# Secrets inventory & provisioning design

## 1. What counts as a secret here

| Secret | Purpose | Where used |
|---|---|---|
| `APP_SECRET_KEY` | Flask session/cookie signing | `app/main.py` |
| `JWT_SECRET` | token signing (optional) | reserved for JWT issuing |
| `DATABASE_URL` | Postgres DSN **including password** | app startup |
| `EXTERNAL_API_TOKEN` | bearer token for `/admin/ping` auth | `app/main.py` |
| `SMTP_HOST` / `SMTP_USER` / `SMTP_PASSWORD` | mail relay credentials | reserved for mail |
| `VAULT_ADDR`, `VAULT_TOKEN` / `VAULT_APPROLE_*` | **bootstrap only** for centralized mode | `app/config.py` |

Rules enforced in this repo:

- No secret is ever hardcoded in source (see `app/config.py` — the single
  point that reads external storage).
- `.env` and `.vault-approle.env` are in `.gitignore`; only placeholder
  templates (`.env.example`) are committed.
- No endpoint ever returns a secret **value** — `/config-status` returns
  names and `true/false` only.
- Gitleaks scans history in CI; `reports/` and logs must not contain values.

## 2. External storage contract

The app reads secrets only through `app/config.py` with
`APP_SECRETS_SOURCE=vault|env|file` (default `file`):

1. `env` — process environment (docker/k8s/systemd/CI injectors).
2. `file` — `.env` next to the app, `chmod 600`, loaded via python-dotenv.
3. `vault` — HashiCorp Vault KV v2 at `secret/lab10`, AppRole auth preferred.

Precedence inside every mode: **process env > selected storage** — an
operator can override one value per instance without touching the store.
Missing required secrets abort startup with an error that lists **names
only**.

## 3. Decentralized provisioning (per environment)

Who: the team/developer that owns the environment. Where: each environment
keeps its own file/env; nothing central to compromise; simplest air-gap-safe
option. Downsides: rotation and auditing are manual, secrets sit on disk.

```bash
./scripts/provision_decentralized.sh          # generate .env (600) with fresh secrets
./scripts/provision_decentralized.sh --force  # rotate everything
make run                                      # app reads .env
# or pure env (no file at runtime):
set -a; . ./.env; set +a; APP_SECRETS_SOURCE=env python3 -m app.main
```

## 4. Centralized provisioning (Vault)

Who: a central secrets service owns generation/rotation; consumers
authenticate with a scoped identity (AppRole `lab10-app`, policy
`vault/policy.hcl` — read-only on `secret/lab10` only). Secrets live only in
Vault memory/store and in the app process.

```bash
./scripts/provision_centralized.sh            # starts Vault (dev), writes secrets,
                                              # provisions AppRole, saves .vault-approle.env
make run-vault                                # app fetches secrets from Vault at startup
```

Rotation in Vault: `vault kv put secret/lab10 EXTERNAL_API_TOKEN=...`
(app picks it up on next start / metadata version bump). Dev mode is
in-memory — for production run Vault with a storage backend and TLS.

## 5. Verification checklist

- `gitleaks detect --source .` — no secrets in history (`.env` is ignored).
- `git log -p -- .env .vault-approle.env` — nothing committed.
- `/config-status` shows names only; no endpoint echoes values.
- `bandit`/`semgrep` reports show no "hardcoded password" findings in the
  main app code (only in the marked legacy demo module).
