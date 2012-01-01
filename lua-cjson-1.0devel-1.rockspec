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
-- LuaRocks does not support platform specific configuration for Solaris.
-- Uncomment the line below on Solaris platforms if required.
--                "USE_INTERNAL_ISINF"
            }
        }
    },
    -- Override default build options (per platform)
    platforms = {
        win32 = { modules = { cjson = { defines = {
            "DISABLE_INVALID_NUMBERS"
        } } } }
    },
    copy_directories = { "tests" }
}

-- vi:ai et sw=4 ts=4:
