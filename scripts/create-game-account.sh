#!/usr/bin/env bash
# Create a player (or GM) account in the Hercules login table.
#
# Usage:
#   sudo bash scripts/create-game-account.sh <userid> <password> [group_id] [sex]
#
# Examples:
#   sudo bash scripts/create-game-account.sh alice secret123
#   sudo bash scripts/create-game-account.sh admin secret123 99 M
#
# Defaults: DB_NAME=hercules, group_id=0, sex=M

set -euo pipefail

USERID="${1:-}"
PASS="${2:-}"
GROUP_ID="${3:-0}"
SEX="${4:-M}"
DB_NAME="${DB_NAME:-hercules}"

if [[ -z "${USERID}" || -z "${PASS}" ]]; then
  echo "Usage: $0 <userid> <password> [group_id] [sex]" >&2
  exit 1
fi

if [[ "${SEX}" != "M" && "${SEX}" != "F" ]]; then
  echo "sex must be M or F" >&2
  exit 1
fi

mysql -u root "${DB_NAME}" <<SQL
INSERT INTO \`login\` (\`userid\`, \`user_pass\`, \`sex\`, \`email\`, \`group_id\`)
VALUES ('${USERID}', '${PASS}', '${SEX}', '${USERID}@localhost', ${GROUP_ID});
SQL

echo "Created account '${USERID}' (group_id=${GROUP_ID}) in database '${DB_NAME}'."
