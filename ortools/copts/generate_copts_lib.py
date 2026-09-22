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

import enum

from ortools.copts import copts


class BuildSystem(enum.Enum):
    BAZEL = 1
    CMAKE = 2


_HEADER = [
    "GENERATED! DO NOT MANUALLY EDIT THIS FILE.",
    " - Edit ortools/copts/copts.py.",
    " - Run `bazel run //ortools/copts:generate_copts`.",
]


def _get_variable_name(compiler: str, flag_type: str) -> str:
    return f"ORTOOLS_{compiler.upper()}_{flag_type.upper()}"


class _ContentGenerator:
    """Generate content for a file."""

    lines: list[str]
    build_system: BuildSystem

    def __init__(self, build_system: BuildSystem = BuildSystem.BAZEL):
        self.lines = []
        self.build_system = build_system

    def add_line(self, line: str = "") -> None:
        self.lines.append(line)

    def add_comment(self, lines: list[str]) -> None:
        if self.build_system == BuildSystem.BAZEL:
            self.add_line('"""')
            for line in lines:
                self.add_line(line)
            self.add_line('"""')
        elif self.build_system == BuildSystem.CMAKE:
            for line in lines:
                self.add_line(f"# {line}")

    def get_content(self) -> str:
        return "\n".join(self.lines)

    def add_variable(self, name: str, values: list[str]) -> None:
        """Add a variable to the file."""
        if self.build_system == BuildSystem.BAZEL:
            self.add_line(f"{name} = [")
            for value in values:
                self.add_line(f'    "{value}",')
            self.add_line("]")
        if self.build_system == BuildSystem.CMAKE:
            self.add_line(f"list(APPEND {name}")
            for value in values:
                self.add_line(f'    "{value}"')
            self.add_line(")")


def get_file_name(build_system: BuildSystem) -> str:
    return {
        BuildSystem.BAZEL: "GENERATED_copts.bzl",
        BuildSystem.CMAKE: "GENERATED_ORToolsCopts.cmake",
    }[build_system]


def get_file_content(build_system: BuildSystem) -> str:
    """Generate the content of the options file."""
    generator = _ContentGenerator(build_system)
    generator.add_comment(_HEADER)
    for compiler, compiler_flags in copts.COPT_VARS.items():
        assert compiler_flags.keys() == {"flags", "test_flags", "linkopts"}
        for flag_type in ["flags", "test_flags", "linkopts"]:
            variable_name = _get_variable_name(compiler, flag_type)
            generator.add_variable(variable_name, compiler_flags[flag_type])
    generator.add_line()
    return generator.get_content()
