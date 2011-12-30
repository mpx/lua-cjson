package = "lua-cjson"
version = "1.0devel-1"

source = {
    url = "http://www.kyne.com.au/~mark/software/lua-cjson-1.0devel.zip",
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
            sources = { "lua_cjson.c", "strbuf.c", "fpconv.c" },
            defines = {
-- Optional workaround:
-- USE_INTERNAL_ISINF:  Provide internal isinf() implementation. Required
--                      on some Solaris platforms.
-- LuaRocks does not support platform specific configuration for Solaris.
-- Uncomment the line below on Solaris platforms.
--                "USE_INTERNAL_ISINF"
            }
        }
    },
    copy_directories = { "tests" }
}

-- vi:ai et sw=4 ts=4:
