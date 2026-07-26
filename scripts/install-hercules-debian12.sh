#!/usr/bin/env bash
# Hercules installer for Debian 12 — battle-tested for 1 CPU / 1 GB RAM
#
# Incorporates fixes from a full manual install:
#   - 2G swap before compile
#   - MariaDB low-memory tuning
#   - DB users for both localhost AND 127.0.0.1
#   - db_hostname = 127.0.0.1 (TCP; avoids /tmp/mysql.sock Conan client issue)
#   - Manual venv/conan/cmake build (setup_env.sh breaks on login shells: $0=-bash)
#   - Single-job compile (-j1) to avoid OOM
#   - login_ip/char_ip/map_ip set in main conf files (not only import)
#   - Optional screen start + test/GM accounts
#
# Usage (as root):
#   curl -fsSL ... | bash          # or:
#   sudo bash scripts/install-hercules-debian12.sh
#
# Common overrides:
#   SERVER_IP=93.127.134.131       # public IP clients use (auto-detected if unset)
#   DB_PASS=ragnarok
#   HERC_PASS=ragnarok             # Linux password for hercuser
#   PACKETVER=20190530             # leave empty for Hercules default
#   ENABLE_RENEWAL=ON
#   START_SERVER=1                 # start in screen when done
#   CREATE_ACCOUNTS=1              # create test + admin accounts

set -euo pipefail

HERC_USER="${HERC_USER:-hercuser}"
HERC_PASS="${HERC_PASS:-ragnarok}"
HERC_HOME="${HERC_HOME:-/home/${HERC_USER}}"
HERC_DIR="${HERC_DIR:-${HERC_HOME}/Hercules}"
DB_NAME="${DB_NAME:-hercules}"
DB_USER="${DB_USER:-hercules}"
DB_PASS="${DB_PASS:-ragnarok}"
INTER_USER="${INTER_USER:-s1}"
INTER_PASS="${INTER_PASS:-p1}"
SWAP_GB="${SWAP_GB:-2}"
HERC_BRANCH="${HERC_BRANCH:-stable}"
ENABLE_RENEWAL="${ENABLE_RENEWAL:-ON}"
PACKETVER="${PACKETVER:-}"
SKIP_BUILD="${SKIP_BUILD:-0}"
SKIP_DB="${SKIP_DB:-0}"
START_SERVER="${START_SERVER:-1}"
CREATE_ACCOUNTS="${CREATE_ACCOUNTS:-1}"
TEST_USER="${TEST_USER:-test}"
TEST_PASS="${TEST_PASS:-test123}"
GM_USER="${GM_USER:-admin}"
GM_PASS="${GM_PASS:-admin123}"
GM_GROUP="${GM_GROUP:-99}"
SERVER_NAME="${SERVER_NAME:-Ranarokx}"
MARIA_CONF="/etc/mysql/mariadb.conf.d/99-hercules-lowmem.cnf"
CREDENTIALS_FILE="${HERC_HOME}/hercules-credentials.txt"

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run as root: sudo bash $0"
}

detect_ips() {
  local pub="" local_ip=""
  pub="$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "${pub}" ]]; then
    pub="$(curl -4 -fsS --max-time 8 https://ifconfig.me 2>/dev/null || true)"
  fi
  local_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
  if [[ -z "${local_ip}" ]]; then
    local_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi

  if [[ -z "${SERVER_IP:-}" || "${SERVER_IP}" == "127.0.0.1" ]]; then
    if [[ -n "${pub}" ]]; then
      SERVER_IP="${pub}"
    elif [[ -n "${local_ip}" ]]; then
      SERVER_IP="${local_ip}"
      warn "Could not detect public IP; using local IP ${SERVER_IP}"
    else
      SERVER_IP="127.0.0.1"
      warn "No IP detected; using 127.0.0.1 (clients on other PCs will not connect)"
    fi
  fi
  LOCAL_IP="${LOCAL_IP:-${local_ip:-127.0.0.1}}"
  log "Client/public IP (char_ip/map_ip): ${SERVER_IP}"
  log "Local NIC IP: ${LOCAL_IP}"
}

setup_swap() {
  local swapfile="/swapfile"
  log "Ensuring ${SWAP_GB}G swap (required to compile on 1 GB RAM)"
  local current_swap
  current_swap="$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)"
  if [[ "${current_swap}" -ge $((SWAP_GB * 1024 * 900)) ]]; then
    log "Swap already present (${current_swap} kB)"
    return
  fi
  if [[ -f "${swapfile}" ]]; then
    swapoff "${swapfile}" 2>/dev/null || true
    rm -f "${swapfile}"
  fi
  if command -v fallocate >/dev/null 2>&1; then
    fallocate -l "${SWAP_GB}G" "${swapfile}" || dd if=/dev/zero of="${swapfile}" bs=1M count=$((SWAP_GB * 1024)) status=progress
  else
    dd if=/dev/zero of="${swapfile}" bs=1M count=$((SWAP_GB * 1024)) status=progress
  fi
  chmod 600 "${swapfile}"
  mkswap "${swapfile}"
  swapon "${swapfile}"
  grep -qE '^/swapfile\s' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -w vm.swappiness=10 >/dev/null
  grep -q '^vm.swappiness=' /etc/sysctl.conf 2>/dev/null || echo 'vm.swappiness=10' >> /etc/sysctl.conf
}

install_packages() {
  log "Installing packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    ca-certificates curl git screen dos2unix \
    cmake ninja-build make gcc g++ \
    python3 python3-venv python3-pip \
    mariadb-server mariadb-client \
    zlib1g-dev libpcre3-dev libssl-dev pkg-config openssl \
    iproute2
}

tune_mariadb() {
  log "Tuning MariaDB for ~1 GB RAM"
  cat > "${MARIA_CONF}" <<'EOF'
[mysqld]
performance_schema = OFF
innodb_buffer_pool_size = 64M
innodb_log_buffer_size = 8M
key_buffer_size = 8M
tmp_table_size = 16M
max_heap_table_size = 16M
max_connections = 40
table_open_cache = 200
thread_cache_size = 4
query_cache_type = 0
skip_name_resolve = ON
bind-address = 127.0.0.1
EOF
  systemctl enable mariadb
  systemctl restart mariadb
  # Wait until accepting connections
  for _ in $(seq 1 30); do
    mysqladmin ping -uroot --silent 2>/dev/null && break
    sleep 1
  done
  mysqladmin ping -uroot --silent || die "MariaDB failed to start"
}

create_herc_user() {
  log "Ensuring Linux user ${HERC_USER}"
  if ! id "${HERC_USER}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${HERC_USER}"
  fi
  echo "${HERC_USER}:${HERC_PASS}" | chpasswd
  mkdir -p "${HERC_HOME}"
  chown -R "${HERC_USER}:${HERC_USER}" "${HERC_HOME}"
}

clone_hercules() {
  log "Cloning Hercules (${HERC_BRANCH})"
  if [[ -d "${HERC_DIR}/.git" ]]; then
    sudo -u "${HERC_USER}" git -C "${HERC_DIR}" fetch --all --tags
    sudo -u "${HERC_USER}" git -C "${HERC_DIR}" checkout "${HERC_BRANCH}"
    sudo -u "${HERC_USER}" git -C "${HERC_DIR}" pull --ff-only || true
  else
    rm -rf "${HERC_DIR}"
    sudo -u "${HERC_USER}" git clone --branch "${HERC_BRANCH}" --depth 1 \
      https://github.com/HerculesWS/Hercules.git "${HERC_DIR}"
  fi
  if [[ ! -d "${HERC_DIR}/conf/import" ]]; then
    sudo -u "${HERC_USER}" cp -a "${HERC_DIR}/conf/import-tmpl" "${HERC_DIR}/conf/import"
  fi
}

setup_database() {
  [[ "${SKIP_DB}" == "1" ]] && { log "SKIP_DB=1"; return; }
  log "Creating MariaDB database/users (localhost + 127.0.0.1)"
  mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

  log "Importing SQL schema"
  local sql_dir="${HERC_DIR}/sql-files"
  mysql -u root "${DB_NAME}" < "${sql_dir}/main.sql"
  mysql -u root "${DB_NAME}" < "${sql_dir}/logs.sql"

  if [[ "${ENABLE_RENEWAL}" == "ON" ]]; then
    [[ -f "${sql_dir}/item_db_re.sql" ]] && mysql -u root "${DB_NAME}" < "${sql_dir}/item_db_re.sql" || true
    [[ -f "${sql_dir}/mob_db_re.sql" ]] && mysql -u root "${DB_NAME}" < "${sql_dir}/mob_db_re.sql" || true
    [[ -f "${sql_dir}/mob_skill_db_re.sql" ]] && mysql -u root "${DB_NAME}" < "${sql_dir}/mob_skill_db_re.sql" || true
  else
    [[ -f "${sql_dir}/item_db.sql" ]] && mysql -u root "${DB_NAME}" < "${sql_dir}/item_db.sql" || true
    [[ -f "${sql_dir}/mob_db.sql" ]] && mysql -u root "${DB_NAME}" < "${sql_dir}/mob_db.sql" || true
    [[ -f "${sql_dir}/mob_skill_db.sql" ]] && mysql -u root "${DB_NAME}" < "${sql_dir}/mob_skill_db.sql" || true
  fi
  for f in item_db2.sql mob_db2.sql mob_skill_db2.sql; do
    [[ -f "${sql_dir}/${f}" ]] && mysql -u root "${DB_NAME}" < "${sql_dir}/${f}" || true
  done

  mysql -u root "${DB_NAME}" <<SQL
INSERT INTO \`login\` (\`account_id\`, \`userid\`, \`user_pass\`, \`sex\`, \`email\`)
VALUES (1, '${INTER_USER}', '${INTER_PASS}', 'S', 'athena@athena.com')
ON DUPLICATE KEY UPDATE \`userid\`=VALUES(\`userid\`), \`user_pass\`=VALUES(\`user_pass\`), \`sex\`='S';
SQL

  # Verify TCP login (what Hercules uses)
  mysql -u "${DB_USER}" -p"${DB_PASS}" -h 127.0.0.1 "${DB_NAME}" -e "SELECT 1;" >/dev/null \
    || die "MariaDB TCP auth failed for ${DB_USER}@127.0.0.1"
}

write_configs() {
  log "Writing SQL + server IP configs"
  local sql_conf="${HERC_DIR}/conf/global/sql_connection.conf"
  [[ -f "${sql_conf}" ]] || die "Missing ${sql_conf}"

  # Use 127.0.0.1 TCP — Conan MariaDB client looks for /tmp/mysql.sock with "localhost"
  sed -i \
    -e 's/db_hostname: ".*"/db_hostname: "127.0.0.1"/' \
    -e "s/db_username: \".*\"/db_username: \"${DB_USER}\"/" \
    -e "s/db_password: \".*\"/db_password: \"${DB_PASS}\"/" \
    -e "s/db_database: \".*\"/db_database: \"${DB_NAME}\"/" \
    "${sql_conf}"

  # Patch MAIN conf files (uncomment or replace keys). Import alone was not enough
  # on some hosts where auto-detect picked the virt NIC (e.g. 192.168.122.33).
  python3 - "${HERC_DIR}" "${SERVER_IP}" <<'PY'
import sys
from pathlib import Path

herc, server_ip = sys.argv[1], sys.argv[2]

def force_key(path: Path, key: str, value: str) -> None:
    lines = path.read_text().splitlines(True)
    out = []
    for line in lines:
        stripped = line.lstrip()
        indent = line[: len(line) - len(stripped)]
        if stripped.startswith(f"{key}:") or stripped.startswith(f"//{key}:"):
            out.append(f'{indent}{key}: "{value}"\n')
        else:
            out.append(line)
    path.write_text("".join(out))

force_key(Path(herc) / "conf/char/char-server.conf", "login_ip", "127.0.0.1")
force_key(Path(herc) / "conf/char/char-server.conf", "char_ip", server_ip)
force_key(Path(herc) / "conf/map/map-server.conf", "char_ip", "127.0.0.1")
force_key(Path(herc) / "conf/map/map-server.conf", "map_ip", server_ip)
PY

  mkdir -p "${HERC_DIR}/conf/import"
  cat > "${HERC_DIR}/conf/import/char-server.conf" <<EOF
char_configuration: {
	server_name: "${SERVER_NAME}"
	inter: {
		userid: "${INTER_USER}"
		passwd: "${INTER_PASS}"
		login_ip: "127.0.0.1"
		char_ip: "${SERVER_IP}"
		char_port: 6121
		login_port: 6900
	}
}
EOF
  cat > "${HERC_DIR}/conf/import/map-server.conf" <<EOF
map_configuration: {
	inter: {
		userid: "${INTER_USER}"
		passwd: "${INTER_PASS}"
		char_ip: "127.0.0.1"
		map_ip: "${SERVER_IP}"
		map_port: 5121
		char_port: 6121
	}
}
EOF
  cat > "${HERC_DIR}/conf/import/login-server.conf" <<'EOF'
login_configuration: {
	login_port: 6900
}
EOF

  chown -R "${HERC_USER}:${HERC_USER}" "${HERC_DIR}/conf"
}

build_hercules() {
  [[ "${SKIP_BUILD}" == "1" ]] && { log "SKIP_BUILD=1"; return; }
  log "Building Hercules (venv + conan + cmake, -j1) — this takes a long time on 1 vCPU"

  local packetver_arg=""
  if [[ -n "${PACKETVER}" ]]; then
    packetver_arg="-DPACKETVER=${PACKETVER}"
  fi

  # Do NOT use setup_env.sh — it breaks when sourced from a login shell ($0 == -bash)
  sudo -u "${HERC_USER}" env \
    HOME="${HERC_HOME}" \
    HERC_DIR="${HERC_DIR}" \
    ENABLE_RENEWAL="${ENABLE_RENEWAL}" \
    PACKETVER_ARG="${packetver_arg}" \
    CMAKE_BUILD_PARALLEL_LEVEL=1 \
    MAKEFLAGS="-j1" \
    bash <<'EOF'
set -euo pipefail
cd "${HERC_DIR}"

python3 -m venv .venv
# shellcheck disable=SC1091
. .venv/bin/activate
pip install --upgrade pip
pip install 'conan>=2,<3'

cmake -S . -B build \
  -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=cmake_modules/conan_provider.cmake \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DENABLE_TESTING=OFF \
  -DENABLE_RENEWAL="${ENABLE_RENEWAL}" \
  ${PACKETVER_ARG} \
  -G Ninja

cmake --build build --parallel 1
cmake --install build
chmod a+x athena-start
dos2unix athena-start 2>/dev/null || true
test -x bin/login-server
test -x bin/char-server
test -x bin/map-server
EOF

  chown -R "${HERC_USER}:${HERC_USER}" "${HERC_DIR}"
}

create_game_accounts() {
  [[ "${CREATE_ACCOUNTS}" == "1" ]] || return
  log "Creating player (${TEST_USER}) and GM (${GM_USER}) accounts"
  mysql -u root "${DB_NAME}" <<SQL
INSERT INTO \`login\` (\`userid\`, \`user_pass\`, \`sex\`, \`email\`, \`group_id\`)
VALUES ('${TEST_USER}', '${TEST_PASS}', 'M', '${TEST_USER}@localhost', 0)
ON DUPLICATE KEY UPDATE \`user_pass\`=VALUES(\`user_pass\`), \`group_id\`=0;

INSERT INTO \`login\` (\`userid\`, \`user_pass\`, \`sex\`, \`email\`, \`group_id\`)
VALUES ('${GM_USER}', '${GM_PASS}', 'M', '${GM_USER}@localhost', ${GM_GROUP})
ON DUPLICATE KEY UPDATE \`user_pass\`=VALUES(\`user_pass\`), \`group_id\`=${GM_GROUP};
SQL
}

install_systemd() {
  local unit="/etc/systemd/system/hercules.service"
  log "Installing systemd unit ${unit}"
  cat > "${unit}" <<EOF
[Unit]
Description=Hercules Ragnarok Online
After=network.target mariadb.service
Wants=mariadb.service

[Service]
Type=forking
User=${HERC_USER}
Group=${HERC_USER}
WorkingDirectory=${HERC_DIR}
ExecStart=${HERC_DIR}/athena-start start
ExecStop=${HERC_DIR}/athena-start stop
Restart=on-failure
RestartSec=5
LimitNOFILE=8192

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

start_server_screen() {
  [[ "${START_SERVER}" == "1" ]] || return
  log "Starting Hercules inside screen session 'hercules'"
  pkill -u "${HERC_USER}" -f 'login-server|char-server|map-server|api-server' 2>/dev/null || true
  sleep 1

  # Kill old screen session if any
  sudo -u "${HERC_USER}" screen -S hercules -X quit 2>/dev/null || true

  sudo -u "${HERC_USER}" screen -dmS hercules bash -lc "
    cd '${HERC_DIR}'
    ./bin/login-server > log/login-server.run.log 2>&1 &
    sleep 2
    ./bin/char-server  > log/char-server.run.log 2>&1 &
    sleep 2
    ./bin/map-server   > log/map-server.run.log 2>&1 &
    if [[ -x ./bin/api-server ]]; then
      sleep 1
      ./bin/api-server > log/api-server.run.log 2>&1 &
    fi
    echo 'Servers launched. Use: screen -r hercules'
    exec bash
  "

  sleep 4
  if ss -lnt | grep -q ':6900'; then
    log "login-server is listening on :6900"
  else
    warn "login-server not listening yet — check ${HERC_DIR}/log/login-server.run.log"
    warn "or: sudo -u ${HERC_USER} screen -r hercules"
  fi
}

write_credentials() {
  umask 077
  mkdir -p "$(dirname "${CREDENTIALS_FILE}")"
  cat > "${CREDENTIALS_FILE}" <<EOF
Hercules install — $(date -u +%Y-%m-%dT%H:%MZ)
=============================================
Linux user / pass:  ${HERC_USER} / ${HERC_PASS}
Hercules path:      ${HERC_DIR}
Public/client IP:   ${SERVER_IP}
Local NIC IP:       ${LOCAL_IP}
Branch:             ${HERC_BRANCH}
Renewal:            ${ENABLE_RENEWAL}
PACKETVER:          ${PACKETVER:-<Hercules default — check login-server log>}

MariaDB db/user/pass: ${DB_NAME} / ${DB_USER} / ${DB_PASS}
Inter-server:         ${INTER_USER} / ${INTER_PASS}

Player account:  ${TEST_USER} / ${TEST_PASS}
GM account:      ${GM_USER} / ${GM_PASS}  (group ${GM_GROUP})

Ports: 6900 (login), 6121 (char), 5121 (map)

Reconnect to consoles:
  sudo su - ${HERC_USER}
  screen -r hercules

Systemd (optional):
  sudo systemctl enable --now hercules

Client: point clientinfo to ${SERVER_IP}:6900
EOF
  chown "${HERC_USER}:${HERC_USER}" "${CREDENTIALS_FILE}"
  chmod 600 "${CREDENTIALS_FILE}"
}

main() {
  require_root
  detect_ips
  setup_swap
  install_packages
  tune_mariadb
  create_herc_user
  clone_hercules
  setup_database
  write_configs
  build_hercules
  create_game_accounts
  install_systemd
  mkdir -p "${HERC_DIR}/log"
  chown -R "${HERC_USER}:${HERC_USER}" "${HERC_DIR}"
  start_server_screen
  write_credentials

  cat <<EOF

============================================================
INSTALL COMPLETE
============================================================
Credentials: ${CREDENTIALS_FILE}

Client IP:   ${SERVER_IP}:6900
Player:      ${TEST_USER} / ${TEST_PASS}
GM:          ${GM_USER} / ${GM_PASS}

If ports are not open externally, allow/forward TCP 6900,6121,5121
in your VPS/host firewall (this VM may be behind NAT).

View logs:
  sudo -u ${HERC_USER} screen -r hercules
  # or: tail -f ${HERC_DIR}/log/*.run.log
============================================================
EOF
}

main "$@"
