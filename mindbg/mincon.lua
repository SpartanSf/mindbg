-- Support program to run programs under the debugger without modification
-- Usage: mincon example.lua
local filePath = ...

local file = fs.open(filePath, "r")
local fileData = file.readAll()
file.close()

local debugger = require("/mindbg/mindbg")
debugger.setWhitelisted({filePath})

local fileLoaded, err = load(fileData, "@" .. filePath, "t", _ENV)

debugger.runDebugger(fileLoaded)
