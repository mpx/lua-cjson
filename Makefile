CJSON_VERSION = 1.0.4
LUA_VERSION =   5.1

## Available Lua CJSON specific workarounds
#
# To ensure JSON encoding/decoding works correctly for locales using
# comma decimal separators, Lua CJSON must be compiled with one of
# these options:
# USE_POSIX_USELOCALE: Linux, OSX. Thread safe. Recommended option.
# USE_POSIX_SETLOCALE: Works on all ANSI C platforms. May be used when
#                      thread-safety isn't required.
#
# USE_INTERNAL_ISINF: Workaround for Solaris platforms missing isinf().

## Common build defaults
PREFIX =            /usr/local
CFLAGS_EXTRA =      -DUSE_POSIX_SETLOCALE
LDFLAGS_EXTRA =     -shared

## Platform overrides
#
# Tweaking one of the platform sections below to suit your situation.
#
# See http://lua-users.org/wiki/BuildingModules for further platform
# specific details.

## Linux
CFLAGS_EXTRA =      -DUSE_POSIX_USELOCALE

## FreeBSD
#LUA_INCLUDE_DIR =   $(PREFIX)/include/lua51

## MacOSX (Macports)
#PREFIX =            /opt/local
#CFLAGS_EXTRA =      -DUSE_POSIX_USELOCALE
#LDFLAGS_EXTRA =     -bundle -undefined dynamic_lookup

## Solaris
#CFLAGS_EXTRA =      -DUSE_POSIX_SETLOCALE -DUSE_INTERNAL_ISINF

## End platform specific section

LUA_INCLUDE_DIR ?=  $(PREFIX)/include
LUA_LIB_DIR ?=      $(PREFIX)/lib/lua/$(LUA_VERSION)

#CFLAGS ?=           -g -Wall -pedantic -fno-inline
CFLAGS ?=           -O3 -Wall -pedantic
override CFLAGS +=  $(CFLAGS_EXTRA) -fpic -I$(LUA_INCLUDE_DIR) -DVERSION=\"$(CJSON_VERSION)\"
override LDFLAGS += $(LDFLAGS_EXTRA)

INSTALL ?= install

.PHONY: all clean install package

all: cjson.so

cjson.so: lua_cjson.o strbuf.o
	$(CC) $(LDFLAGS) -o $@ $^

install:
	$(INSTALL) -d $(DESTDIR)/$(LUA_LIB_DIR)
	$(INSTALL) cjson.so $(DESTDIR)/$(LUA_LIB_DIR) 

clean:
	rm -f *.o *.so

package:
	git archive --prefix="lua-cjson-$(CJSON_VERSION)/" master | \
		gzip -9 > "lua-cjson-$(CJSON_VERSION).tar.gz"
	git archive --prefix="lua-cjson-$(CJSON_VERSION)/" \
		-o "lua-cjson-$(CJSON_VERSION).zip" master
