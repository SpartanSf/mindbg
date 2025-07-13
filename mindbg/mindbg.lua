local pretty = require "cc.pretty"

local term = term
local w, h = term.getSize()

local left_width = math.floor(w / 2)
local divider_x = left_width + 1
local right_width = w - left_width - 1

local prog_win = window.create(term.current(), 1, 1, left_width, h, true)
local divider_win = window.create(term.current(), divider_x, 1, 1, h, true)
local dbg_win = window.create(term.current(), divider_x + 1, 1, right_width, h, true)

prog_win.clear()
dbg_win.clear()
divider_win.clear()
prog_win.setCursorPos(1, 1)
dbg_win.setCursorPos(1, 1)

for y = 1, h do
    divider_win.setCursorPos(1, y)
    divider_win.write(string.char(0x95))
end

local orig_term = term.current()

local function dbg_print(...)
    term.redirect(dbg_win)
	print(...)
	term.redirect(prog_win)
end

local source_cache = {}
local break_mode = "step"
local current_line = nil
local last_info = nil
local target_line = nil

local function get_source_line(file, line)
    if not source_cache[file] then
        if not fs.exists(file) then
            source_cache[file] = {}
            return nil
        end
        local lines = {}
        for l in io.lines(file) do table.insert(lines, l) end
        source_cache[file] = lines
    end
    return source_cache[file][line]
end

local function debugger(info, line, level)
    level = level or 3
    local src = info.short_src
    local file_line = get_source_line(src, line) or "<unavailable>"
    dbg_print(("[DEBUG] %s:%d: %s"):format(src, line, file_line))

    while true do
        dbg_win.write("(debug) > ")
        dbg_win.setCursorBlink(true)
        term.redirect(dbg_win)
        local cmd = read()
        dbg_win.setCursorBlink(false)
        term.redirect(prog_win)

        if cmd == "step" or cmd == "s" then
            break_mode = "step"
            break
        elseif cmd == "continue" or cmd == "c" then
            break_mode = "continue"
            break
        elseif cmd:match("^until%s+%d+") or cmd:match("^u%s+%d+") then
            local lnum = tonumber(cmd:match("%d+"))
            if lnum then
                break_mode = "until"
                target_line = lnum
                break
            else
                dbg_print("Invalid line number.")
            end
        elseif cmd:match("^print%s+") then
            local expr = cmd:match("^print%s+(.+)")
            local env = {}
            local i = 1
            while true do
                local n, v = debug.getlocal(level, i)
                if not n then break end
                env[n] = v
                i = i + 1
            end
            setmetatable(env, { __index = _G })
            local chunk, err = load("return " .. expr, "=(debug)", "t", env)
            if not chunk then
                dbg_print("Compile error: " .. err)
            else
                local ok, result = pcall(chunk)
                if ok then
					term.redirect(dbg_win)
					term.write("= ")
					pretty.pretty_print(result)
					term.redirect(prog_win)
                else
                    dbg_print("Runtime error: " .. result)
                end
            end
        elseif cmd == "bt" then
            local lvl = level
            while true do
                local i = debug.getinfo(lvl, "nSl")
                if not i then break end
                dbg_print(("#%d %s (%s:%d)"):format(lvl - level, i.name or "<anon>", i.short_src, i.currentline))
                lvl = lvl + 1
            end
        elseif cmd:match("^set%s+") then
            local var_expr = cmd:match("^set%s+(.+)")
            local var_name, var_value = var_expr:match("^([%w_]+)%s*=%s*(.+)$")
            
            if not var_name or not var_value then
                dbg_print("Usage: set <varname> = <value>")
            else
                local found = false
                local i = 1
                while true do
                    local name, value = debug.getlocal(level, i)
                    if not name then break end
                    if name == var_name then
                        local chunk, err = load("return "..var_value, "=(set)", "t", _ENV)
                        if not chunk then
                            dbg_print("Error in value expression: "..err)
                        else
                            local ok, new_value = pcall(chunk)
                            if ok then
                                debug.setlocal(level, i, new_value)
								term.redirect(dbg_win)
								term.write(("Set local %s = "):format(var_name))
								pretty.pretty_print(new_value)
								term.redirect(prog_win)
                                found = true
                                break
                            else
                                dbg_print("Error evaluating value: "..new_value)
                            end
                        end
                    end
                    i = i + 1
                end
                
                if not found then
                    local func = debug.getinfo(level, "f").func
                    local j = 1
                    while true do
                        local name, value = debug.getupvalue(func, j)
                        if not name then break end
                        if name == var_name then
                            local chunk, err = load("return "..var_value, "=(set)", "t", _ENV)
                            if not chunk then
                                dbg_print("Error in value expression: "..err)
                            else
                                local ok, new_value = pcall(chunk)
                                if ok then
                                    debug.setupvalue(func, j, new_value)
									term.redirect(dbg_win)
                                    term.write(("Set upvalue %s = "):format(var_name))
									pretty.pretty_print(new_value)
									term.redirect(prog_win)
                                    found = true
                                    break
                                else
                                    dbg_print("Error evaluating value: "..new_value)
                                end
                            end
                        end
                        j = j + 1
                    end
                end
                
                if not found then
                    local chunk, err = load("return "..var_value, "=(set)", "t", _ENV)
                    if not chunk then
                        dbg_print("Error in value expression: "..err)
                    else
                        local ok, new_value = pcall(chunk)
                        if ok then
                            _G[var_name] = new_value
							term.redirect(dbg_win)
							term.write(("Set global %s = "):format(var_name))
							pretty.pretty_print(new_value)
							term.redirect(prog_win)
                        else
                            dbg_print("Error evaluating value: "..new_value)
                        end
                    end
                end
            end
        elseif cmd == "info" then
            if last_info then
                dbg_print("Function Info:")
                dbg_print("  Name:        " .. (last_info.name or "<anonymous>"))
                dbg_print("  Source:      " .. last_info.short_src)
                dbg_print("  Line defined:" .. last_info.linedefined)
                dbg_print("  Last line:   " .. last_info.lastlinedefined)
                dbg_print("  Current line:" .. last_info.currentline)
                dbg_print("  What:        " .. last_info.what)
                dbg_print("  Args/Locals:")
                local i = 1
                while true do
                    local name, value = debug.getlocal(level, i)
                    if not name then break end
                    dbg_print(("    [%d] %s = %s"):format(i, name, tostring(value)))
                    i = i + 1
                end
                local funcinfo = debug.getinfo(level, "f")
                if funcinfo and funcinfo.func then
                    local j = 1
                    dbg_print("  Upvalues:")
                    while true do
                        local name, val = debug.getupvalue(funcinfo.func, j)
                        if not name then break end
                        dbg_print(("    [%d] %s = %s"):format(j, name, tostring(val)))
                        j = j + 1
                    end
                end
            else
                dbg_print("No function info available yet.")
            end
        elseif cmd == "help" then
            dbg_print("Commands:")
            dbg_print("  step/s              - Step to next line")
            dbg_print("  continue/c          - Run until halt or end")
            dbg_print("  until/u <n>         - Run until line n")
            dbg_print("  print <expr>        - Evaluate expression")
            dbg_print("  set <var> = <value> - Set variable value")
            dbg_print("  bt                  - Backtrace stack")
            dbg_print("  info                - Show function info and locals")
            dbg_print("  exit                - Quit debugger")
        else
            dbg_print("Unknown command. Type 'help'.")
        end
    end
end

local function is_ROM(file)
    local f = fs.open(file, "r")
    if not f then return true end
    local content = f.readAll()
    f.close()
    local w = fs.open(file, "w")
    if not w then return true end
    w.close()
    f = fs.open(file, "w")
    if f then
        f.write(content)
        f.close()
    end
    return false
end

debug.sethook(function(event, line)
    if event == "line" then
        local info = debug.getinfo(2, "nSl")
        last_info = info
        current_line = line
        local src = info.short_src
        local file_line = get_source_line(src, line) or "<unavailable>"
        local filename = info.short_src:gsub("^@", "")
        if filename == "/mindbg/mindbg.lua" then return end

        if break_mode == "step" and not is_ROM(filename) then
            debugger(info, line, 3)
        elseif break_mode == "until" and line == target_line and not is_ROM(filename) then
            debugger(info, line, 3)
            break_mode = "step"
            target_line = nil
        elseif break_mode == "continue" and not is_ROM(filename) then
            if file_line:match("^__MINDBG_HALT()") then
                debugger(info, line, 3)
                break_mode = "step"
            end
        end
    end
end, "l")

local function run_debugger(fn)
    term.redirect(prog_win)
    fn()
    term.redirect(orig_term)
end

return run_debugger
