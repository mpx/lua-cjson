package = "lua-cjson"
version = "git-1"

description = {
    summary = "A fast JSON encoding/parsing module",
    detailed = [[
        The Lua CJSON module provides JSON support for Lua. It features:
        - Fast, standards compliant encoding/parsing routines
        - Full support for JSON with UTF-8, including decoding surrogate pairs
        - Optional run-time support for common exceptions to the JSON specification
          (infinity, NaN,..)
        - No dependencies on other libraries
    ]],
    homepage = "http://www.kyne.com.au/~mark/software/lua-cjson.php",
    license = "MIT"
}

source = {
    url = "https://git.inconcert/lua-libraries/lua-cjson",
    dir = "lua-cjson"
}

dependencies = {
    "lua >= 5.1"
}

build = {
    type = "builtin",
    modules = {
        cjson = {
            defines = { "MULTIPLE_THREADS" },
            sources = { "lua_cjson.c", "strbuf.c", "fpconv.c" },
            defines = {
-- LuaRocks does not support platform specific configuration for Solaris.
-- Uncomment the line below on Solaris platforms if required.
--                "USE_INTERNAL_ISINF"
            }
        }
    },
    install = {
        lua = {
            ["cjson.util"] = "lua/cjson/util.lua"
        },
        bin = {
            json2lua = "lua/json2lua.lua",
            lua2json = "lua/lua2json.lua"
        }
    },
    -- Override default build options (per platform)
    platforms = {
        win32 = { modules = { cjson = { defines = {
            "MULTIPLE_THREADS", "DISABLE_INVALID_NUMBERS"
        } } } }
    },
    copy_directories = { "tests" }
}

-- Para compilar lua-cjson en windows:
-- luarocks make CFLAGS="/TP /MD /O2 -DMULTIPLE_THREADS -DUSE_INTERNAL_FPCONV"


-- vi:ai et sw=4 ts=4:
