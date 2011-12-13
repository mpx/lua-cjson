#!/bin/sh

EGREP="grep -E"

PLATFORM="`uname -s`"

[ "$PLATFORM" = "SunOS" ] && EGREP=egrep

set -e

do_tests() {
    echo
    cd tests
    ./test.lua | $EGREP 'version|PASS|FAIL'
    cd ..
}

echo "===== Setting LuaRocks PATH ====="
eval "`luarocks path`"

echo "===== Building UTF-8 test data ====="
( cd tests && ./genutf8.pl; )

echo "===== Cleaning old build data ====="
make clean
rm -f tests/cjson.so

echo "===== Verifying cjson.so is not installed ====="

cd tests
if lua -e 'require "cjson"' 2>/dev/null
then
	cat <<EOT
Please ensure you do not have the Lua CJSON module installed before
running these tests.
EOT
	exit
fi
cd ..

echo "===== Testing LuaRocks build ====="
luarocks make --local
do_tests
luarocks remove --local lua-cjson
make clean

echo "===== Testing Makefile build ====="
make
cp cjson.so tests
do_tests
make clean
rm -f tests/cjson.so

if [ "$PLATFORM" = "Linux" ]
then
	echo "===== Testing RPM build ====="
	make package
	LOG=/tmp/build.$$
	rpmbuild -tb lua-cjson-1.0.4.tar.gz | tee "$LOG"
	RPM="`awk '/^Wrote: / && ! /debuginfo/ { print $2}' < "$LOG"`"
	sudo -- rpm -Uvh \"$RPM\"
	do_tests
	sudo -- rpm -e lua-cjson
	rm -f "$LOG"
fi
