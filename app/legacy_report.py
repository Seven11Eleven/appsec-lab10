"""LEGACY MODULE - INTENTIONALLY INSECURE, kept to demonstrate SAST.

Bandit/Semgrep should report here: weak hashing (B324), insecure randomness
for tokens (B311), shell command injection (B602/B605).
The corrected, secret-safe patterns live in app/config.py and app/main.py.
Do NOT copy anything from this file into production code.
"""

from __future__ import annotations

import hashlib
import random
import subprocess


def legacy_md5_password(password: str) -> str:
    # B324: md5 is not a password hash
    return hashlib.md5(password.encode()).hexdigest()


def legacy_session_token() -> str:
    # B311: `random` is not cryptographically secure
    return f"user-{random.randint(0, 999_999):06d}"


def legacy_read_report(report_name: str) -> str:
    # B602/B605: attacker-controlled string reaches a shell
    proc = subprocess.run(
        f"cat /var/reports/{report_name}", shell=True, capture_output=True, text=True
    )
    return proc.stdout
