"""Lab 10 demo service.

Start:
  decentralized (file):  make decentralized && make run
  decentralized (env):   set -a; . ./.env; set +a; APP_SECRETS_SOURCE=env python3 -m app.main
  centralized  (vault):  make centralized && make run-vault

Endpoints:
  GET /health         -> liveness + which secret source is in use
  GET /config-status  -> which secret NAMES are loaded (values are never returned)
  GET /admin/ping     -> requires `Authorization: Bearer <EXTERNAL_API_TOKEN>`
"""

from __future__ import annotations

import hmac
import os

from flask import Flask, abort, jsonify, request

from .config import load_config


def create_app() -> Flask:
    cfg = load_config()  # fails fast if a required secret is absent
    app = Flask(__name__)
    app.secret_key = cfg.get("APP_SECRET_KEY")

    @app.get("/health")
    def health():
        return jsonify(status="ok", secrets_source=cfg.source)

    @app.get("/config-status")
    def config_status():
        return jsonify(source=cfg.source, secrets=cfg.present)

    @app.get("/admin/ping")
    def admin_ping():
        token = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()
        expected = cfg.get("EXTERNAL_API_TOKEN") or ""
        if not token or not hmac.compare_digest(token.encode(), expected.encode()):
            abort(401)
        return jsonify(ok=True, message="admin token verified")

    return app


if __name__ == "__main__":
    host = os.environ.get("APP_HOST", "127.0.0.1")
    port = int(os.environ.get("PORT", "8080"))
    create_app().run(host=host, port=port)
