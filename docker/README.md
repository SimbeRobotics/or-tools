# Simbe or-tools Debian packages

This branch (based on the upstream `v9.7` tag) adds a Docker-based build that
packages the or-tools C++ library as Debian packages for the private
`robot-apt` repository in Artifact Registry. It follows the same shape as the
fuse deb build (`SimbeRobotics/fuse`: `docker-bake.hcl` + `docker/`).

| File | Purpose |
|---|---|
| `docker-bake.hcl` | Bake matrix: `focal` and `noble`, each for `linux/amd64` and `linux/arm64`. |
| `docker/Dockerfile` | Ubuntu build stage, then a `scratch` stage holding only the `.deb`. |
| `docker/build-deb.sh` | Configures, builds and packages or-tools. |

## Building

The build runs on Depot (currently borrowing the Tally project, like fuse),
which builds each architecture on a native machine:

```sh
ORTOOLS_PATCH=$(git rev-list --count v9.0..v9.7) \
  depot bake --project t795bp4f73
```

This builds all four packages into `output/<codename>/linux_<arch>/`. To build
one release, name its target (`ortools-deb-focal` or `ortools-deb-noble`); to
build one architecture, add e.g.
`--set ortools-deb-noble.platform=linux/amd64`.

Plain `docker buildx bake` reads the same file. On an x86 host the arm64 builds
then go through QEMU emulation, which takes hours instead of minutes.

`ORTOOLS_PATCH` is required. Upstream derives the patch number from git
history, which `.dockerignore` keeps out of the build context. Without it CMake
would silently use `9999`, so the build refuses to run. Count to the `v9.7`
tag rather than `HEAD`: `2996` matches upstream's own 9.7 release, and counting
to `HEAD` would bump it with every Simbe commit on this branch. Packaging-only
changes bump `DEB_REVISION` instead.

A cold build takes a few minutes per target on Depot; a ccache cache mount
(one per codename/arch) makes rebuilds after a source change much faster.

## Publishing

```sh
for deb in output/*/*/*.deb; do
  gcloud artifacts apt upload robot-apt --location=us --project=simbe-cloud \
    --source="$deb" --quiet
done
```

A version can only be uploaded once. To republish the same upstream version
with packaging changes, rebuild with `DEB_REVISION=2` (and so on).

## Package layout and naming

- **Names:** `simbe-ortools-focal` and `simbe-ortools-noble`, version
  `9.7.2996-simbe1`. `robot-apt` is a single flat suite read by both the focal
  and noble containers, so the release has to be in the package name. A
  `~focal`/`~noble` version suffix would let apt install whichever sorts
  highest. These names match the rosdep keys in tally's `simbe-rosdep.yaml`
  (`tsp-route-solver-cpp` branch).
- **Mutual exclusion:** both packages install to the same path, so each
  declares `Provides: simbe-ortools` and `Conflicts: simbe-ortools`.
- **Contents:** headers, static `.a` archives and the CMake config under
  `/opt/ortools`, plus `bin/protoc-23.3.0`. There are no shared libraries, so
  nothing has to be on the library path at runtime.
- **Consuming it:** `find_package(ortools CONFIG REQUIRED)` with
  `CMAKE_PREFIX_PATH=/opt/ortools`, then link `ortools::ortools`.

## Build decisions

- **Bundled dependencies (`BUILD_DEPS=ON`).** or-tools 9.7 builds its own
  abseil 20230125.3, protobuf v23.3, re2, Eigen and zlib. These are newer than
  what focal ships and differ from noble's.
- **Static (`BUILD_SHARED_LIBS=OFF`, PIC on).** A shared `libortools.so` in
  `/opt/ortools/lib` would not be found at load time (that path is deliberately
  off the library path), so consumers such as simbe_soul would not start.
- **Hidden visibility** (`CMAKE_{C,CXX}_VISIBILITY_PRESET=hidden`,
  `CMAKE_VISIBILITY_INLINES_HIDDEN=ON`). This stops the vendored protobuf and
  abseil symbols from being exported by a consumer and interposed against the
  system `libprotobuf` that ROS links (the dynamic linker binds first-wins).
- **`--exclude-libs` on `ortools::ortools`.** Hidden visibility alone left two
  symbols exported from a consumer `.so`: `std::` template instantiations over
  protobuf types. libstdc++ marks `namespace std` as default visibility, so
  hidden visibility doesn't reach them. `build-deb.sh` appends an
  `INTERFACE_LINK_OPTIONS` entry to the installed `ortoolsConfig.cmake` that
  passes `--exclude-libs` for every archive in `/opt/ortools/lib`. Consumers get
  it without changing their own CMake.
- **Unused solvers and tools are off:** `BUILD_FLATZINC`, `BUILD_LP_PARSER`,
  `USE_SCIP`, `USE_COINOR`, `USE_GLPK`, `USE_HIGHS`, plus samples, examples,
  tests and the Python/Java/.NET bindings. `solve` and `sat_runner` are
  installed unconditionally, so they are deleted after install.
- **`protoc` is kept.** Protobuf's exported CMake config checks that the file
  exists, so `find_package(ortools)` fails without it. It sits in
  `/opt/ortools/bin`, which is not on `PATH`.
- **No `-g` or LTO.** The script calls CMake directly (Release, stripped
  install) rather than `dpkg-buildpackage`, so `dpkg-buildflags` never adds
  `-g` or noble's `-flto=auto -ffat-lto-objects`. The packages are 12–14 MB.
- **Focal CMake.** or-tools 9.7 needs CMake 3.18 or newer, and focal ships
  3.16. The Dockerfile installs a newer one from PyPI (`cmake>=3.18,<3.28`)
  only when the distro version is too old. GCC 9 on focal builds 9.7 cleanly.
- **Parallelism** is capped at one job per 2 GB of RAM, so the heaviest
  translation units can't run the builder out of memory.
- **Runtime `Depends`** are computed by `dpkg-shlibdeps`: only libc6,
  libgcc-s1 and libstdc++6.

## Verification

During development, a throwaway consumer (a shared library solving a
four-city TSP with the routing library, plus an executable calling it) was
built against the installed package for all four targets. It found the
optimal route. Neither binary loaded or-tools, protobuf or abseil dynamically,
and neither exported any protobuf or abseil symbol
(`nm -D --defined-only ... | grep -cE 'protobuf|absl'` gave 0). That check
is not part of the build.

## Known limitations

- The packages have only been exercised inside the build container, and
  nothing in the build re-checks for symbol leaks. They have not yet been
  installed in the robot containers or linked into simbe_soul.
- Hidden visibility stops or-tools from *exporting* its protobuf. It cannot
  help if a consumer's own code also includes system protobuf headers and links
  the system `libprotobuf`. Protobuf 23 and the system version share symbol
  names, so that would be an ODR clash in the consumer's own link. abseil is
  safe because its symbols carry a versioned inline namespace.
- There is no GitHub Actions workflow yet. The fuse workflow (Depot bake,
  workload identity, upload only from the mainline branch) would carry over
  almost unchanged, but it needs a service account with write access to
  `robot-apt`.
