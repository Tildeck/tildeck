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
FROM mvdan/shfmt:v3.12.0@sha256:307d265ffd25ce832899ae17c93ed5062fc3375c514bba8f52cbf52792735c4d AS shfmt

# The throwaway database for server tests. Same image as the Compose files.
FROM postgres:18@sha256:5a5a84b19854a9ffaa54082c166ff4ec27473a361e496e5ea167f298f2da9722 AS postgres
