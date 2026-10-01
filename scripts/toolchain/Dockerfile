# Toolchain images for the workflow scripts and CI, pinned by digest.
#
# This file is never built. scripts/lib/common.sh reads the FROM lines by
# stage name, so every script and CI job runs the exact same image. It is a
# Dockerfile so Dependabot keeps the tags and digests current.
#
# The server's own build images (Node, Python, uv) are pinned in
# server/Dockerfile, and PostgreSQL in the Compose files.

# Flutter with the Android SDK: analyze, test, golden images, Android builds.
FROM ghcr.io/cirruslabs/flutter:3.44.0@sha256:46691e311715845de03a3ba4753a475476936805b29431b1f00f1816981033f8 AS flutter

# Generates the Dart API client from server/openapi.json.
FROM openapitools/openapi-generator-cli:v7.25.0@sha256:2ab0a9680222de65dc9d3baf861aa02b99e1b80c211d8221ebf3ae8f8a102524 AS openapi-generator

# Shell lint and format for scripts/.
FROM koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d AS shellcheck
FROM mvdan/shfmt:v3.14.1@sha256:8c06884a35683d8763fba6c0d9484d11a61a96da65f8d497d6f625825a6043f2 AS shfmt

# Lints the GitHub Actions workflows (and the shell inside them).
FROM rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667 AS actionlint

# Plain Python for the stdlib-only repository guards (scripts/check-text.py).
# Same image as the server's base in server/Dockerfile.
FROM python:3.14-slim@sha256:51dafde81dbdb6ebde285137a295cf18a47ca95234fe388a343719cb97305b3d AS python

# A throwaway OpenSSH server the client's SSH tests connect to.
FROM linuxserver/openssh-server:10.3_p1-r1-ls237@sha256:946fa26105e0ec212fdf821b9ddc59aab65f2c2d07c02b25ff0f5001fc332ff0 AS openssh

# A throwaway Telnet server (BusyBox telnetd) the client's Telnet tests use.
FROM busybox:1.37@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e AS telnet

# The throwaway database for server tests. Same image as the Compose files.
FROM postgres:18@sha256:5a5a84b19854a9ffaa54082c166ff4ec27473a361e496e5ea167f298f2da9722 AS postgres
