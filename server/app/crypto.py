"""Encryption at rest for stored settings.

CONFIG_ENCRYPTION_KEY is an arbitrary operator-chosen string; a Fernet key is
derived from it with SHA-256, so the operator does not have to produce valid
Fernet material by hand. Losing the key means losing every stored value.

This protects operator settings only. User vault data never reaches the
server in plaintext and is not handled here.
"""

import base64
import hashlib

from cryptography.fernet import Fernet, InvalidToken

from app.config import get_settings


class EncryptionUnavailable(RuntimeError):
    """CONFIG_ENCRYPTION_KEY is not set."""


class DecryptionFailed(RuntimeError):
    """Stored ciphertext cannot be read with the current key."""


def _fernet() -> Fernet:
    key = get_settings().CONFIG_ENCRYPTION_KEY.strip()
    if not key:
        raise EncryptionUnavailable("CONFIG_ENCRYPTION_KEY is not set; encrypted settings cannot be used")
    derived = base64.urlsafe_b64encode(hashlib.sha256(key.encode("utf-8")).digest())
    return Fernet(derived)


def encrypt(value: str) -> str:
    return _fernet().encrypt(value.encode("utf-8")).decode("ascii")


def decrypt(token: str) -> str:
    try:
        return _fernet().decrypt(token.encode("ascii")).decode("utf-8")
    except InvalidToken as exc:
        raise DecryptionFailed("stored value cannot be decrypted with the current CONFIG_ENCRYPTION_KEY") from exc
