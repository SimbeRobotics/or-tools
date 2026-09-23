#!/bin/bash
# ------------------------------------------------------------------------------
# docker/build-deb.sh
# ------------------------------------------------------------------------------
# Builds the or-tools C++ library and packages it as a single Debian package.
#
# This is a static, development-only package: headers, .a archives and CMake
# config under /opt/ortools, for consumers to link with find_package(ortools)
# and CMAKE_PREFIX_PATH=/opt/ortools. Nothing needs to be found at load time,
# so /opt/ortools stays off the library path.
#
# or-tools vendors its own abseil and protobuf, newer than what Ubuntu ships.
# Everything is compiled with hidden visibility so that, once linked into a
# consumer, those copies can't be exported and interposed against the system
# libprotobuf that ROS links (the dynamic linker binds first-wins).
# ------------------------------------------------------------------------------
# Copyright (c) 2026, Simbe Robotics, Inc.
# ------------------------------------------------------------------------------
set -euo pipefail

PREFIX=/opt/ortools
UBUNTU_CODENAME="${UBUNTU_CODENAME:?}"
# robot-apt is a single flat suite that both focal and noble containers read,
# so a codename in the version would just let apt pick whichever sorts
# highest. The release goes in the package name instead, matching the rosdep
# keys in tally.
PKG_NAME="simbe-ortools-${UBUNTU_CODENAME}"
DEB_REVISION="${DEB_REVISION:-1}"

# Without .git in the build context, CMake would silently fall back to a patch
# number of 9999. Refuse to build rather than publish a misleading version.
if [ -z "${ORTOOLS_PATCH:-}" ]; then
  echo "ERROR: ORTOOLS_PATCH is not set; pass \$(git rev-list --count v9.0..HEAD)" >&2
  exit 1
fi
# CMake's set_version() reads this from the environment.
export OR_TOOLS_PATCH="${ORTOOLS_PATCH}"

MAJOR="$(sed -n 's/^OR_TOOLS_MAJOR=//p' Version.txt)"
MINOR="$(sed -n 's/^OR_TOOLS_MINOR=//p' Version.txt)"
UPSTREAM_VERSION="${MAJOR}.${MINOR}.${ORTOOLS_PATCH}"
DEB_VERSION="${UPSTREAM_VERSION}-simbe${DEB_REVISION}"
DEB_ARCH="$(dpkg --print-architecture)"

# The heaviest or-tools translation units need ~2 GB each; running one job per
# core can run the builder out of memory.
if [ -z "${JOBS:-}" ]; then
  cores="$(nproc)"
  mem_jobs="$(awk '/^MemTotal/ { print int($2 / 1024 / 1024 / 2) }' /proc/meminfo)"
  JOBS=$(( cores < mem_jobs ? cores : mem_jobs ))
  [ "${JOBS}" -ge 1 ] || JOBS=1
fi
echo "==> building or-tools ${UPSTREAM_VERSION} (${DEB_ARCH}, ${JOBS} jobs)"

cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_C_VISIBILITY_PRESET=hidden \
  -DCMAKE_CXX_VISIBILITY_PRESET=hidden \
  -DCMAKE_VISIBILITY_INLINES_HIDDEN=ON \
  -DBUILD_DEPS=ON \
  -DBUILD_CXX=ON \
  -DBUILD_PYTHON=OFF \
  -DBUILD_JAVA=OFF \
  -DBUILD_DOTNET=OFF \
  -DBUILD_FLATZINC=OFF \
  -DBUILD_LP_PARSER=OFF \
  -DUSE_COINOR=OFF \
  -DUSE_GLPK=OFF \
  -DUSE_HIGHS=OFF \
  -DUSE_SCIP=OFF \
  -DBUILD_SAMPLES=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_TESTING=OFF

cmake --build build --parallel "${JOBS}"
ccache --show-stats || true

# Install for real (this is a throwaway container) so the smoke test below
# exercises the same absolute paths a robot image will see.
rm -rf "${PREFIX}"
cmake --install build --strip

# solve and sat_runner are installed unconditionally but aren't part of the
# exported CMake targets, so they can go. protoc has to stay: protobuf's
# exported config checks that it exists, and find_package(ortools) fails
# without it.
rm -f "${PREFIX}/bin/solve" "${PREFIX}/bin/sat_runner"

# Hidden visibility can't cover everything: libstdc++ marks namespace std as
# default visibility, so e.g. std::vector<protobuf-type> instantiations inside
# the archives would still be exported from a consumer's .so. --exclude-libs
# hides every symbol pulled from the listed archives, and attaching it to the
# imported target means consumers get it without changing their own CMake.
ARCHIVES="$(cd "${PREFIX}/lib" && ls -1 ./*.a | sed 's|^\./||' | paste -sd: -)"
if [ -z "${ARCHIVES}" ]; then
  echo "ERROR: no static archives under ${PREFIX}/lib" >&2
  exit 1
fi
cat >> "${PREFIX}/lib/cmake/ortools/ortoolsConfig.cmake" <<EOF

# Simbe: keep the vendored static dependencies out of consumers' dynamic
# symbol tables (added by docker/build-deb.sh).
if(TARGET ortools::ortools)
  set_property(TARGET ortools::ortools APPEND PROPERTY
    INTERFACE_LINK_OPTIONS "LINKER:--exclude-libs,${ARCHIVES}")
endif()
EOF

# Link a small routing library against the install the way a consumer would,
# run it, and check neither it nor its executable exports the vendored
# protobuf/abseil symbols.
echo "==> smoke-testing the install"
SMOKE_SRC="$(pwd)/docker/smoke-test"
rm -rf /tmp/smoke
cmake -S "${SMOKE_SRC}" -B /tmp/smoke -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="${PREFIX}"
cmake --build /tmp/smoke
/tmp/smoke/smoke
for bin in /tmp/smoke/smoke /tmp/smoke/libsmoke_route.so; do
  if ldd "${bin}" | grep -E 'ortools|protobuf|absl'; then
    echo "ERROR: ${bin} still loads or-tools/protobuf/abseil dynamically" >&2
    exit 1
  fi
  exported="$(nm -D --defined-only "${bin}" | grep -cE 'protobuf|absl' || true)"
  echo "==> protobuf/abseil symbols exported by $(basename "${bin}"): ${exported}"
  if [ "${exported}" -ne 0 ]; then
    nm -DC --defined-only "${bin}" | grep -E 'protobuf|absl' | head -20 >&2
    echo "ERROR: vendored protobuf/abseil symbols leak out of ${bin}" >&2
    exit 1
  fi
done

# Stage inside a debian/ tree so dpkg-shlibdeps recognises anything bundled
# as belonging to this package rather than as a missing dependency.
WORK=/work
STAGE="${WORK}/debian/${PKG_NAME}"
rm -rf "${WORK}"
mkdir -p "${STAGE}/DEBIAN" "${STAGE}$(dirname "${PREFIX}")"
cp -a "${PREFIX}" "${STAGE}${PREFIX}"

# dpkg-shlibdeps only needs enough of a source package to know our name.
cat > "${WORK}/debian/control" <<EOF
Source: ${PKG_NAME}

Package: ${PKG_NAME}
Architecture: any
EOF

# Resolved up front rather than inline, where a failure would be swallowed and
# silently yield a package with no runtime dependencies.
ELF_FILES="$(find "${STAGE}${PREFIX}" -type f \
  -exec sh -c 'file -b "$1" | grep -q "^ELF"' _ {} \; -print)"
if [ -z "${ELF_FILES}" ]; then
  echo "ERROR: install produced no ELF files under ${STAGE}${PREFIX}" >&2
  exit 1
fi

# shellcheck disable=SC2086
DEPENDS="$(cd "${WORK}" && dpkg-shlibdeps -O --ignore-missing-info \
  -l"${STAGE}${PREFIX}/lib" ${ELF_FILES} \
  | sed -n 's/^shlibs:Depends=//p')"
echo "==> runtime dependencies: ${DEPENDS}"

INSTALLED_SIZE="$(du -sk "${STAGE}${PREFIX}" | cut -f1)"

cat > "${STAGE}/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${DEB_VERSION}
Architecture: ${DEB_ARCH}
Maintainer: Nandini Thakur <nandini.thakur@simberobotics.com>
Section: libdevel
Priority: optional
Installed-Size: ${INSTALLED_SIZE}
Depends: ${DEPENDS}
Provides: simbe-ortools
Conflicts: simbe-ortools
Homepage: https://developers.google.com/optimization
Description: Google OR-Tools C++ static library (Simbe build)
 OR-Tools ${UPSTREAM_VERSION} static C++ libraries, headers and CMake config
 for Ubuntu ${UBUNTU_CODENAME}, without SCIP, COIN-OR, GLPK, HiGHS or
 FlatZinc. Built with bundled
 dependencies and installed under ${PREFIX} so they cannot conflict with
 system libraries. The per-release packages all install to the same path and
 so conflict with one another.
EOF

OUT=/out
mkdir -p "${OUT}"
dpkg-deb --root-owner-group --build "${STAGE}" \
  "${OUT}/${PKG_NAME}_${DEB_VERSION}_${DEB_ARCH}.deb"

dpkg --info "${OUT}"/*.deb
ls -la "${OUT}"
