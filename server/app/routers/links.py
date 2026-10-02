"""The pages behind links in emails: address verification and approval of a
new device. Plain server-rendered pages in the account's language.

Both need a button press: mail scanners open links on their own, and that
must never confirm an address or approve a device.
These routes are not part of the API contract.
"""

import html

from fastapi import APIRouter, Depends, Request
from fastapi.responses import HTMLResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app import accounts, audit, clock
from app.db import get_db
from app.mailer import text
from app.models import Account, Device, EmailToken
from app.routers.account import approve_device

router = APIRouter(prefix="/links", include_in_schema=False)

_PAGE = """<!doctype html>
<html lang="{lang}" dir="{dir}">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex"><title>{title}</title>
<style>
body {{ margin: 0; min-height: 100vh; display: grid; place-items: center; background: #eff4f4; color: #0e181c;
  font-family: system-ui, "Segoe UI", sans-serif; }}
main {{ max-width: 30rem; margin: 1.5rem; padding: 2rem; background: #fff; border-radius: 1rem; border: 1px solid #d2ddde; }}
h1 {{ margin: 0 0 .75rem; font-size: 1.6rem; }} p {{ line-height: 1.5; color: #54666b; }}
button {{ font: inherit; font-weight: 700; padding: .7rem 1.4rem; border: 0; border-radius: .6rem; background: #0f766e; color: #fff; cursor: pointer; }}
@media (prefers-color-scheme: dark) {{ body {{ background: #081013; color: #ebf4f3; }} main {{ background: #101c20; border-color: #26383d; }}
  p {{ color: #8da4a7; }} button {{ background: #2dd4bf; color: #061a1a; }} }}
</style></head>
<body><main><h1>{title}</h1><p>{body}</p>{form}</main></body></html>"""

_SECURITY_HEADERS = {
    "cache-control": "no-store",
    "referrer-policy": "no-referrer",
    "x-content-type-options": "nosniff",
    "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'",
}


def _page(
    locale: str, title_key: str, body_key: str, *, status: int = 200, form: str = "", **values: str
) -> HTMLResponse:
    escaped = {k: html.escape(v) for k, v in values.items()}
    content = _PAGE.format(
        lang=locale,
        dir="rtl" if locale == "he" else "ltr",
        title=html.escape(text(locale, title_key)),
        body=text(locale, body_key, **escaped) if values else html.escape(text(locale, body_key)),
        form=form,
    )
    return HTMLResponse(content, status_code=status, headers=_SECURITY_HEADERS)


async def _usable(session: AsyncSession, token: str, purpose: str) -> tuple[EmailToken, Account] | None:
    link = await session.get(EmailToken, accounts.token_hash(token))
    if link is None or link.purpose != purpose or link.used_at is not None or link.expires_at < clock.now():
        return None
    account = await session.get(Account, link.account_id)
    return (link, account) if account is not None and account.disabled_at is None else None


def _invalid(request: Request) -> HTMLResponse:
    locale = "he" if request.headers.get("accept-language", "").lower().startswith("he") else "en"
    return _page(locale, "link_invalid_title", "link_invalid_body", status=410)


@router.get("/verify/{token}")
async def verify_page(token: str, request: Request, session: AsyncSession = Depends(get_db)) -> HTMLResponse:
    found = await _usable(session, token, "verify")
    if found is None:
        return _invalid(request)
    _, account = found
    button = html.escape(text(account.locale, "verify_button"))
    form = f'<form method="post"><button type="submit">{button}</button></form>'
    return _page(account.locale, "verify_title", "verify_page_body", form=form)


@router.post("/verify/{token}")
async def verify_email(token: str, request: Request, session: AsyncSession = Depends(get_db)) -> HTMLResponse:
    found = await _usable(session, token, "verify")
    if found is None:
        return _invalid(request)
    link, account = found
    link.used_at = clock.now()
    if account.email_verified_at is None:
        account.email_verified_at = clock.now()
        audit.record(
            session, actor=account.email, source="user", action="email_verified", entity="account", entity_id=account.id
        )
    await session.commit()
    return _page(account.locale, "verified_title", "verified_body")


async def _pending(session: AsyncSession, token: str) -> tuple[EmailToken, Account, Device] | None:
    found = await _usable(session, token, "approve")
    if found is None:
        return None
    link, account = found
    device = await session.get(Device, link.device_id) if link.device_id else None
    return (link, account, device) if device is not None and device.status == "pending" else None


@router.get("/approve/{token}")
async def approve_page(token: str, request: Request, session: AsyncSession = Depends(get_db)) -> HTMLResponse:
    found = await _pending(session, token)
    if found is None:
        return _invalid(request)
    _, account, device = found
    button = html.escape(text(account.locale, "approve_button"))
    form = f'<form method="post"><button type="submit">{button}</button></form>'
    return _page(account.locale, "approve_title", "approve_page_body", form=form, device=device.name)


@router.post("/approve/{token}")
async def approve_confirm(token: str, request: Request, session: AsyncSession = Depends(get_db)) -> HTMLResponse:
    found = await _pending(session, token)
    if found is None:
        return _invalid(request)
    link, account, device = found
    link.used_at = clock.now()
    await approve_device(request, session, account, device, f"{account.email} (email link)")
    return _page(account.locale, "approved_title", "approved_body")
