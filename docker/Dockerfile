# ------------------------------------------------------------------------------
# docker/Dockerfile
# ------------------------------------------------------------------------------
# Builds the or-tools C++ library into a Debian package. Wrapping this in
# Docker gives us caching of the toolchain install and a reproducible Ubuntu
# environment regardless of what the build host happens to be.
#
# The final stage is a scratch image containing only the deb, so that a bake
# invocation can export it straight to the host:
#
#   docker buildx bake ortools-deb   ->   output/*.deb
# ------------------------------------------------------------------------------
# Copyright (c) 2026, Simbe Robotics, Inc.
# ------------------------------------------------------------------------------
ARG UBUNTU_CODENAME=noble

FROM ubuntu:${UBUNTU_CODENAME} AS build
ARG DEBIAN_FRONTEND=noninteractive

# BUILD_DEPS=ON fetches and builds abseil, protobuf, SCIP etc. from source at
# configure time, so the toolchain plus git is all we need from the archive.
RUN apt-get update && apt-get install -yq --no-install-recommends \
    build-essential \
    ca-certificates \
    ccache \
    cmake \
    dpkg-dev \
    file \
    git \
    libssl-dev \
    ninja-build \
    pkg-config \
    python3-pip \
    wget

# or-tools 9.7 needs CMake >= 3.18 and focal only ships 3.16. The PyPI wheel
# is the least-effort way to get a newer one on both amd64 and arm64.
ARG UBUNTU_CODENAME
RUN if dpkg --compare-versions "$(cmake --version | sed -n 's/^cmake version //p')" lt 3.18; then \
      pip3 install --no-cache-dir 'cmake>=3.18,<3.28' && hash -r && cmake --version; \
    fi

ARG TARGETARCH
ARG ORTOOLS_PATCH
ARG DEB_REVISION=1
ENV UBUNTU_CODENAME=${UBUNTU_CODENAME} \
    ORTOOLS_PATCH=${ORTOOLS_PATCH} \
    DEB_REVISION=${DEB_REVISION} \
    CCACHE_DIR=/ccache

COPY docker/build-deb.sh /usr/local/bin/build-deb
COPY . /src/or-tools
WORKDIR /src/or-tools

# ccache lives in a cache mount so that a source change doesn't mean
# recompiling all of or-tools and its dependencies from scratch.
RUN --mount=type=cache,target=/ccache,id=ortools-ccache-${UBUNTU_CODENAME}-${TARGETARCH} \
    build-deb


# Export stage: nothing but the deb, for `type=local` output.
FROM scratch AS deb
COPY --from=build /out/*.deb /
