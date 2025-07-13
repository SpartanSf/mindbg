-- Support program to run programs under the debugger without modification
-- Usage: mincon example.lua
local filePath = ...

local file = fs.open(filePath, "r")
local fileData = file.readAll()
file.close()

local debugger = require("/mindbg/mindbg")

local fileLoaded, err = load(fileData, "@" .. filePath)

debugger(fileLoaded)
