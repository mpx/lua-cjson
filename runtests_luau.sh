#!/bin/bash

set -eoux pipefail

ARG1=${1:-}

clear
if [[ $ARG1 == "--rst" ]]; then
    rm -rf _build || true
fi
cmake -G Ninja -B _build -S . -DUSE_INTERNAL_FPCONV=ON -DUSE_LUAU=ON -DCOMPILE_LUAU_TEST=ON \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build _build --config RelWithDebInfo
cd tests
if [ ! -f utf8.dat ]; then
    ./genutf8.pl
fi
../_build/luau_test luau_test.lua

