#!/usr/bin/env bash
# Install the Ranarokx registration site on Linux server #1 (Hercules game host).
# Do NOT run this on the Windows RO client VPS.
#
# Usage (on Hercules Linux host):
#   cd /path/to/Ranarokx
#   sudo bash scripts/install-registration-site.sh
#
# Optional env:
#   SITE_ROOT=/var/www/ranarokx
#   SERVER_NAME=_   (nginx server_name; use your domain or _)
#   DB_HOST=127.0.0.1 DB_NAME=hercules DB_USER=hercules DB_PASS=ragnarok

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_ROOT="${SITE_ROOT:-/var/www/ranarokx}"
SERVER_NAME="${SERVER_NAME:-_}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_NAME="${DB_NAME:-hercules}"
DB_USER="${DB_USER:-hercules}"
DB_PASS="${DB_PASS:-ragnarok}"
CRED_FILE="${CRED_FILE:-/home/hercuser/hercules-credentials.txt}"

log() { echo "[reg-site] $*"; }

# Prefer password from credentials file if present
if [[ -f "${CRED_FILE}" ]]; then
  maybe="$(grep -E -i 'db_?pass|database password|mysql.*pass' "${CRED_FILE}" | head -1 | sed -E 's/.*[: =]//I;s/[[:space:]]+$//' || true)"
  # Keep default unless we find an obvious key=value style
  if grep -q 'DB_PASS=' "${CRED_FILE}" 2>/dev/null; then
    # shellcheck disable=SC1090
    DB_PASS="$(grep '^DB_PASS=' "${CRED_FILE}" | head -1 | cut -d= -f2-)"
  fi
  if grep -q 'DB_USER=' "${CRED_FILE}" 2>/dev/null; then
    DB_USER="$(grep '^DB_USER=' "${CRED_FILE}" | head -1 | cut -d= -f2-)"
  fi
  if grep -q 'DB_NAME=' "${CRED_FILE}" 2>/dev/null; then
    DB_NAME="$(grep '^DB_NAME=' "${CRED_FILE}" | head -1 | cut -d= -f2-)"
  fi
  unset maybe
fi

log "Installing nginx + php-fpm"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx php-fpm php-mysql php-cli

PHP_SOCK="$(ls /run/php/php*-fpm.sock 2>/dev/null | head -1 || true)"
if [[ -z "${PHP_SOCK}" ]]; then
  echo "Could not find php-fpm socket under /run/php" >&2
  exit 1
fi

log "Deploying site to ${SITE_ROOT}"
mkdir -p "${SITE_ROOT}"
rsync -a --delete \
  --exclude 'config.php' \
  "${REPO_ROOT}/website/" "${SITE_ROOT}/"

if [[ ! -f "${SITE_ROOT}/config.php" ]]; then
  cp "${SITE_ROOT}/config.example.php" "${SITE_ROOT}/config.php"
fi

# Rewrite DB block in config.php safely via PHP
php -r '
$path = $argv[1];
$host = $argv[2];
$name = $argv[3];
$user = $argv[4];
$pass = $argv[5];
$cfg = require $path;
$cfg["db"]["host"] = $host;
$cfg["db"]["name"] = $name;
$cfg["db"]["user"] = $user;
$cfg["db"]["pass"] = $pass;
$export = var_export($cfg, true);
file_put_contents($path, "<?php\ndeclare(strict_types=1);\n\nreturn " . $export . ";\n");
' "${SITE_ROOT}/config.php" "${DB_HOST}" "${DB_NAME}" "${DB_USER}" "${DB_PASS}"

chown -R www-data:www-data "${SITE_ROOT}"
chmod 640 "${SITE_ROOT}/config.php"
# www-data must read config; keep it out of public/
chown root:www-data "${SITE_ROOT}/config.php"

NGINX_SITE=/etc/nginx/sites-available/ranarokx
cat > "${NGINX_SITE}" <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${SERVER_NAME};

    root ${SITE_ROOT}/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
    }

    location ~ /\. {
        deny all;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sfn "${NGINX_SITE}" /etc/nginx/sites-enabled/ranarokx

nginx -t

# Restart matching php-fpm (socket name like php8.2-fpm.sock)
FPM_UNIT="$(basename "${PHP_SOCK}" .sock)"
if systemctl list-unit-files "${FPM_UNIT}.service" &>/dev/null; then
  systemctl enable --now "${FPM_UNIT}.service"
  systemctl restart "${FPM_UNIT}.service"
else
  systemctl restart php8.2-fpm 2>/dev/null \
    || systemctl restart php8.3-fpm 2>/dev/null \
    || systemctl restart php8.1-fpm 2>/dev/null \
    || systemctl restart php-fpm 2>/dev/null \
    || true
fi
systemctl reload nginx

# Smoke-test DB from www-data context if possible
if mysql -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" -e 'SELECT 1 FROM login LIMIT 1' &>/dev/null; then
  log "Database login OK"
else
  log "WARNING: could not verify DB login with ${DB_USER}@${DB_HOST}/${DB_NAME}"
  log "Edit ${SITE_ROOT}/config.php if needed"
fi

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
log "Registration site is live"
log "  URL:  http://${IP}/  and  http://${IP}/register.php"
log "  Root: ${SITE_ROOT}/public"
log "  Config: ${SITE_ROOT}/config.php"
log "Open TCP 80 (and 443 later) on your host/NAT if players register from the internet."
