# ------------------------------------------------------------------------------
# docker/smoke-test/CMakeLists.txt
# ------------------------------------------------------------------------------
# Minimal consumer of the packaged or-tools, built by docker/build-deb.sh
# against the installed /opt/ortools exactly as a robot package would be.
# ------------------------------------------------------------------------------
# Copyright (c) 2026, Simbe Robotics, Inc.
# ------------------------------------------------------------------------------
cmake_minimum_required(VERSION 3.18)
project(ortools_smoke_test LANGUAGES CXX)

find_package(ortools CONFIG REQUIRED)

add_library(smoke_route SHARED route.cc)
target_compile_features(smoke_route PRIVATE cxx_std_17)
target_link_libraries(smoke_route PRIVATE ortools::ortools)

add_executable(smoke main.cc)
target_link_libraries(smoke PRIVATE smoke_route)
