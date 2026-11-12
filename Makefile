# Lab 10 - build, run local analysis (same as CI), provision and run the app.
.PHONY: help build sast sca secrets-scan reports run run-vault decentralized centralized

help:
	@echo "targets: build | sast | sca | secrets-scan | reports | decentralized | centralized | run | run-vault"

build:
	python3 -m pip install -r requirements.txt

sast:
	bash scripts/run_checks_local.sh

sca:
	pip-audit -r requirements.txt

secrets-scan:
	mkdir -p reports && gitleaks detect --source . --report-format json --report-path reports/gitleaks-report.json --exit-code 0

reports:
	@ls -l reports/ 2>/dev/null || echo "no reports yet: make sast"

decentralized:
	bash scripts/provision_decentralized.sh

centralized:
	bash scripts/provision_centralized.sh

run:
	APP_SECRETS_SOURCE=file python3 -m app.main

run-vault:
	bash -c 'set -a; . ./.vault-approle.env; set +a; APP_SECRETS_SOURCE=vault python3 -m app.main'
