#!/usr/bin/env bash
# Install OpenKore on Debian/Ubuntu and point it at Hercules.
#
# Ranarokx = 2 servers only:
#   1) Linux game host → Hercules (+ optional OpenKore on THIS same box)
#   2) Windows host    → RO client only
#
# Recommended (same Linux game host):
#   sudo SERVER_IP=127.0.0.1 bash scripts/install-openkore-linux.sh
#
# Defaults:
#   SERVER_IP=127.0.0.1
#   SERVER_PORT=6900
#   PACKETVER-compatible serverType ≈ kRO_RagexeRE_2018_11_21
#   Accounts: admin/admin123 or test/test123
#   forceMapIP 127.0.0.1 (same-host hairpin fix)
#
# Overrides:
#   SERVER_IP=x.x.x.x
#   SERVER_PORT=6900
#   SERVER_TITLE=Ranarokx
#   OK_USER=admin
#   OK_PASS=admin123
#   SERVER_TYPE=kRO_RagexeRE_2018_11_21
#   CHAR_BLOCK_SIZE=155
#   OPENKORE_DIR=/opt/openkore
#   RUN_USER=openkore

set -euo pipefail

SERVER_IP="${SERVER_IP:-127.0.0.1}"
SERVER_PORT="${SERVER_PORT:-6900}"
SERVER_TITLE="${SERVER_TITLE:-Ranarokx}"
OK_USER="${OK_USER:-admin}"
OK_PASS="${OK_PASS:-admin123}"
# Classic Hercules login works better with 2018-11-21 + patched recvpackets
# (2020 type can trigger token/0AE3 flow). Override if needed.
SERVER_TYPE="${SERVER_TYPE:-kRO_RagexeRE_2018_11_21}"
CHAR_BLOCK_SIZE="${CHAR_BLOCK_SIZE:-155}"
MASTER_VERSION="${MASTER_VERSION:-1}"
VERSION="${VERSION:-55}"
OPENKORE_DIR="${OPENKORE_DIR:-/opt/openkore}"
RUN_USER="${RUN_USER:-openkore}"
OPENKORE_REPO="${OPENKORE_REPO:-https://github.com/OpenKore/openkore.git}"

log()  { printf '\n==> %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run with sudo: sudo bash $0"
}

install_deps() {
  log "Installing OpenKore dependencies"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    git build-essential g++ make \
    perl perl-base \
    libtime-hires-perl \
    libio-compress-perl \
    libreadline-dev \
    libcurl4-openssl-dev \
    python3 \
    python-is-python3 \
    screen curl ca-certificates
}

fix_quests_utf8() {
  # OpenKore refuses non-UTF-8 table files and exits
  local q="${OPENKORE_DIR}/tables/translated/kRO_english/quests.txt"
  if [[ -f "${q}" ]]; then
    log "Ensuring quests.txt is UTF-8"
    if ! iconv -f UTF-8 -t UTF-8 "${q}" -o /dev/null 2>/dev/null; then
      iconv -f LATIN1 -t UTF-8 "${q}" -o "${q}.utf8"
      mv "${q}.utf8" "${q}"
      chown "${RUN_USER}:${RUN_USER}" "${q}"
    fi
  fi
}

patch_hercules_recvpackets() {
  # PACKETVER ~20190530 Hercules private-server packet lengths used in testing
  local rp="${OPENKORE_DIR}/tables/kRO/recvpackets.txt"
  [[ -f "${rp}" ]] || die "Missing ${rp}"
  log "Patching kRO recvpackets.txt for Hercules"
  local begin="# >>> RANAROKX_PACKETS_BEGIN"
  local end="# <<< RANAROKX_PACKETS_END"
  python3 - "${rp}" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
begin = "# >>> RANAROKX_PACKETS_BEGIN\n"
end = "# <<< RANAROKX_PACKETS_END\n"
block = begin + "\n".join([
    "0AC4 0",
    "0AE3 0",
    "082D 0",
    "08B9 12",
    "099D 0",
    "09A0 4",
    "0AC5 156",
    "0AC7 156",
    "09E7 3",
    "0B18 4",
    "0ADE 6",
    "0A23 -1",
    "0ADC 6",
    "0ADD 24",
    "0AE0 30",
    "0AE1 28",
]) + "\n" + end
text = path.read_text()
if begin in text and end in text:
    pre = text.split(begin, 1)[0]
    post = text.split(end, 1)[1]
    text = pre + block + post
else:
    if not text.endswith("\n"):
        text += "\n"
    text += "\n" + block
path.write_text(text)
PY
  chown "${RUN_USER}:${RUN_USER}" "${rp}"
}

create_user() {
  log "Ensuring user ${RUN_USER}"
  if ! id "${RUN_USER}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${RUN_USER}"
  fi
}

clone_openkore() {
  log "Cloning OpenKore into ${OPENKORE_DIR}"
  if [[ -d "${OPENKORE_DIR}/.git" ]]; then
    git -C "${OPENKORE_DIR}" fetch --all
    git -C "${OPENKORE_DIR}" pull --ff-only || true
  else
    rm -rf "${OPENKORE_DIR}"
    git clone --depth 1 "${OPENKORE_REPO}" "${OPENKORE_DIR}"
  fi
  chown -R "${RUN_USER}:${RUN_USER}" "${OPENKORE_DIR}"
}

configure_server() {
  log "Configuring servers.txt + config.txt for ${SERVER_TITLE} @ ${SERVER_IP}:${SERVER_PORT}"
  local servers="${OPENKORE_DIR}/tables/servers.txt"
  local config="${OPENKORE_DIR}/control/config.txt"
  [[ -f "${servers}" ]] || die "Missing ${servers}"
  [[ -f "${config}" ]] || die "Missing ${config}"

  python3 - "${servers}" "${config}" \
    "${SERVER_TITLE}" "${SERVER_IP}" "${SERVER_PORT}" \
    "${MASTER_VERSION}" "${VERSION}" "${SERVER_TYPE}" "${CHAR_BLOCK_SIZE}" \
    "${OK_USER}" "${OK_PASS}" <<'PY'
from pathlib import Path
import sys

(
    servers_path,
    config_path,
    title,
    ip,
    port,
    master_version,
    version,
    server_type,
    char_block,
    user,
    password,
) = sys.argv[1:]

BEGIN = "# >>> RANAROKX_BEGIN\n"
END = "# <<< RANAROKX_END\n"

block = f"""{BEGIN}
[{title}]
ip {ip}
port {port}
private 1
master_version {master_version}
version {version}
serverType {server_type}
serverEncoding Western
charBlockSize {char_block}
addTableFolders translated/kRO_english;kRO
pinCode 0
{END}"""

text = Path(servers_path).read_text()
if BEGIN in text and END in text:
    pre = text.split(BEGIN, 1)[0]
    post = text.split(END, 1)[1]
    text = pre + block + post
else:
    if not text.endswith("\n"):
        text += "\n"
    text += "\n" + block
Path(servers_path).write_text(text)

# Patch control/config.txt keys (lines are "key" or "key value")
keys = {
    "master": title,
    "username": user,
    "password": password,
    "XKore": "0",
}
out = []
seen = set()
for line in Path(config_path).read_text().splitlines(True):
    raw = line.rstrip("\n")
    if not raw or raw.lstrip().startswith("#"):
        out.append(line)
        continue
    parts = raw.split(None, 1)
    k = parts[0]
    if k in keys:
        out.append(f"{k} {keys[k]}\n")
        seen.add(k)
    else:
        out.append(line)
for k, v in keys.items():
    if k not in seen:
        out.insert(0, f"{k} {v}\n")

# When bot runs on the same host as Hercules, public map_ip is unreachable (NAT hairpin).
if ip in ("127.0.0.1", "localhost"):
    # replace or append forceMapIP
    replaced = False
    new_out = []
    for line in out:
        raw = line.rstrip("\n")
        if raw.split(None, 1)[:1] == ["forceMapIP"]:
            new_out.append("forceMapIP 127.0.0.1\n")
            replaced = True
        else:
            new_out.append(line)
    if not replaced:
        new_out.insert(0, "forceMapIP 127.0.0.1\n")
    out = new_out

Path(config_path).write_text("".join(out))
PY

  chown -R "${RUN_USER}:${RUN_USER}" "${OPENKORE_DIR}/tables" "${OPENKORE_DIR}/control"
}

compile_xstools() {
  log "Compiling XSTools"
  sudo -u "${RUN_USER}" bash -lc "
    cd '${OPENKORE_DIR}'
    make clean || true
    make -j\"\$(nproc)\"
  "
}

write_helpers() {
  log "Writing helper scripts"
  cat > "${OPENKORE_DIR}/start-openkore.sh" <<EOF
#!/usr/bin/env bash
cd "${OPENKORE_DIR}"
exec perl ./openkore.pl "\$@"
EOF
  chmod a+x "${OPENKORE_DIR}/start-openkore.sh"

  cat > /usr/local/bin/openkore-ranarokx <<EOF
#!/usr/bin/env bash
# Start OpenKore in screen as ${RUN_USER}
sudo -u ${RUN_USER} screen -S openkore -X quit 2>/dev/null || true
sudo -u ${RUN_USER} screen -dmS openkore bash -lc 'cd ${OPENKORE_DIR} && perl ./openkore.pl'
echo "OpenKore started in screen session 'openkore'"
echo "Attach with: sudo -u ${RUN_USER} screen -r openkore"
EOF
  chmod a+x /usr/local/bin/openkore-ranarokx

  cat > "${OPENKORE_DIR}/CREDENTIALS.txt" <<EOF
OpenKore → Hercules (${SERVER_TITLE})
=====================================
OpenKore path: ${OPENKORE_DIR}
Linux user:    ${RUN_USER}

Hercules IP:   ${SERVER_IP}
Login port:    ${SERVER_PORT}
serverType:    ${SERVER_TYPE}
charBlockSize: ${CHAR_BLOCK_SIZE}

Login user:    ${OK_USER}
Login pass:    ${OK_PASS}

Start (foreground):
  sudo -u ${RUN_USER} -i
  cd ${OPENKORE_DIR}
  perl ./openkore.pl

Start (background screen):
  openkore-ranarokx
  sudo -u ${RUN_USER} screen -r openkore

If login fails with packet errors, try another SERVER_TYPE near PACKETVER 20190530:
  sudo SERVER_TYPE=kRO_RagexeRE_2020_03_04a bash $(basename "$0")
EOF
  chown "${RUN_USER}:${RUN_USER}" "${OPENKORE_DIR}/CREDENTIALS.txt" "${OPENKORE_DIR}/start-openkore.sh"
}

main() {
  require_root
  install_deps
  create_user
  clone_openkore
  configure_server
  fix_quests_utf8
  patch_hercules_recvpackets
  compile_xstools
  write_helpers

  cat <<EOF

============================================================
OpenKore install complete
============================================================
Configured for Hercules at ${SERVER_IP}:${SERVER_PORT}
Account: ${OK_USER} / ${OK_PASS}

Start now:
  openkore-ranarokx

Or interactively:
  sudo -u ${RUN_USER} -i
  cd ${OPENKORE_DIR}
  perl ./openkore.pl

Details: ${OPENKORE_DIR}/CREDENTIALS.txt
============================================================
EOF
}

main "$@"
