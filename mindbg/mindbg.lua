local pretty = require "cc.pretty"
local term = term
local w, h = term.getSize()

local left_width = math.floor(w / 2)
local divider_x = left_width + 1
local right_width = w - left_width - 1
local dbg_height = math.floor(h * 3/4)
local code_height = h - dbg_height - 1  

local prog_win = window.create(term.current(), 1, 1, left_width, h, true)
local divider_win = window.create(term.current(), divider_x, 1, 1, h, true)
local dbg_win = window.create(term.current(), divider_x + 1, 1, right_width, dbg_height, true)
local code_divider_win = window.create(term.current(), divider_x + 1, dbg_height + 1, right_width, 1, true)
local code_win = window.create(term.current(), divider_x + 1, dbg_height + 2, right_width, code_height, true)

prog_win.clear()
dbg_win.clear()
divider_win.clear()
code_divider_win.clear()
code_win.clear()
prog_win.setCursorPos(1, 1)
dbg_win.setCursorPos(1, 1)
code_win.setCursorPos(1, 1)

code_win.setBackgroundColor(colors.black)
code_win.setTextColor(colors.white)

for y = 1, h do
	divider_win.setCursorPos(1, y)
	if y ~= dbg_height + 1 then
		divider_win.write(string.char(0x95))
	else
		divider_win.write(string.char(0x9D))
	end
end

for x = 1, right_width do
    code_divider_win.setCursorPos(x, 1)
    code_divider_win.write(string.char(0x8C))
end

local orig_term = term.current()
local source_cache = {}
local break_mode = "step"
local current_line = nil
local last_info = nil
local target_line = nil

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

local function get_source_line(file, line)
    if not source_cache[file] then
        local clean_file = file:gsub("^@", "")
        if not fs.exists(clean_file) then
            source_cache[file] = {}
            return nil
        end

        local lines = {}
        local f = fs.open(clean_file, "r")
        while true do
            local line = f.readLine()
            if not line then break end
            table.insert(lines, line)
        end
        f.close()
        source_cache[file] = lines
    end
    return source_cache[file][line]
end

local function update_code_view(file, current_line)
    if not file or not current_line then return end

    local lines = source_cache[file]
    if not lines then
        get_source_line(file, current_line)  
        lines = source_cache[file] or {}
    end

    local _, win_height = code_win.getSize()
    local total_lines = #lines

    local start_line = math.max(1, current_line - math.floor(win_height/2))
    local end_line = math.min(total_lines, start_line + win_height - 1)

    if end_line - start_line < win_height - 1 then
        start_line = math.max(1, end_line - win_height + 1)
    end

    code_win.clear()
    code_win.setCursorPos(1, 1)

    for i = start_line, end_line do
        if i == current_line then
            code_win.setTextColor(colors.yellow)
            code_win.write("> " .. lines[i])
        else
            code_win.setTextColor(colors.white)
            code_win.write("  " .. lines[i])
        end

        if i < end_line then
            local x, y = code_win.getCursorPos()
            code_win.setCursorPos(1, y + 1)
        end
    end
end

local function dbg_print(...)
    term.redirect(dbg_win)
    print(...)
    term.redirect(prog_win)
end

local whitelisted = {}

local function setWhitelisted(whitelist)
	whitelisted = whitelist
end

local function debugger(info, line, level)
    level = level or 3
    local src = info.short_src
    local file_line = get_source_line(src, line) or "<source unavailable>"

    update_code_view(src, line)
    dbg_print(("DEBUG %s:%d"):format(src, line))
    dbg_print(file_line)

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
                dbg_print("Invalid line number")
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
            local var, expr = cmd:match("^set%s+([%w_]+)%s*=%s*(.+)")
            if not var or not expr then
                dbg_print("Usage: set <var> = <expr>")
            else
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
                        local found = false

                        for i = 1, math.huge do
                            local name = debug.getlocal(level, i)
                            if not name then break end
                            if name == var then
                                debug.setlocal(level, i, result)
                                dbg_print(("Set local %s = %s"):format(var, tostring(result)))
                                found = true
                                break
                            end
                        end

                        if not found then
                            local funcinfo = debug.getinfo(level, "f")
                            if funcinfo and funcinfo.func then
                                for i = 1, math.huge do
                                    local name = debug.getupvalue(funcinfo.func, i)
                                    if not name then break end
                                    if name == var then
                                        debug.setupvalue(funcinfo.func, i, result)
                                        dbg_print(("Set upvalue %s = %s"):format(var, tostring(result)))
                                        found = true
                                        break
                                    end
                                end
                            end
                        end

                        if not found then
                            _G[var] = result
                            dbg_print(("Set global %s = %s"):format(var, tostring(result)))
                        end
                    else
                        dbg_print("Runtime error: " .. result)
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
                    local name, value = debug.getlocal(3, i)
                    if not name then break end
					
                    dbg_print(("    [%d] %s = %s"):format(i, name, tostring(value)))

                    i = i + 1
                end

                local funcinfo = debug.getinfo(3, "f")

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
            dbg_print("  continue/c          - Run until breakpoint")
            dbg_print("  until/u <n>         - Run until line number")
            dbg_print("  print <expr>        - Evaluate expression")
            dbg_print("  set <var> = <value> - Set variable")
            dbg_print("  bt                  - Show backtrace")
            dbg_print("  info                - Show current context")
            dbg_print("  exit                - Quit debugger")
        elseif cmd == "view" then
            update_code_view(src, line)
        else
            dbg_print("Unknown command. Type 'help'")
        end
    end
end

debug.sethook(function(event, line)
    if event == "line" then
        local info = debug.getinfo(2, "nSl")
        if not info then return end

        last_info = info
        current_line = line
        local src = info.short_src
        local filename = src:gsub("^@", "")
        local file_line = get_source_line(src, line) or ""

        if filename:match("mindbg") then return end
        if is_ROM(filename) then
			local stillReturn = true
			for _,v in ipairs(whitelisted) do
				if fs.combine(v) == fs.combine(filename) then
					stillReturn = false
					break
				end
			end
			
			if stillReturn then return end
		end

        if break_mode == "step" then
            update_code_view(src, line)
            debugger(info, line, 3)
        elseif break_mode == "until" and line == target_line then
            update_code_view(src, line)
            debugger(info, line, 3)
            break_mode = "step"
            target_line = nil
        elseif break_mode == "continue" then
            if file_line:match("__MINDBG_HALT") then
                update_code_view(src, line)
                debugger(info, line, 3)
                break_mode = "step"
            end
        end
    end
end, "l")

local function run_debugger(fn)
    term.redirect(prog_win)
    local ok, err = pcall(fn)
    term.redirect(orig_term)

    if not ok then
        term.redirect(dbg_win)
        print("Program crashed: " .. err)
        term.redirect(orig_term)
    end

    return ok, err
end

return {
	runDebugger = run_debugger,
	setWhitelisted = setWhitelisted
}
