CJSON_VERSION = 1.0.3
LUA_VERSION =   5.1

# See http://lua-users.org/wiki/BuildingModules for platform specific
# details.

## Linux/BSD
PREFIX ?=          /usr/local
LDFLAGS +=         -shared

## OSX (Macports)
#PREFIX ?=          /opt/local
#LDFLAGS +=         -bundle -undefined dynamic_lookup

LUA_INCLUDE_DIR ?= $(PREFIX)/include
LUA_LIB_DIR ?=     $(PREFIX)/lib/lua/$(LUA_VERSION)

#CFLAGS ?=          -g -Wall -pedantic -fno-inline
CFLAGS ?=          -g -O3 -Wall -pedantic
override CFLAGS += -fpic -I$(LUA_INCLUDE_DIR) -DVERSION=\"$(CJSON_VERSION)\"

## Optional work arounds
# Handle Solaris platforms that are missing isinf().
#override CFLAGS +=  -DUSE_INTERNAL_ISINF
# Handle locales that use comma as a decimal separator on locale aware
# platforms (optional, but recommended).
# USE_POSIX_USELOCALE: Linux, OSX. Thread safe. Recommended option.
# USE_POSIX_SETLOCALE: Works on all ANSI C platforms. May be used when
#                      thread-safety isn't required.
override CFLAGS +=  -DUSE_POSIX_USELOCALE
#override CFLAGS +=  -DUSE_POSIX_SETLOCALE

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
