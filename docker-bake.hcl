# ------------------------------------------------------------------------------
# docker-bake.hcl
# ------------------------------------------------------------------------------
# Bake configuration for the or-tools C++ Debian package. The patch number is
# normally derived from git history, which isn't in the build context, so it
# has to be passed in:
#
#   ORTOOLS_PATCH=$(git rev-list --count v9.0..v9.7) \
#     depot bake --project t795bp4f73
#
# builds every release/arch combination; name one (e.g. ortools-deb-noble) to
# build just that release. Plain `docker buildx bake` works the same way.
# Results land in ./output.
# ------------------------------------------------------------------------------
# Copyright (c) 2026, Simbe Robotics, Inc.
# ------------------------------------------------------------------------------

variable "ORTOOLS_PATCH" {
  default = ""
}

# Bump this to republish the same upstream version with packaging changes.
variable "DEB_REVISION" {
  default = "1"
}

group "default" {
  targets = ["ortools-deb"]
}

target "ortools-deb" {
  name       = "ortools-deb-${codename}"
  matrix     = { codename = ["focal", "noble"] }
  context    = "."
  dockerfile = "docker/Dockerfile"
  target     = "deb"

  args = {
    UBUNTU_CODENAME = codename
    ORTOOLS_PATCH   = ORTOOLS_PATCH
    DEB_REVISION    = DEB_REVISION
  }

  # Depot builds each platform on a native machine, so arm64 is no slower
  # than amd64. With plain buildx, arm64 on an x86 host goes through QEMU.
  platforms = ["linux/amd64", "linux/arm64"]

  # Multi-platform local output lands in output/<codename>/linux_<arch>/.
  output = ["type=local,dest=output/${codename}"]
}
