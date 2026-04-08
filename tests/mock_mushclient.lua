------------------------------------------------------------------------
-- mock_mushclient.lua - Mock MUSHclient APIs for standalone testing
-- This module stubs out all MUSHclient APIs so plugin code can run
-- outside of MUSHclient for unit testing.
------------------------------------------------------------------------

-- Lua 5.1 compatibility: table.pack was added in 5.2
if not table.pack then
   function table.pack(...)
      return {n = select("#", ...), ...}
   end
end
if not table.unpack then
   table.unpack = unpack
end

-- Ensure test temp directories exist (needed when real lsqlite3 is available)
os.execute("mkdir -p /tmp/test_plugins")
os.execute("mkdir -p /tmp/test_mushclient")

-- Track all API calls for inspection
mock = {
   calls = {},
   variables = {},
   gmcp_data = {},
   triggers = {},
   trigger_groups = {},
   aliases = {},
   timers = {},
   plugins = {},
   connected = true,
}

--- Reset all mock state (call between tests)
function mock.reset()
   mock.calls = {}
   mock.variables = {}
   mock.gmcp_data = {}
   mock.triggers = {}
   mock.trigger_groups = {}
   mock.aliases = {}
   mock.timers = {}
   mock.plugins = {}
   mock.connected = true
end

--- Reset DB state so each test file gets a fresh database
function mock.reset_db()
   if DB and DB._db then
      DB._db:close()
      DB._db = nil
   end
   if DB then DB._path = nil end
   -- Remove old test DB file
   os.remove("/tmp/test_plugins/Search_and_Destroy.db")
end

--- Set GMCP data for testing
function mock.set_gmcp(path, value)
   mock.gmcp_data[path] = value
end

--- Record a function call for later inspection
local function record_call(fn_name, ...)
   if not mock.calls[fn_name] then
      mock.calls[fn_name] = {}
   end
   mock.calls[fn_name][#mock.calls[fn_name] + 1] = {...}
end

------------------------------------------------------------------------
-- MUSHclient Global API Stubs
------------------------------------------------------------------------

function GetVariable(name)
   record_call("GetVariable", name)
   return mock.variables[name]
end

function SetVariable(name, value)
   record_call("SetVariable", name, value)
   mock.variables[name] = value
   return 0
end

function SaveState()
   record_call("SaveState")
end

function Note(text)
   record_call("Note", text)
end

function ColourNote(...)
   record_call("ColourNote", ...)
end

function ColourTell(...)
   record_call("ColourTell", ...)
end

function Tell(text)
   record_call("Tell", text)
end

function Send(text)
   record_call("Send", text)
end

function SendNoEcho(text)
   record_call("SendNoEcho", text)
end

function Execute(text)
   record_call("Execute", text)
end

function Simulate(text)
   record_call("Simulate", text)
end

function print(...)
   -- Real print for test output
   local args = {...}
   local parts = {}
   for _, v in ipairs(args) do
      parts[#parts + 1] = tostring(v)
   end
   io.write(table.concat(parts, "\t") .. "\n")
end

function GetPluginID()
   return "a11200000053264400000001"
end

function GetPluginInfo(id, info_type)
   record_call("GetPluginInfo", id, info_type)
   if info_type == 1 then return "Search_and_Destroy" end       -- name
   if info_type == 17 then return true end                       -- enabled
   if info_type == 19 then return "2.000" end                    -- version
   if info_type == 20 then return "/tmp/test_plugins/" end       -- plugin directory
   return nil
end

function IsPluginInstalled(id)
   record_call("IsPluginInstalled", id)
   return mock.plugins[id] or false
end

function CallPlugin(id, func_name, ...)
   record_call("CallPlugin", id, func_name, ...)
   -- Special handling for GMCP handler
   if id == "3e7dedbe37e44942dd46d264" then
      if func_name == "gmcpdata_as_string" then
         local path = select(1, ...)
         local data = mock.gmcp_data[path]
         if data then
            -- Serialize the data to a Lua-loadable string
            return 0, serialize_value(data)
         end
         return 0, "nil"
      elseif func_name == "Send_GMCP_Packet" then
         return 0
      end
   end
   -- Special handling for mapper
   if id == "b6eae87ccedd84f510b74714" then
      if func_name == "map_find_query" then
         return 0, ""
      end
   end
   return 0
end

function BroadcastPlugin(msg, data)
   record_call("BroadcastPlugin", msg, data)
end

function IsConnected()
   return mock.connected
end

function WorldName()
   return "aardwolf"
end

function GetInfo(info_type)
   record_call("GetInfo", info_type)
   if info_type == 60 then return "/tmp/test_mushclient/" end  -- MUSHclient directory
   if info_type == 66 then return "/tmp/test_data/" end        -- data directory
   return nil
end

function DoAfterSpecial(delay, code, sendto)
   record_call("DoAfterSpecial", delay, code, sendto)
end

function AddTriggerEx(name, match, response, flags, colour, wildcard, sound, script, sendto, sequence)
   record_call("AddTriggerEx", name, match, response, flags, colour, wildcard, sound, script, sendto, sequence)
   mock.triggers[name] = {
      match = match,
      script = script,
      enabled = true,
      group = "",
   }
   return 0
end

function DeleteTrigger(name)
   record_call("DeleteTrigger", name)
   mock.triggers[name] = nil
   return 0
end

function EnableTrigger(name, enabled)
   record_call("EnableTrigger", name, enabled)
   if mock.triggers[name] then
      mock.triggers[name].enabled = enabled
   end
   return 0
end

function EnableTriggerGroup(group, enabled)
   record_call("EnableTriggerGroup", group, enabled)
   mock.trigger_groups[group] = enabled
   for name, trg in pairs(mock.triggers) do
      if trg.group == group then
         trg.enabled = enabled
      end
   end
   return 0
end

function SetTriggerOption(name, option, value)
   record_call("SetTriggerOption", name, option, value)
   if mock.triggers[name] then
      if option == "group" then
         mock.triggers[name].group = value
      end
   end
   return 0
end

function AddAlias(name, match, response, flags, script)
   record_call("AddAlias", name, match, response, flags, script)
   mock.aliases[name] = {match = match, script = script, enabled = true}
   return 0
end

function EnableAlias(name, enabled)
   record_call("EnableAlias", name, enabled)
   if mock.aliases[name] then
      mock.aliases[name].enabled = enabled
   end
   return 0
end

function AddTimer(name, hours, minutes, seconds, response, flags, script)
   record_call("AddTimer", name, hours, minutes, seconds, response, flags, script)
   mock.timers[name] = {enabled = true}
   return 0
end

function EnableTimer(name, enabled)
   record_call("EnableTimer", name, enabled)
   if mock.timers[name] then
      mock.timers[name].enabled = enabled
   end
   return 0
end

function ResetTimer(name)
   record_call("ResetTimer", name)
   return 0
end

function WindowInfo(win, info_type)
   return 0
end

function WindowDelete(win)
   return 0
end

------------------------------------------------------------------------
-- Utility: Serialize a Lua value to a loadable string
------------------------------------------------------------------------
function serialize_value(val)
   local t = type(val)
   if t == "nil" then
      return "nil"
   elseif t == "boolean" then
      return tostring(val)
   elseif t == "number" then
      return tostring(val)
   elseif t == "string" then
      return string.format("%q", val)
   elseif t == "table" then
      local parts = {}
      -- Check if it's an array
      local is_array = true
      local max_i = 0
      for k, _ in pairs(val) do
         if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
            is_array = false
            break
         end
         if k > max_i then max_i = k end
      end
      if is_array and max_i == #val then
         for i = 1, #val do
            parts[#parts + 1] = serialize_value(val[i])
         end
      else
         for k, v in pairs(val) do
            local key_str
            if type(k) == "string" then
               if k:match("^[%a_][%w_]*$") then
                  key_str = k
               else
                  key_str = "[" .. string.format("%q", k) .. "]"
               end
            else
               key_str = "[" .. tostring(k) .. "]"
            end
            parts[#parts + 1] = key_str .. " = " .. serialize_value(v)
         end
      end
      return "{" .. table.concat(parts, ", ") .. "}"
   else
      return tostring(val)
   end
end

------------------------------------------------------------------------
-- Sendto constants (from MUSHclient)
------------------------------------------------------------------------
sendto = {
   world = 0,
   command = 1,
   output = 2,
   status = 3,
   notepad = 4,
   notepadappend = 5,
   logfile = 6,
   notepadreplace = 7,
   worldimmediate = 8,
   worlddeferred = 9,
   variable = 10,
   execute = 11,
   script = 12,
   immediate = 13,
   speedwalk = 14,
}

------------------------------------------------------------------------
-- Miniwin constants (from MUSHclient)
------------------------------------------------------------------------
miniwin = {
   pos_center = 0,
   create_absolute_location = 0,
}

------------------------------------------------------------------------
-- Trigger flag constants
------------------------------------------------------------------------
trigger_flag = {
   Enabled = 1,
   OmitFromLog = 2,
   OmitFromOutput = 4,
   KeepEvaluating = 8,
   IgnoreCase = 16,
   RegularExpression = 32,
   ExpandVariables = 512,
   Replace = 1024,
   Temporary = 16384,
   OneShot = 32768,
}

-- Make sure json is available (try to load from multiple locations)
local json_ok, json_mod = pcall(require, "json")
if not json_ok then
   -- Minimal JSON stub for testing
   json = {}
   function json.encode(val)
      return serialize_value(val)
   end
   function json.decode(str)
      local fn = loadstring("return " .. str)
      if fn then return fn() end
      return nil
   end
else
   json = json_mod
end

-- SQLite3 stub (for tests that don't need real DB)
local sqlite3_ok, sqlite3_mod = pcall(require, "lsqlite3")
if sqlite3_ok then
   sqlite3 = sqlite3_mod
else
   -- Try alternate name
   local ok2, mod2 = pcall(require, "lsqlite3complete")
   if ok2 then
      sqlite3 = mod2
   else
      -- Minimal stub
      sqlite3 = {
         open = function(path)
            return {
               execute = function() return 0 end,
               nrows = function() return function() return nil end end,
               errmsg = function() return "" end,
               close = function() end,
               close_vm = function() end,
            }
         end,
      }
   end
end

return mock
