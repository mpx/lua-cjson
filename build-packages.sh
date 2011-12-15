#!/bin/sh

# build-packages.sh [ VERSION [ BRANCH ] ]

# No args: Build current 1.0devel packages
# 1 args: Build release package for VERSION (>= 1.0.5)
# 2 args: Build release package for VERSION from BRANCH

# Files requiring a version bump
VERSION_FILES="lua-cjson-1.0devel-1.rockspec lua-cjson.spec lua_cjson.c manual.txt runtests.sh"

if [ "$1" ]
then
    VERSION="$1"
    BRANCH="cjson-$VERSION"
    VER_BUMP=1
else
    VERSION=1.0devel
    BRANCH=master
fi

[ "$2" ] && BRANCH="$2"

PREFIX="lua-cjson-$VERSION"

set -x
set -e

DESTDIR="`pwd`/packages"
mkdir -p "$DESTDIR"
BUILDROOT="`mktemp -d`"
trap "rm -rf '$BUILDROOT'" 0

git archive --prefix="$PREFIX/" "$BRANCH" | tar xf - -C "$BUILDROOT"
cd "$BUILDROOT"

if [ "$VER_BUMP" ]; then
    ( cd "$PREFIX"
      rename 1.0devel "$VERSION" $VERSION_FILES
      perl -pi -e "s/\\b1.0devel\\b/$VERSION/g" ${VERSION_FILES/1.0devel/$VERSION}; )
fi
make -C "$PREFIX" doc
tar cf - "$PREFIX" | gzip -9 > "$DESTDIR/$PREFIX.tar.gz"
zip -9rq "$DESTDIR/$PREFIX.zip" "$PREFIX"

# vi:ai et sw=4 ts=4:
