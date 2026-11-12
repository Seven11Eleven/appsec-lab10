#!/usr/bin/env bash
# Run the same analysis as CI, locally. Reports land in ./reports/.
# Missing tools are skipped with a hint (install commands in README).
set -uo pipefail  # NOT -e: run every tool even if one exits non-zero
cd "$(dirname "$0")/.."
mkdir -p reports

echo "== SAST #1: Bandit =="
if command -v bandit >/dev/null 2>&1; then
  bandit -r app -f json -o reports/bandit-report.json || true
  bandit -r app -f txt  -o reports/bandit-report.txt  || true
else
  echo "bandit not installed (pipx install bandit)"
fi

echo "== SAST #2: Semgrep =="
if command -v semgrep >/dev/null 2>&1; then
  semgrep scan --config p/python --config p/secrets --json --output reports/semgrep-report.json || true
  semgrep scan --config p/python --config p/secrets --text --output reports/semgrep-report.txt  || true
else
  echo "semgrep not installed (pipx install semgrep)"
fi

echo "== SCA: pip-audit =="
if command -v pip-audit >/dev/null 2>&1; then
  pip-audit -r requirements.txt -f json    -o reports/pip-audit-report.json || true
  pip-audit -r requirements.txt -f columns > reports/pip-audit-report.txt  || true
else
  echo "pip-audit not installed (pipx install pip-audit)"
fi

echo "== Secrets scan: gitleaks (bonus) =="
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --source . --report-format json \
    --report-path reports/gitleaks-report.json --exit-code 0 --redact || true
else
  echo "gitleaks not installed (sudo dnf install gitleaks)"
fi

echo "== Reports =="
ls -l reports/
