-- Support program to run programs under the debugger without modification
-- Usage: mincon example.lua
local args = {...}
local filePath = table.remove(args, 1)

if not fs.exists(filePath) then error("File does not exist", 0) end

local file = fs.open(filePath, "r")
local fileData = file.readAll()
file.close()

local debugger = require("/mindbg/mindbg")
debugger.setWhitelisted({filePath})

local fileLoaded, err = load(fileData, "@" .. filePath, "t", _ENV)

debugger.runDebugger(fileLoaded, args or {})
