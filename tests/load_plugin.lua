------------------------------------------------------------------------
-- load_plugin.lua - Extract and load Lua code from the plugin XML
-- This parses the CDATA section from Search_and_Destroy_v2.xml and
-- executes it in the global environment so tests can access all modules.
------------------------------------------------------------------------

local function load_plugin()
   -- Find the plugin XML file relative to tests/ directory
   local script_dir = debug.getinfo(1, "S").source:match("@(.+)/[^/]+$") or
                      debug.getinfo(1, "S").source:match("@(.+)\\[^\\]+$") or "tests"
   local plugin_dir = script_dir:match("(.+)/tests$") or script_dir:match("(.+)\\tests$") or ".."

   local plugin_path = plugin_dir .. "/Search_and_Destroy_v2.xml"

   -- Read the plugin XML file
   local f = io.open(plugin_path, "r")
   if not f then
      -- Try alternate paths
      plugin_path = "Search_and_Destroy_v2.xml"
      f = io.open(plugin_path, "r")
      if not f then
         plugin_path = "../Search_and_Destroy_v2.xml"
         f = io.open(plugin_path, "r")
      end
   end

   if not f then
      error("Cannot find Search_and_Destroy_v2.xml - run from the plugin directory or tests/ directory")
   end

   local content = f:read("*a")
   f:close()

   -- Extract Lua code from CDATA section
   local lua_code = content:match("<![[]CDATA[[](.-)]]>")
   if not lua_code then
      error("Cannot find CDATA section in plugin XML")
   end

   -- Remove require statements that won't work outside MUSHclient
   -- (json and sqlite3 are handled by mock_mushclient.lua)
   lua_code = lua_code:gsub('json = require "json"', '-- json loaded by mock')
   lua_code = lua_code:gsub('sqlite3 = require "lsqlite3"', '-- sqlite3 loaded by mock')

   -- Execute the Lua code in the global environment
   local load_fn = loadstring or load
   local fn, err = load_fn(lua_code, "Search_and_Destroy_v2")
   if not fn then
      error("Failed to parse plugin Lua code: " .. tostring(err))
   end

   local ok, err2 = pcall(fn)
   if not ok then
      error("Failed to execute plugin Lua code: " .. tostring(err2))
   end

   return true
end

return load_plugin
