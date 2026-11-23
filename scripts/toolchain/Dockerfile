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
FROM openapitools/openapi-generator-cli:v7.27.0@sha256:949efd0d5cf3c093ef169887b2ebe0879ee2e8074b6476264232ce4fd8ef46d0 AS openapi-generator

# Shell lint and format for scripts/.
FROM koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d AS shellcheck
FROM mvdan/shfmt:v3.14.1@sha256:8c06884a35683d8763fba6c0d9484d11a61a96da65f8d497d6f625825a6043f2 AS shfmt

# Lints the GitHub Actions workflows (and the shell inside them).
FROM rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667 AS actionlint

# Plain Python for the stdlib-only repository guards (scripts/check-text.py).
# The server's own Python is pinned separately in server/Dockerfile.
FROM python:3.15-slim@sha256:65a65fc7b30b06cb6df4930fd4650697cb23f4c2698ab81fc87e4b031bc36928 AS python

# A throwaway OpenSSH server the client's SSH tests connect to.
FROM linuxserver/openssh-server:10.3_p1-r1-ls237@sha256:946fa26105e0ec212fdf821b9ddc59aab65f2c2d07c02b25ff0f5001fc332ff0 AS openssh

# Makes the one-time key files the client's key import tests read
# (scripts/verify.sh): puttygen from putty-tools, installed at run time,
# which must be release 0.83.
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2 AS keygen

# A throwaway Telnet server (BusyBox telnetd) the client's Telnet tests use.
FROM busybox:1.38@sha256:a46257e06c82ad85242d0d38077d0a52d9896389ca60a1a59d3463db586e5fa4 AS telnet

# The throwaway database for server tests. Same image as the Compose files.
FROM postgres:18@sha256:74935e72241653ca55e0414067e6d8763aceb8a810eb51b452253ec3dcfc4336 AS postgres
