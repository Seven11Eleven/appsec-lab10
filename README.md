# Lab 10 — CI SAST/SCA pipeline + secrets provisioning

A tiny Flask service (`app/`) wrapped in a CI pipeline that builds the app,
runs **2 SAST tools + 1 SCA tool**, and exports all reports as pipeline
artifacts. Secrets are **never hardcoded** — the app reads them from
external storage (env vars / `.env` file / HashiCorp Vault), and both
secret-provisioning approaches (decentralized & centralized) are
demonstrated with working scripts.

## App

- `app/main.py` — Flask service: `/health`, `/config-status` (secret *names*
  only, never values), `/admin/ping` (bearer-token check via
  `EXTERNAL_API_TOKEN`).
- `app/config.py` — the single secrets-loading point (env / file / Vault).
- `app/legacy_report.py` — intentionally insecure legacy code kept to give
  SAST real findings. Do not copy its patterns.

## Tooling

| Type    | Tool        | Why chosen |
|---------|-------------|------------|
| SAST #1 | **Bandit**  | Python-specific, AST-based static analysis, zero config |
| SAST #2 | **Semgrep** | Multi-language rulesets (`p/python`, `p/secrets`), custom rules friendly |
| SCA     | **pip-audit** | Audits `requirements.txt` (incl. transitive deps) against PyPI/OSV advisory DB |
| Bonus   | **Gitleaks**| Scans git history for leaked secrets (ties into the secrets topic) |

## CI pipeline

`.gitlab-ci.yml` (GitLab) and `.github/workflows/ci.yml` (GitHub mirror):

| Stage   | Job             | Artifact (exported with `when: always`) |
|---------|-----------------|------------------------------------------|
| build   | `build_app`     | — (install deps, byte-compile, import check) |
| sast    | `bandit_sast`   | `reports/bandit-report.{json,txt}` |
| sast    | `semgrep_sast`  | `reports/semgrep-report.{json,txt}` |
| sca     | `pip_audit_sca` | `reports/pip-audit-report.{json,txt}` |
| secrets | `gitleaks_secrets` | `reports/gitleaks-report.json` |

Tools run in **report mode** (`|| true`) so artifacts are always exported;
to enforce instead, drop `|| true` or add severity gates (e.g.
`bandit --severity-level high`, gitleaks `--exit-code 1`).

Push the repo and the pipeline runs automatically:

```bash
git remote add origin <YOUR_REPO_URL>   # GitHub or GitLab
git push -u origin main
```

## Secrets

Full inventory + design: `docs/SECRETS.md`. Loading contract:
`app/config.py` + `APP_SECRETS_SOURCE=vault|env|file` (default `file`).

### Decentralized (per-environment files/env)

```bash
./scripts/provision_decentralized.sh    # generates .env (chmod 600) with fresh secrets
make run                                # app reads .env
```

### Centralized (HashiCorp Vault, AppRole)

```bash
./scripts/provision_centralized.sh      # starts Vault (dev), writes secret/lab10,
                                        # provisions scoped AppRole, saves .vault-approle.env
make run-vault                          # app fetches secrets from Vault at startup
```

Stop the demo vault with `docker stop lab10-vault && docker rm lab10-vault`
(or `pkill -f 'vault server -dev'` if the binary was used).

## Local run (Fedora)

```bash
sudo dnf install -y git make openssl python3-pip python3-virtualenv gitleaks
python3 -m pip install --user pipx && pipx ensurepath    # then re-login shell
pipx install bandit semgrep pip-audit                    # same tools as CI
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

make decentralized && make run                           # app on :8080
make sast                                                # bandit+semgrep+pip-audit+gitleaks -> reports/
```

`make` targets: `build`, `sast`, `sca`, `secrets-scan`, `reports`,
`decentralized`, `centralized`, `run`, `run-vault`.

## Expected analysis findings (by design)

- **Bandit** flags `app/legacy_report.py`: B324 (md5), B311 (`random` for
  tokens), B602/B605 (shell injection).
- **Semgrep** (`p/python`, `p/secrets`) flags the same module.
- **pip-audit** flags `requests==2.28.0` (CVE-2023-32681, CVE-2024-35195) —
  intentionally outdated pin; fix is `requests>=2.32.0`.
- **Gitleaks** finds nothing — secrets live in git-ignored files.

## Russian TL;DR

Сервис Flask + CI-pipeline (GitLab/GitHub): сборка → SAST (Bandit, Semgrep)
→ SCA (pip-audit) → сканирование секретов (gitleaks); все отчёты
выгружаются как артефакты. Секреты не хранятся в коде: приложение читает
их из внешнего хранилища — файл `.env`/переменные окружения
(децентрализованно, `scripts/provision_decentralized.sh`) или HashiCorp
Vault через AppRole (централизованно, `scripts/provision_centralized.sh`).
Перечень секретов — `docs/SECRETS.md`.
