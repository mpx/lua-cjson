#!/bin/sh

MAKE=make
#MAKE=gmake

EGREP="grep -E"
#EGREP="egrep"

set -e

do_tests() {
    echo
    cd tests
    ./test.lua | $EGREP 'version|PASS|FAIL'
    cd ..
}

cat <<EOT
Please ensure you do not have the Lua CJSON module installed before
running these tests.

EOT

echo "===== Setting LuaRocks PATH ====="
eval "`luarocks path`"

echo "===== Building UTF-8 test data ====="
( cd tests && ./genutf8.pl; )

echo "===== Cleaning old build data ====="
$MAKE clean
rm -f tests/cjson.so

echo "===== Testing LuaRocks build ====="
luarocks make --local
do_tests
luarocks remove --local lua-cjson
$MAKE clean

echo "===== Testing Makefile build ====="
$MAKE
cp cjson.so tests
do_tests
$MAKE clean
rm -f tests/cjson.so
