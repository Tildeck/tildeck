"""Serving the built admin panel.

The panel is a static single-page app. Files that exist are served as they
are; any other path outside /api answers with the app shell so client-side
routes survive a reload. Hashed build assets are cached forever, the shell is
always revalidated so a browser never holds an index.html whose chunks a newer
deploy removed.
"""

import logging
import os
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse

logger = logging.getLogger("tildeck.panel")

SECURITY_HEADERS = {
    "x-content-type-options": "nosniff",
    "referrer-policy": "same-origin",
    "content-security-policy": "frame-ancestors 'none'",
}


def mount(app: FastAPI, panel_dir: str) -> bool:
    root = Path(panel_dir).resolve()
    shell = root / "index.html"
    inside = str(root) + os.sep
    if not shell.is_file():
        logger.warning("Admin panel not found at %s; serving the API only", root)
        return False

    @app.api_route("/{path:path}", methods=["GET", "HEAD"], include_in_schema=False)
    async def panel(path: str) -> FileResponse:
        if path == "api" or path.startswith("api/"):
            raise HTTPException(status_code=404)
        # Resolved, links included, and only served from inside the panel.
        candidate = os.path.realpath(os.path.join(root, path))
        if path and candidate.startswith(inside) and os.path.isfile(candidate):
            cache = "public, max-age=31536000, immutable" if path.startswith("_nuxt/") else "no-cache"
            return FileResponse(candidate, headers={**SECURITY_HEADERS, "cache-control": cache})
        return FileResponse(shell, headers={**SECURITY_HEADERS, "cache-control": "no-cache"})

    logger.info("Admin panel served from %s", root)
    return True
