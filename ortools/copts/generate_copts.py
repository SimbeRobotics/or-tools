#!/usr/bin/env python3
# Copyright 2010-2025 Google LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Generate copts for OR-Tools."""

from collections.abc import Sequence

from absl import app

from ortools.copts import generate_copts_lib


def _write_file(build_system: generate_copts_lib.BuildSystem) -> None:
    """Write the copts file for the given build system."""
    content = generate_copts_lib.get_file_content(build_system)
    file_name = generate_copts_lib.get_file_name(build_system)
    path = f"ortools/copts/{file_name}"
    with open(path, "w") as f:
        f.write(content)


def main(argv: Sequence[str]) -> None:
    if len(argv) > 1:
        raise app.UsageError("Too many command-line arguments.")

    for build_system in generate_copts_lib.BuildSystem:
        _write_file(build_system)


if __name__ == "__main__":
    app.run(main)
