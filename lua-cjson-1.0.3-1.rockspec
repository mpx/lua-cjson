package = "lua-cjson"
version = "1.0.3-1"

source = {
    url = "http://www.kyne.com.au/~mark/software/lua-cjson-1.0.3.zip",
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
            defines = { "VERSION=\"1.0.3\"" }
        }
    },
    copy_directories = { "tests" }
}
