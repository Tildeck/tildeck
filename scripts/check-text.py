#!/usr/bin/env python3
"""Text guards, run by scripts/verify.sh. Stdlib only.

1. Locale parity: every English and Hebrew locale pair has exactly the same
   keys (nested JSON paths; ARB message keys).
2. Hebrew only where allowed: the repository is public-ready and in English,
   so Hebrew characters may appear only in the Hebrew locale files listed
   below. Tests load their Hebrew samples from those files.
3. No Unicode dashes (em dash, en dash, and relatives) in human-readable
   text: documentation and locale files.

Only files tracked by Git are checked, so local scratch files never fail it.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (English file, Hebrew file). The Hebrew files are the only ones that may
# contain Hebrew.
LOCALE_PAIRS = [
    ("panel/i18n/locales/en.json", "panel/i18n/locales/he.json"),
    ("app/lib/l10n/app_en.arb", "app/lib/l10n/app_he.arb"),
    ("server/app/locales/en.json", "server/app/locales/he.json"),
]
HEBREW_ALLOWED = {he for _, he in LOCALE_PAIRS}

HEBREW_RE = re.compile("[\u0590-\u05ff\ufb1d-\ufb4f]")
# Figure dash, en dash, em dash, horizontal bar, minus sign, two-em and
# three-em dash, small em dash, fullwidth hyphen-minus.
DASH_RE = re.compile("[\u2012\u2013\u2014\u2015\u2212\u2e3a\u2e3b\ufe58\uff0d]")
PROSE_SUFFIXES = {".md", ".html", ".json", ".arb"}

# Binary files never hold text worth scanning.
BINARY_SUFFIXES = {".png", ".jpg", ".ico", ".ttf", ".otf", ".woff", ".woff2", ".jar", ".keystore", ".jks"}


def tracked_files() -> list[str]:
    # --stdin: the NUL-separated output of `git ls-files -z`, so the guard
    # also runs in a container without Git.
    if "--stdin" in sys.argv:
        output = sys.stdin.buffer.read()
    else:
        output = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
    return [name for name in output.decode("utf-8").split("\0") if name]


def keys_of(path: Path) -> set[str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if path.suffix == ".arb":
        return {key for key in data if not key.startswith("@")}

    def flatten(value, prefix=""):
        if isinstance(value, dict):
            for key, child in value.items():
                yield from flatten(child, f"{prefix}{key}.")
        else:
            yield prefix.rstrip(".")

    return set(flatten(data))


def check_parity() -> list[str]:
    problems = []
    for en, he in LOCALE_PAIRS:
        en_path, he_path = ROOT / en, ROOT / he
        if not en_path.is_file() or not he_path.is_file():
            problems.append(f"missing locale file: {en if not en_path.is_file() else he}")
            continue
        en_keys, he_keys = keys_of(en_path), keys_of(he_path)
        problems += [f"{he}: missing key {key}" for key in sorted(en_keys - he_keys)]
        problems += [f"{en}: missing key {key}" for key in sorted(he_keys - en_keys)]
        print(f"parity: {en} and {he}: {len(en_keys)} keys")
    return problems


def check_text(files: list[str]) -> list[str]:
    problems = []
    scanned = 0
    for name in files:
        path = ROOT / name
        if path.suffix.lower() in BINARY_SUFFIXES or not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        scanned += 1
        prose = path.suffix in PROSE_SUFFIXES
        for number, line in enumerate(text.splitlines(), start=1):
            if name not in HEBREW_ALLOWED and HEBREW_RE.search(line):
                problems.append(f"{name}:{number}: Hebrew outside the Hebrew locale files")
            if prose and DASH_RE.search(line):
                problems.append(f"{name}:{number}: Unicode dash character")
    print(f"text: {scanned} tracked text files checked")
    return problems


def main() -> int:
    problems = check_parity() + check_text(tracked_files())
    for problem in problems:
        print(f"FAIL {problem}")
    if problems:
        print(f"{len(problems)} problem(s)")
        return 1
    print("text guards passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
