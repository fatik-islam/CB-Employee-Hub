#!/bin/zsh
set -euo pipefail

readonly PROJECT_ROOT="/Users/syedfatikislam/Documents/CB Attendence"
readonly BACKUP_ROOT="/Users/syedfatikislam/Documents/CB Employee Hub Backups"
readonly KEYCHAIN_SERVICE="pk.com.chickybites.employeehub.backup"
readonly KEYCHAIN_ACCOUNT="syedfatikislam"
readonly NPX_PATH="/usr/local/bin/npx"
readonly OPENSSL_PATH="/usr/bin/openssl"
readonly SECURITY_PATH="/usr/bin/security"
readonly TIMESTAMP="$(/bin/date -u +%Y-%m-%dT%H-%M-%SZ)"
readonly SQL_PATH="${BACKUP_ROOT}/CB-Employee-Hub-${TIMESTAMP}.sql"
readonly ENCRYPTED_PATH="${SQL_PATH}.enc"

/bin/mkdir -p "$BACKUP_ROOT"
/bin/chmod 700 "$BACKUP_ROOT"

if ! "$SECURITY_PATH" find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1; then
  BACKUP_SECRET="$($OPENSSL_PATH rand -base64 48 | /usr/bin/tr -d '\n')"
  "$SECURITY_PATH" add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w "$BACKUP_SECRET" >/dev/null
  unset BACKUP_SECRET
fi

cd "$PROJECT_ROOT"
"$NPX_PATH" -y @insforge/cli db export \
  --format sql \
  --include-functions \
  --include-sequences \
  --include-views \
  --output "$SQL_PATH"

if [[ ! -s "$SQL_PATH" ]]; then
  /bin/rm -f "$SQL_PATH"
  print -u2 "InsForge export was empty."
  exit 1
fi

"$SECURITY_PATH" find-generic-password -w -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" \
  | "$OPENSSL_PATH" enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -in "$SQL_PATH" -out "$ENCRYPTED_PATH" -pass stdin

/bin/rm -f "$SQL_PATH"
/bin/chmod 600 "$ENCRYPTED_PATH"
/usr/bin/find "$BACKUP_ROOT" -type f -name 'CB-Employee-Hub-*.sql.enc' -mtime +30 -delete

print "Created encrypted backup: $ENCRYPTED_PATH"
