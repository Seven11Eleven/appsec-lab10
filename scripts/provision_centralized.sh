#!/usr/bin/env bash
# Centralized secrets provisioning (Lab 10) - HashiCorp Vault.
#
# Centralized approach: ONE secret store holds ALL secrets; consumers
# authenticate (here: scoped AppRole identity, not the root token) and read
# secrets at runtime. The app talks to Vault itself (app/config.py,
# APP_SECRETS_SOURCE=vault), so secrets never land on disk in the app.
#
# Uses the `vault` binary if present, otherwise docker/podman with the
# hashicorp/vault image in dev mode (dev mode = in-memory, fine for the lab).
set -euo pipefail

cd "$(dirname "$0")/.."

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
ROOT_TOKEN="lab10-root"
ROLE="lab10-app"
export VAULT_ADDR

CURL_OK() { curl -sf "${VAULT_ADDR}/v1/sys/health" >/dev/null 2>&1; }

echo "== 1. Vault dev server =="
if CURL_OK; then
  echo "[+] Vault already running at ${VAULT_ADDR}"
else
  if command -v vault >/dev/null 2>&1; then
    echo "[*] starting vault binary (dev mode, log: /tmp/lab10-vault.log)"
    nohup vault server -dev \
      -dev-root-token-id="${ROOT_TOKEN}" \
      -dev-listen-address=127.0.0.1:8200 \
      >/tmp/lab10-vault.log 2>&1 &
  elif command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1; then
    ENGINE=$(command -v docker >/dev/null 2>&1 && echo docker || echo podman)
    echo "[*] starting vault via ${ENGINE} (dev mode)"
    ${ENGINE} rm -f lab10-vault >/dev/null 2>&1 || true
    ${ENGINE} run -d --name lab10-vault -p 8200:8200 --cap-add=IPC_LOCK \
      -e VAULT_DEV_ROOT_TOKEN_ID="${ROOT_TOKEN}" \
      -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
      hashicorp/vault:1.15 >/dev/null
  else
    echo "[x] need the 'vault' binary or docker/podman (see README)" >&2
    exit 1
  fi
  for _ in $(seq 1 30); do CURL_OK && break; sleep 1; done
  CURL_OK || { echo "[x] vault did not start; see /tmp/lab10-vault.log" >&2; exit 1; }
  echo "[+] Vault is up"
fi

echo "== 2. Write the app secrets to the central store (KV v2) =="
if command -v vault >/dev/null 2>&1; then
  export VAULT_TOKEN="${ROOT_TOKEN}"
  cli() { vault "$@"; }
else
  ENGINE=$(command -v docker >/dev/null 2>&1 && echo docker || echo podman)
  cli() { ${ENGINE} exec -i -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="${ROOT_TOKEN}" lab10-vault vault "$@"; }
fi

cli kv put "secret/lab10" \
  APP_SECRET_KEY="$(openssl rand -hex 32)" \
  JWT_SECRET="$(openssl rand -hex 32)" \
  DATABASE_URL="postgresql://app_user:$(openssl rand -hex 24)@db.internal:5432/appdb" \
  EXTERNAL_API_TOKEN="$(openssl rand -hex 24)" \
  >/dev/null
echo "[+] secrets stored at secret/lab10"

echo "== 3. Scoped app identity (AppRole + least-privilege policy) =="
cli policy write "${ROLE}" - < vault/policy.hcl >/dev/null
cli auth enable approle >/dev/null 2>&1 || true
cli write "auth/approle/role/${ROLE}" token_policies="${ROLE}" token_ttl=1h >/dev/null

ROLE_ID=$(cli read -field=role_id "auth/approle/role/${ROLE}/role-id")
SECRET_ID=$(cli write -f -field=secret_id "auth/approle/role/${ROLE}/secret-id")

umask 077
cat > .vault-approle.env <<EOF
# Runtime-only bootstrap for centralized mode. chmod 600, git-ignored.
# The app authenticates to Vault with this scoped AppRole (NOT the root token).
VAULT_ADDR=${VAULT_ADDR}
VAULT_APPROLE_ROLE_ID=${ROLE_ID}
VAULT_APPROLE_SECRET_ID=${SECRET_ID}
EOF
chmod 600 .vault-approle.env

echo "[+] policy vault/policy.hcl attached; AppRole '${ROLE}' provisioned"
echo "[+] role_id/secret_id written to .vault-approle.env (0600, git-ignored)"
echo ""
echo "== 4. Run the app in centralized mode =="
echo "  set -a; . ./.vault-approle.env; set +a"
echo "  APP_SECRETS_SOURCE=vault python3 -m app.main   (or: make run-vault)"
