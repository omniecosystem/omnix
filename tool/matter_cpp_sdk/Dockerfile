# Copyright 2026 The Omnix Authors
# SPDX-License-Identifier: Apache-2.0
FROM rust@sha256:452176c0cefca88c0b3184ce85a4eb03e3d4fa05d2afb5366abcba853221019e
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git build-essential pkg-config cmake curl ca-certificates libssl-dev libdbus-1-dev \
    libglib2.0-dev libavahi-client-dev ninja-build python3-venv python3-dev python3-pip \
    unzip libgirepository1.0-dev libcairo2-dev libreadline-dev libevent-dev default-jre \
    clang gn file
WORKDIR /work
