package = "lua-cjson"
version = "1.0.4-1"

source = {
    url = "http://www.kyne.com.au/~mark/software/lua-cjson-1.0.4.zip",
}

description = {
    summary = "Fast JSON encoding/parsing support for Lua",
    detailed = [[
        Lua CJSON provides fast UTF-8 JSON parsing/encoding support for Lua,
        and has no external dependencies.
    ]],
    homepage = "http://www.kyne.com.au/~mark/software/lua-cjson.php",
    license = "MIT"
}

dependencies = {
    "lua >= 5.1"
}

build = {
    type = "builtin",
    modules = {
        cjson = {
            sources = { "lua_cjson.c", "strbuf.c" },
-- Optional workarounds:
-- USE_POSIX_USELOCALE: Linux, OSX. Thread safe. Recommended.
-- USE_POSIX_SETLOCALE: Works on all ANSI C platforms. May be used when
--                      thread-safety isn't required.
-- USE_INTERNAL_ISINF:  Provide internal isinf() implementation. Required
--                      on some Solaris platforms.
            defines = { "VERSION=\"1.0.4\"", "USE_POSIX_SETLOCALE" }
        }
    },
    copy_directories = { "tests" }
}
