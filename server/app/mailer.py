"""Outgoing email: localized text messages over the operator's SMTP server.

Messages are rendered from app/locales/<locale>.json by the recipient's
language. They never contain a key, a wrapped key, a hash, or a link that
signs anyone in. The SMTP settings are read from the settings registry at
send time, so a change in the admin panel applies to the next message; the
password is never logged.
"""

import json
import logging
import smtplib
import ssl
from dataclasses import dataclass
from email.message import EmailMessage
from functools import cache
from pathlib import Path

from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool

from app import settings_store

logger = logging.getLogger("tildeck.mail")

LOCALES = ("en", "he")
_LOCALE_DIR = Path(__file__).parent / "locales"


@cache
def strings(locale: str) -> dict[str, str]:
    return json.loads((_LOCALE_DIR / f"{locale if locale in LOCALES else 'en'}.json").read_text(encoding="utf-8"))


def text(locale: str, key: str, **values: str) -> str:
    return strings(locale)[key].format(**values)


@dataclass(frozen=True)
class Mail:
    to: str
    subject: str
    body: str


class Mailer:
    """Sends a rendered message; implementations decide how."""

    async def send(self, session: AsyncSession, mail: Mail) -> None:
        raise NotImplementedError


class MemoryMailer(Mailer):
    """Keeps messages in memory: tests read what would have been sent."""

    def __init__(self) -> None:
        self.sent: list[Mail] = []

    async def send(self, session: AsyncSession, mail: Mail) -> None:
        self.sent.append(mail)


class SmtpMailer(Mailer):
    async def send(self, session: AsyncSession, mail: Mail) -> None:
        values = {
            key: await settings_store.get_value(session, key)
            for key in ("smtp_host", "smtp_port", "smtp_security", "smtp_username", "smtp_password", "smtp_from")
        }
        await run_in_threadpool(_deliver, values, mail)


def _deliver(values: dict[str, str | None], mail: Mail) -> None:
    message = EmailMessage()
    message["From"] = values["smtp_from"]
    message["To"] = mail.to
    message["Subject"] = mail.subject
    message.set_content(mail.body)

    host, port = values["smtp_host"] or "", int(values["smtp_port"] or 587)
    context = ssl.create_default_context()
    if values["smtp_security"] == "tls":
        client: smtplib.SMTP = smtplib.SMTP_SSL(host, port, timeout=20, context=context)
    else:
        client = smtplib.SMTP(host, port, timeout=20)
    with client:
        if values["smtp_security"] == "starttls":
            client.starttls(context=context)
        if values["smtp_username"]:
            client.login(values["smtp_username"], values["smtp_password"] or "")
        client.send_message(message)
    logger.info("Sent %r to %s", mail.subject, mail.to)


async def email_configured(session: AsyncSession) -> bool:
    """SMTP and the public address are both set: links in messages would work."""
    for key in ("smtp_host", "smtp_from", "public_url"):
        if not await settings_store.get_value(session, key):
            return False
    return True
