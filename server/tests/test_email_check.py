"""The email address check: the rule of the regular expression it replaced,
without its backtracking."""

import re
import time

import pytest

from app.accounts import is_email

# The expression is_email replaced, kept here to compare against.
OLD = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

SAMPLES = [
    "ops@example.com",
    "a.b+c@sub.example.co.il",
    "a@b.c",
    "a@b..c",
    "a@.b",
    "a@b.",
    "@b.c",
    "a@b",
    "a@@b.c",
    "a@b@c.d",
    "a b@c.d",
    "a@b.c ",
    "a@b\t.c",
    "",
    "@",
    "a@",
    ".@a.b",
    "user@xn--exmple-cua.com",
]


@pytest.mark.parametrize("value", SAMPLES)
def test_same_answer_as_the_old_expression(value):
    assert is_email(value) is bool(OLD.match(value))


def test_crafted_input_is_answered_at_once():
    crafted = "a@" + "." * 318
    start = time.perf_counter()
    assert is_email(crafted) is False
    assert time.perf_counter() - start < 0.01
