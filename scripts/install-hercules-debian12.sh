#!/usr/bin/env bash
# Hercules Ragnarok Online server installer for Debian 12 (bookworm)
# Tuned for low-resource VPS: 1 CPU / 1 GB RAM
#
# Usage (as root or with sudo):
#   sudo bash scripts/install-hercules-debian12.sh
#
# Optional environment overrides:
#   HERC_USER=hercuser
#   HERC_HOME=/home/hercuser
#   DB_NAME=hercules
#   DB_USER=hercules
#   DB_PASS='change_me'
#   SERVER_IP=127.0.0.1          # public/LAN IP clients connect to
#   INTER_USER=s1
#   INTER_PASS=p1               # change before going public
#   SWAP_GB=2
#   HERC_BRANCH=stable          # or a tag like v2026.07
#   ENABLE_RENEWAL=ON           # ON = renewal, OFF = pre-renewal
#   PACKETVER=                  # e.g. 20211103 — leave empty for Hercules default
#   SKIP_BUILD=0
#   SKIP_DB=0

set -euo pipefail

HERC_USER="${HERC_USER:-hercuser}"
HERC_HOME="${HERC_HOME:-/home/${HERC_USER}}"
HERC_DIR="${HERC_DIR:-${HERC_HOME}/Hercules}"
DB_NAME="${DB_NAME:-hercules}"
DB_USER="${DB_USER:-hercules}"
DB_PASS="${DB_PASS:-$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)}"
SERVER_IP="${SERVER_IP:-127.0.0.1}"
INTER_USER="${INTER_USER:-s1}"
INTER_PASS="${INTER_PASS:-p1}"
SWAP_GB="${SWAP_GB:-2}"
HERC_BRANCH="${HERC_BRANCH:-stable}"
ENABLE_RENEWAL="${ENABLE_RENEWAL:-ON}"
PACKETVER="${PACKETVER:-}"
SKIP_BUILD="${SKIP_BUILD:-0}"
SKIP_DB="${SKIP_DB:-0}"
MARIA_CONF="/etc/mysql/mariadb.conf.d/99-hercules-lowmem.cnf"
CREDENTIALS_FILE="${HERC_HOME}/hercules-credentials.txt"

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Run this script as root (or with sudo)."
  fi
}

detect_debian() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "debian" && "${ID_LIKE:-}" != *"debian"* ]]; then
      warn "This script targets Debian 12; detected ${PRETTY_NAME:-unknown}. Continuing anyway."
    fi
  fi
}

setup_swap() {
  local swapfile="/swapfile"

  log "Checking swap (needed for compiling on 1 GB RAM)"
  local current_swap
  current_swap="$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)"
  if [[ "${current_swap}" -ge $((SWAP_GB * 1024 * 900)) ]]; then
    log "Swap already present (${current_swap} kB). Skipping."
    return
  fi

  if [[ -f "${swapfile}" ]]; then
    warn "${swapfile} exists but swap is low; recreating."
    swapoff "${swapfile}" 2>/dev/null || true
    rm -f "${swapfile}"
  fi

  log "Creating ${SWAP_GB}G swap at ${swapfile}"
  if command -v fallocate >/dev/null 2>&1; then
    fallocate -l "${SWAP_GB}G" "${swapfile}" || dd if=/dev/zero of="${swapfile}" bs=1M count=$((SWAP_GB * 1024)) status=progress
  else
    dd if=/dev/zero of="${swapfile}" bs=1M count=$((SWAP_GB * 1024)) status=progress
  fi
  chmod 600 "${swapfile}"
  mkswap "${swapfile}"
  swapon "${swapfile}"

  if ! grep -qE '^/swapfile\s' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi

  sysctl -w vm.swappiness=10 >/dev/null
  if ! grep -q '^vm.swappiness=' /etc/sysctl.conf 2>/dev/null; then
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
  fi
}

install_packages() {
  log "Updating apt and installing build/runtime packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    ca-certificates \
    curl \
    git \
    screen \
    dos2unix \
    cmake \
    ninja-build \
    make \
    gcc \
    g++ \
    python3 \
    python3-venv \
    python3-pip \
    mariadb-server \
    mariadb-client \
    zlib1g-dev \
    libpcre3-dev \
    libssl-dev \
    pkg-config \
    openssl
}

tune_mariadb() {
  log "Tuning MariaDB for ~1 GB RAM"
  cat > "${MARIA_CONF}" <<'EOF'
[mysqld]
# Low-memory profile for Hercules on 1 GB VPS
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
EOF
  systemctl enable mariadb
  systemctl restart mariadb
}

create_herc_user() {
  log "Ensuring Linux user '${HERC_USER}' exists"
  if ! id "${HERC_USER}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${HERC_USER}"
    log "Created user ${HERC_USER}. Set a password with: passwd ${HERC_USER}"
  fi
  mkdir -p "${HERC_HOME}"
  chown -R "${HERC_USER}:${HERC_USER}" "${HERC_HOME}"
}

clone_hercules() {
  log "Cloning Hercules (${HERC_BRANCH}) into ${HERC_DIR}"
  if [[ -d "${HERC_DIR}/.git" ]]; then
    sudo -u "${HERC_USER}" git -C "${HERC_DIR}" fetch --all --tags
    sudo -u "${HERC_USER}" git -C "${HERC_DIR}" checkout "${HERC_BRANCH}"
    sudo -u "${HERC_USER}" git -C "${HERC_DIR}" pull --ff-only || true
  else
    sudo -u "${HERC_USER}" git clone --branch "${HERC_BRANCH}" --depth 1 \
      https://github.com/HerculesWS/Hercules.git "${HERC_DIR}"
  fi

  # Import templates must be copied once into conf/import
  if [[ ! -d "${HERC_DIR}/conf/import" ]]; then
    if [[ -d "${HERC_DIR}/conf/import-tmpl" ]]; then
      sudo -u "${HERC_USER}" cp -a "${HERC_DIR}/conf/import-tmpl" "${HERC_DIR}/conf/import"
    else
      sudo -u "${HERC_USER}" mkdir -p "${HERC_DIR}/conf/import"
    fi
  fi
}

setup_database() {
  [[ "${SKIP_DB}" == "1" ]] && { log "SKIP_DB=1, skipping database setup"; return; }

  log "Creating MariaDB database and user"
  mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

  log "Importing SQL schema"
  local sql_dir="${HERC_DIR}/sql-files"
  [[ -d "${sql_dir}" ]] || die "Missing ${sql_dir}"

  mysql -u root "${DB_NAME}" < "${sql_dir}/main.sql"
  mysql -u root "${DB_NAME}" < "${sql_dir}/logs.sql"

  if [[ "${ENABLE_RENEWAL}" == "ON" ]]; then
    [[ -f "${sql_dir}/item_db_re.sql" ]] && mysql -u root "${DB_NAME}" < "${sql_dir}/item_db_re.sql"
    [[ -f "${sql_dir}/mob_db_re.sql" ]] && mysql -u root "${DB_NAME}" < "${sql_dir}/mob_db_re.sql"
    [[ -f "${sql_dir}/mob_skill_db_re.sql" ]] && mysql -u root "${DB_NAME}" < "${sql_dir}/mob_skill_db_re.sql"
  else
    [[ -f "${sql_dir}/item_db.sql" ]] && mysql -u root "${DB_NAME}" < "${sql_dir}/item_db.sql"
    [[ -f "${sql_dir}/mob_db.sql" ]] && mysql -u root "${DB_NAME}" < "${sql_dir}/mob_db.sql"
    [[ -f "${sql_dir}/mob_skill_db.sql" ]] && mysql -u root "${DB_NAME}" < "${sql_dir}/mob_skill_db.sql"
  fi

  for f in item_db2.sql mob_db2.sql mob_skill_db2.sql; do
    [[ -f "${sql_dir}/${f}" ]] && mysql -u root "${DB_NAME}" < "${sql_dir}/${f}" || true
  done

  # Ensure inter-server account exists / matches config (main.sql already seeds s1/p1)
  mysql -u root "${DB_NAME}" <<SQL
INSERT INTO \`login\` (\`account_id\`, \`userid\`, \`user_pass\`, \`sex\`, \`email\`)
VALUES (1, '${INTER_USER}', '${INTER_PASS}', 'S', 'athena@athena.com')
ON DUPLICATE KEY UPDATE \`userid\`=VALUES(\`userid\`), \`user_pass\`=VALUES(\`user_pass\`), \`sex\`='S';
SQL
}

write_configs() {
  log "Writing Hercules SQL + import configs"

  local sql_conf="${HERC_DIR}/conf/global/sql_connection.conf"
  [[ -f "${sql_conf}" ]] || die "Missing ${sql_conf}"

  # Prefer editing the shared SQL connection file (included by all servers)
  sed -i \
    -e "s/db_hostname: \".*\"/db_hostname: \"127.0.0.1\"/" \
    -e "s/db_username: \".*\"/db_username: \"${DB_USER}\"/" \
    -e "s/db_password: \".*\"/db_password: \"${DB_PASS}\"/" \
    -e "s/db_database: \".*\"/db_database: \"${DB_NAME}\"/" \
    "${sql_conf}"

  local import_dir="${HERC_DIR}/conf/import"
  mkdir -p "${import_dir}"

  cat > "${import_dir}/inter-server.conf" <<EOF
// Auto-generated by install-hercules-debian12.sh
inter_configuration: {
}
EOF

  cat > "${import_dir}/login-server.conf" <<EOF
// Auto-generated by install-hercules-debian12.sh
login_configuration: {
	login_port: 6900
}
EOF

  cat > "${import_dir}/char-server.conf" <<EOF
// Auto-generated by install-hercules-debian12.sh
char_configuration: {
	server_name: "Ranarokx"
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

  cat > "${import_dir}/map-server.conf" <<EOF
// Auto-generated by install-hercules-debian12.sh
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

  chown -R "${HERC_USER}:${HERC_USER}" "${HERC_DIR}/conf"
}

build_hercules() {
  [[ "${SKIP_BUILD}" == "1" ]] && { log "SKIP_BUILD=1, skipping compile"; return; }

  log "Building Hercules with CMake/Conan (1 job — slow but safe on 1 GB RAM)"
  export CMAKE_BUILD_PARALLEL_LEVEL=1
  export MAKEFLAGS="-j1"

  local packetver_arg=""
  if [[ -n "${PACKETVER}" ]]; then
    packetver_arg="-DPACKETVER=${PACKETVER}"
  fi

  sudo -u "${HERC_USER}" env \
    CMAKE_BUILD_PARALLEL_LEVEL=1 \
    MAKEFLAGS="-j1" \
    HERC_DIR="${HERC_DIR}" \
    ENABLE_RENEWAL="${ENABLE_RENEWAL}" \
    PACKETVER_ARG="${packetver_arg}" \
    bash <<'EOF'
set -euo pipefail
cd "${HERC_DIR}"

# setup_env.sh must be sourced into the current shell
set +u
. ./setup_env.sh --build-type RelWithDebInfo
set -u

# Reconfigure with our options (tests off to save RAM/time)
# shellcheck disable=SC2086
cmake -S "${HERC_DIR}" -B "${HERC_DIR}/build" \
  -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=cmake_modules/conan_provider.cmake \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DENABLE_TESTING=OFF \
  -DENABLE_RENEWAL="${ENABLE_RENEWAL}" \
  ${PACKETVER_ARG} \
  -G Ninja

cmake --build "${HERC_DIR}/build" --target all --parallel 1
cmake --install "${HERC_DIR}/build"
EOF

  if [[ -f "${HERC_DIR}/athena-start" ]]; then
    chmod a+x "${HERC_DIR}/athena-start"
    dos2unix "${HERC_DIR}/athena-start" 2>/dev/null || true
  fi
  chown -R "${HERC_USER}:${HERC_USER}" "${HERC_DIR}"
}

write_credentials() {
  umask 077
  cat > "${CREDENTIALS_FILE}" <<EOF
Hercules install credentials ($(date -u +%Y-%m-%dT%H:%MZ))
================================================
Linux user:     ${HERC_USER}
Hercules path:  ${HERC_DIR}
Server IP:      ${SERVER_IP}
Branch:         ${HERC_BRANCH}
Renewal:        ${ENABLE_RENEWAL}
PACKETVER:      ${PACKETVER:-<Hercules default>}

MariaDB database: ${DB_NAME}
MariaDB user:     ${DB_USER}
MariaDB password: ${DB_PASS}

Inter-server userid: ${INTER_USER}
Inter-server passwd: ${INTER_PASS}

Ports (open in firewall if public):
  login  6900/tcp
  char   6121/tcp
  map    5121/tcp

Start:
  su - ${HERC_USER}
  cd ${HERC_DIR}
  ./athena-start start

Stop / restart:
  ./athena-start stop
  ./athena-start restart

IMPORTANT:
  Change INTER_USER/INTER_PASS and DB_PASS before exposing the server publicly.
  Client PACKETVER must match the compiled server (-DPACKETVER=YYYYMMDD).
EOF
  chown "${HERC_USER}:${HERC_USER}" "${CREDENTIALS_FILE}"
  chmod 600 "${CREDENTIALS_FILE}"
}

open_firewall_hint() {
  if command -v ufw >/dev/null 2>&1; then
    log "UFW detected. To allow game ports: ufw allow 6900,6121,5121/tcp && ufw reload"
  fi
}

main() {
  require_root
  detect_debian
  setup_swap
  install_packages
  tune_mariadb
  create_herc_user
  clone_hercules
  setup_database
  write_configs
  build_hercules
  write_credentials
  open_firewall_hint

  cat <<EOF

============================================================
Hercules install finished.
============================================================
Credentials saved to: ${CREDENTIALS_FILE}

Next steps on the VPS:
  1) su - ${HERC_USER}
  2) cd ${HERC_DIR}
  3) ./athena-start start

Point your RO client at ${SERVER_IP}:6900
If login fails with wrong PACKETVER, rebuild with:
  PACKETVER=YYYYMMDD sudo -E bash scripts/install-hercules-debian12.sh
============================================================
EOF
}

main "$@"
