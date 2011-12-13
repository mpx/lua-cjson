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

## Build defaults
PREFIX =            /usr/local
#CFLAGS =            -g -Wall -pedantic -fno-inline
CFLAGS =            -O3 -Wall -pedantic
CJSON_CFLAGS =      -DUSE_POSIX_SETLOCALE
CJSON_LDFLAGS =     -shared
LUA_INCLUDE_DIR =   $(PREFIX)/include
LUA_MODULE_DIR =    $(PREFIX)/lib/lua/$(LUA_VERSION)
INSTALL_CMD =       install

## Platform overrides
#
# Tweak one of the platform sections below to suit your situation.
#
# See http://lua-users.org/wiki/BuildingModules for further platform
# specific details.

## Linux
#CJSON_CFLAGS =      -DUSE_POSIX_USELOCALE

## FreeBSD
#LUA_INCLUDE_DIR =   $(PREFIX)/include/lua51

## MacOSX (Macports)
#PREFIX =            /opt/local
#CJSON_CFLAGS =      -DUSE_POSIX_USELOCALE
#CJSON_LDFLAGS =     -bundle -undefined dynamic_lookup

## Solaris
#CJSON_CFLAGS =      -DUSE_POSIX_SETLOCALE -DUSE_INTERNAL_ISINF

## End platform specific section

BUILD_CFLAGS =      -fpic -I$(LUA_INCLUDE_DIR) $(CJSON_CFLAGS)
OBJS :=             lua_cjson.o strbuf.o

.PHONY: all clean install package doc

all: cjson.so

doc: manual.html

.c.o:
	$(CC) -c $(CFLAGS) $(CPPFLAGS) $(BUILD_CFLAGS) -o $@ $<

cjson.so: $(OBJS)
	$(CC) $(LDFLAGS) $(CJSON_LDFLAGS) -o $@ $(OBJS)

install: cjson.so
	mkdir -p $(DESTDIR)/$(LUA_MODULE_DIR)
	$(INSTALL_CMD) cjson.so $(DESTDIR)/$(LUA_MODULE_DIR)

manual.html: manual.txt
	asciidoc -n -a toc manual.txt

clean:
	rm -f *.o *.so

package:
	git archive --prefix="lua-cjson-$(CJSON_VERSION)/" master | \
		gzip -9 > "lua-cjson-$(CJSON_VERSION).tar.gz"
	git archive --prefix="lua-cjson-$(CJSON_VERSION)/" \
		-o "lua-cjson-$(CJSON_VERSION).zip" master
