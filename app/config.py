"""Single point of secret handling for the app.

Secrets are NEVER stored in source code. They come from external storage:

  env   - process environment (docker/k8s/systemd/CI): decentralized
  file  - .env file (chmod 600, git-ignored): decentralized
  vault - HashiCorp Vault KV v2 via AppRole or token: centralized

Selection: APP_SECRETS_SOURCE=vault|env|file (default: file).
Precedence inside every mode: process env > selected storage, so an
operator can override a single value per instance without touching the
central store. Values are validated (names only) and never logged.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional, Union

from dotenv import dotenv_values, load_dotenv

REQUIRED_SECRETS = ("APP_SECRET_KEY", "DATABASE_URL", "EXTERNAL_API_TOKEN")
OPTIONAL_SECRETS = ("JWT_SECRET", "SMTP_HOST", "SMTP_USER", "SMTP_PASSWORD")
ALL_SECRETS = REQUIRED_SECRETS + OPTIONAL_SECRETS

ENV_FILE = Path(os.environ.get("APP_ENV_FILE", ".env"))


class MissingSecretError(RuntimeError):
    """A required secret is absent from the configured external storage."""


@dataclass
class Config:
    source: str
    values: dict = field(default_factory=dict)

    def get(self, name: str, default: Optional[str] = None) -> Optional[str]:
        return self.values.get(name, default)

    @property
    def present(self) -> dict:
        """Which secret NAMES are loaded - safe to expose, values are not."""
        return {name: name in self.values for name in ALL_SECRETS}


def _collect(store) -> dict:
    return {name: store[name] for name in ALL_SECRETS if store.get(name)}


def load_from_env() -> dict:
    """Decentralized storage #1: process environment variables."""
    return _collect(os.environ)


def load_from_file(env_file: Union[str, Path, None] = None) -> dict:
    """Decentralized storage #2: per-environment .env file (chmod 600)."""
    env_file = Path(env_file) if env_file else ENV_FILE
    if not env_file.is_file():
        raise MissingSecretError(
            f"secret file {env_file} not found - run scripts/provision_decentralized.sh"
        )
    load_dotenv(env_file, override=False)
    return load_from_env()


def load_from_vault() -> dict:
    """Centralized storage: HashiCorp Vault KV v2 (token or AppRole auth)."""
    import hvac  # imported lazily: only the vault mode needs it

    addr = os.environ.get("VAULT_ADDR", "http://127.0.0.1:8200")
    mount = os.environ.get("VAULT_MOUNT", "secret")
    path = os.environ.get("VAULT_SECRET_PATH", "lab10")

    client = hvac.Client(url=addr, verify=os.environ.get("VAULT_CACERT") or False)
    role_id = os.environ.get("VAULT_APPROLE_ROLE_ID")
    if role_id:
        secret_id = os.environ.get("VAULT_APPROLE_SECRET_ID", "")
        client.auth.approle.login(role_id, secret_id)
    else:
        client.token = os.environ.get("VAULT_TOKEN", "")
    if not client.is_authenticated():
        raise MissingSecretError("Vault authentication failed (check VAULT_* variables)")

    resp = client.secrets.kv.v2.read_secret_version(path=path, mount_point=mount)
    data = (resp or {}).get("data", {}).get("data", {})
    return _collect(data)


def load_config() -> Config:
    """Load + validate secrets from the selected external storage."""
    source = os.environ.get("APP_SECRETS_SOURCE", "file").lower().strip()
    if source not in ("env", "file", "vault"):
        raise ValueError(f"APP_SECRETS_SOURCE must be env|file|vault, got: {source!r}")

    if ENV_FILE.is_file():
        if source == "vault":
            # Vault mode: .env may only bootstrap VAULT_* / source selection,
            # so decentralized .env secrets cannot shadow the central store.
            for key, value in dotenv_values(ENV_FILE).items():
                if key.startswith("VAULT_") or key == "APP_SECRETS_SOURCE":
                    os.environ.setdefault(key, value)
        else:
            load_dotenv(ENV_FILE, override=False)

    if source == "env":
        loaded = load_from_env()
    elif source == "file":
        loaded = load_from_file()
    else:  # vault: env vars override vault values (per-instance override)
        loaded = {**load_from_vault(), **load_from_env()}

    missing = [name for name in REQUIRED_SECRETS if not loaded.get(name)]
    if missing:
        raise MissingSecretError(
            "missing required secrets in external storage "
            f"(source={source}): {', '.join(missing)} - values are never shown"
        )
    return Config(source=source, values=loaded)
