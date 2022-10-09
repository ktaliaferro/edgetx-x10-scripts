local toolName = "TNS|_Log Viewer v1.2|TNE"

---- #########################################################################
---- #                                                                       #
---- # License GPLv3: https://www.gnu.org/licenses/gpl-3.0.html              #
---- #                                                                       #
---- # This program is free software; you can redistribute it and/or modify  #
---- # it under the terms of the GNU General Public License version 2 as     #
---- # published by the Free Software Foundation.                            #
---- #                                                                       #
---- # This program is distributed in the hope that it will be useful        #
---- # but WITHOUT ANY WARRANTY; without even the implied warranty of        #
---- # MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         #
---- # GNU General Public License for more details.                          #
---- #                                                                       #
---- #########################################################################

-- This script display a log file as a graph
-- Original Author: Herman Kruisman (RealTadango) (original version: https://raw.githubusercontent.com/RealTadango/FrSky/master/OpenTX/LView/LView.lua)
-- Current Author: Offer Shmuely
-- Date: 2022
-- ver: 1.2

local m_log = {}
local m_log_parser = {}
local m_utils =  {}
local m_tables =  {}
local m_index_file = {}

--function cache
local math_floor = math.floor
--local math_fmod = math.fmod
local string_gmatch = string.gmatch
--local string_gsub = string.gsub
--local string_len = string.len

local heap = 2048
local hFile
local min_log_sec_to_show = 60

local log_file_list_raw = {}
local log_file_list_raw_idx = -1
local log_file_list = {}

local log_file_list_filtered = {}
local filter_model_name
local filter_date
local model_name_list = { "-- all --" }
local date_list = { "-- all --" }
local accuracy_list = { "1/1 (read every line)", "1/2 (every 2nd line)", "1/5 (every 5th line)", "1/10 (every 10th line)" }
local ddLogFile = nil -- log-file dropDown object

local filename
local filename_idx = 1

local columns = {}
local current_session = nil
local FIRST_VALID_COL = 2

-- state machine
local STATE = {
    INIT = 0,
    SELECT_FILE_INIT = 1,
    SELECT_FILE = 2,

    SELECT_SENSORS_INIT = 3,
    SELECT_SENSORS = 4,

    READ_FILE_DATA = 5,
    PARSE_DATA = 6,

    SHOW_GRAPH = 7
}

local state = STATE.INIT
--Graph data
local _values = {}
local _points = {}
local conversionSensorId = 0
local conversionSensorProgress = 0

--File reading data
local valPos = 0
local skipLines = 0
local lines = 0
local index = 0
local buffer = ""
--local prevTotalSeconds = 0

--Option data
--local maxLines
local current_option = 1

local sensorSelection = {
    { y = 80, label = "Field 1", values = {}, value = 2, min = 0 },
    { y = 105, label = "Field 2", values = {}, value = 3, min = 0 },
    { y = 130, label = "Field 3", values = {}, value = 4, min = 0 },
    { y = 155, label = "Field 4", values = {}, value = 1, min = 0 }
}

local graphConfig = {
    --x_start = 60,
    x_start = 0,
    --x_end = 420,
    x_end = LCD_W,
    y_start = 40,
    y_end = 240,
    { color = BLUE, valx = 80, valy = 249, minx = 5, miny = 220, maxx = 5, maxy = 30 },
    { color = GREEN, valx = 170, valy = 249, minx = 5, miny = 205, maxx = 5, maxy = 45 },
    { color = RED, valx = 265, valy = 249, minx = 5, miny = 190, maxx = 5, maxy = 60 },
    { color = WHITE, valx = 380, valy = 249, minx = 5, miny = 175, maxx = 5, maxy = 75 }
}

local xStep = (graphConfig.x_end - graphConfig.x_start) / 100

local cursor = 0

local GRAPH_MODE = {
    CURSOR = 0,
    ZOOM = 1,
    SCROLL = 2,
    GRAPH_MINMAX = 3
}
local graphMode = GRAPH_MODE.CURSOR
local graphStart = 0
local graphSize = 0
local graphTimeBase = 0
local graphMinMaxIndex = 0

local img1 = Bitmap.open("/SCRIPTS/TOOLS/LogViewer/bg1.png")
local img2 = Bitmap.open("/SCRIPTS/TOOLS/LogViewer/bg2.png")

--------------------------------------------------------------
-- Return GUI library table
local libGUI
local function loadGUI()
    if not libGUI then
        -- Loadable code chunk is called immediately and returns libGUI
        libGUI = loadScript("/SCRIPTS/TOOLS/LogViewer/libgui.lua")
    end
    return libGUI()
end
local libGUI = loadGUI()

-- Instantiate a new GUI object
local ctx1 = nil
local ctx2 = nil



---- #########################################################################
---- ###########  m_log              #########################################
--region m_log
--local m_log = {}
m_log.log = {
    outfile = "/SCRIPTS/TOOLS/LogViewer/app.log",
    enable_file = false,
    level = "info",

    -- func
    trace = nil,
    debug = nil,
    info = nil,
    warn = nil,
    error = nil,
    fatal = nil,
}

m_log.levels = {
    trace = 1,
    debug = 2,
    info = 3,
    warn = 4,
    error = 5,
    fatal = 6
}

m_log.round = function(x, increment)
    increment = increment or 1
    x = x / increment
    return (x > 0 and math.floor(x + .5) or math.ceil(x - .5)) * increment
end

m_log._tostring = m_log.tostring

m_log.tostring = function(...)
    local t = {}
    for i = 1, select('#', ...) do
        local x = select(i, ...)
        if type(x) == "number" then
            x = m_log.round(x, .01)
        end
        t[#t + 1] = m_log._tostring(x)
    end
    return table.concat(t, " ")
end

m_log.do_log = function(i, ulevel, fmt, ...)
     --below the log level
    if i < m_log.levels[m_log.log.level] then
        return
    end

    local num_arg = #{...}
    local msg
    if num_arg > 0 then
        msg = string.format(fmt, ...)
    else
        msg = fmt
    end
    --print(msg)

    --local info = debug.getinfo(2, "Sl")
    --local lineinfo = info.short_src .. ":" .. info.currentline
    local lineinfo = "f.lua:0"

    local msg2 = string.format("[%-4s] %s: %s", ulevel, lineinfo, msg)

    -- output to console
    print(msg2)

    -- Output to log file
    if m_log.log.enable_file == true and m_log.log.outfile then
        local fp = io.open(m_log.log.outfile, "a")
        io.write(fp, msg2 .. "\n")
        io.close(fp)
    end
end

m_log.trace = function(fmt, ...)
    m_log.do_log(m_log.levels.trace, "TRACE", fmt, ...)
end
m_log.debug = function(fmt, ...)
    m_log.do_log(m_log.levels.debug, "DEBUG", fmt, ...)
end
m_log.info = function(fmt, ...)
    --print(fmt)
    m_log.do_log(m_log.levels.info, "INFO", fmt, ...)
end
m_log.warn = function(fmt, ...)
    m_log.do_log(m_log.levels.warn, "WARN", fmt, ...)
end
m_log.error = function(fmt, ...)
    m_log.do_log(m_log.levels.error, "ERROR", fmt, ...)
end
m_log.fatal = function(fmt, ...)
    m_log.do_log(m_log.levels.fatal, "FATAL",fmt, ...)
end

--endregion


---- #########################################################################
---- ###########  m_utils              #########################################
--region m_utils

--local m_utils = {}
function m_utils.split(text)
    local cnt = 0
    local result = {}
    for val in string.gmatch(string.gsub(text, ",,", ", ,"), "([^,]+),?") do
        cnt = cnt + 1
        result[cnt] = val
    end
    --m_log.info("split: #col: %d (%s)", cnt, text)
    --m_log.info("split: #col: %d (1-%s, 2-%s)", cnt, result[1], result[2])
    return result, cnt
end

function m_utils.split_pipe(text)
    -- m_log.info("split_pipe(%s)", text)
    local cnt = 0
    local result = {}
    for val in string.gmatch(string.gsub(text, "||", "| |"), "([^|]+)|?") do
        cnt = cnt + 1
        result[cnt] = val
    end
    m_log.info("split_pipe: #col: %d (%s)", cnt, text)
    m_log.info("split_pipe: #col: %d (1-%s, 2-%s)", cnt, result[1], result[2])
    return result, cnt
end

-- remove trailing and leading whitespace from string.
-- http://en.wikipedia.org/wiki/Trim_(programming)
function m_utils.trim(s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
    --string.gsub(text, ",,", ", ,")
end

function m_utils.trim_safe(s)
    if s == nil then
        return ""
    end
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
    --string.gsub(text, ",,", ", ,")
end

--endregion


---- #########################################################################
---- ###########  m_tables           #########################################
--region m_tables

--local m_tables =  {}

function m_tables.tprint(t, s)
    for k, v in pairs(t) do
        local kfmt = '["' .. tostring(k) .. '"]'
        if type(k) ~= 'string' then
            kfmt = '[' .. k .. ']'
        end
        local vfmt = '"' .. tostring(v) .. '"'
        if type(v) == 'table' then
            m_tables.tprint(v, (s or '') .. kfmt)
        else
            if type(v) ~= 'string' then
                vfmt = tostring(v)
            end
            print(type(t) .. (s or '') .. kfmt .. ' = ' .. vfmt)
        end
    end
end

function m_tables.table_clear(tbl)
    -- clean without creating a new list
    for i = 0, #tbl do
        table.remove(tbl, 1)
    end
end

function m_tables.table_print(prefix, tbl)
    m_log.info("-------------")
    m_log.info("table_print(%s)", prefix)
    for i = 1, #tbl, 1 do
        local val = tbl[i]
        if type(val) ~= "table" then
            m_log.info(string.format("%d. %s: %s", i, prefix, val))
        else
            local t_val = val
            m_log.info2("-++++------------ %d %s", #val, type(t_val))
            for j = 1, #t_val, 1 do
                local val = t_val[j]
                m_log.info(string.format("%d. %s: %s", i, prefix, val))
            end
        end
    end
    m_log.info("------------- table_print end")
end

--endregion


---- #########################################################################
---- ###########  log_parser         #########################################
--region m_log_parser

--local m_log_parser = {}

m_log_parser.getTotalSeconds = function(time)
    local total = tonumber(string.sub(time, 1, 2)) * 3600
    total = total + tonumber(string.sub(time, 4, 5)) * 60
    total = total + tonumber(string.sub(time, 7, 8))
    return total
end

m_log_parser.getFileDataInfo = function(fileName)

    local hFile = io.open("/LOGS/" .. fileName, "r")
    if hFile == nil then
        return nil, nil, nil, nil, nil
    end

    local buffer = ""
    local start_time
    local end_time
    local total_lines = 0
    local start_index
    local col_with_data_str = ""

    local columns_by_header = {}
    local columns_is_have_data = {}
    local columns_with_data = {}

    -- read Header
    local data1 = io.read(hFile, 2048)
    local index = string.find(data1, "\n")
    if index == nil then
        m_log.info("Header could not be found, file: %s", fileName)
        return nil, nil, nil, nil, nil, nil
    end

    -- get header line
    local headerLine = string.sub(data1, 1, index)
    m_log.info("header-line: [%s]", headerLine)

    -- get columns
    columns_by_header = m_utils.split(headerLine)

    start_index = index
    io.seek(hFile, index)

    -- stop after 2M (1000x2028)
    local sample_col_data = nil
    for i = 1, 1000 do
        local data2 = io.read(hFile, 2048)

        -- file read done
        if data2 == "" then
            -- done reading file
            io.close(hFile)

            -- calculate data
            local first_time_sec = m_log_parser.getTotalSeconds(start_time)
            local last_time_sec = m_log_parser.getTotalSeconds(end_time)
            local total_seconds = last_time_sec - first_time_sec
            m_log.info("parser:getFileDataInfo: done - [%s] lines: %d, duration: %dsec", fileName, total_lines, total_seconds)

            --for idxCol = 1, #columns_by_header do
            --    local col_name = columns_by_header[idxCol]
            --    m_log.info("getFileDataInfo %s: %s", col_name, columns_is_have_data[idxCol])
            --end

            for idxCol = 1, #columns_by_header do
                local col_name = columns_by_header[idxCol]
                col_name = string.gsub(col_name, "\n", "")
                if columns_is_have_data[idxCol] == true and col_name ~= "Date" and col_name ~= "Time" then
                    columns_with_data[#columns_with_data+1] = col_name
                    if string.len(col_with_data_str) == 0 then
                        col_with_data_str = col_name
                    else
                        col_with_data_str = col_with_data_str .. "|" .. col_name
                    end
                end
            end

            m_log.info("parser:getFileDataInfo: done - col_with_data_str: %s", col_with_data_str)
            --for idxCol = 1, #columns_with_data do
            --    m_log.info("getFileDataInfo@ %d: %s", idxCol, columns_with_data[idxCol])
            --end

            return start_time, end_time, total_seconds, total_lines, start_index, col_with_data_str
        end

        buffer = buffer .. data2
        local idx_buff = 0

        for line in string_gmatch(buffer, "([^\n]+)\n") do
            total_lines = total_lines + 1
            --m_log.info("getFileDataInfo: %d. line: %s", total_lines, line)
            --m_log.info("getFileDataInfo2: line: %d", total_lines)
            local time = string.sub(line, 12, 19)
            --m_log.info("getFileDataInfo: %d. time: %s", total_lines, time)
            if start_time == nil then
                start_time = time
            end
            end_time = time

            -- find columns with data
            local vals = m_utils.split(line)
            if sample_col_data == nil then
                sample_col_data = vals
                for idxCol = 1, #columns_by_header, 1 do
                    columns_is_have_data[idxCol] = false
                end
            end

            for idxCol = 1, #columns_by_header, 1 do
                if vals[idxCol] ~= sample_col_data[idxCol] then
                    columns_is_have_data[idxCol] = true
                end
            end

            --local buf1 = ""
            --for idxCol = 1, #columns_by_header do
            --    buf1 = buf1 .. string.format("%s: %s\n", columns_by_header[idxCol], columns_with_data[idxCol])
            --end
            --m_log.info("getFileDataInfo %s", buf1)

            idx_buff = idx_buff + string.len(line) + 1 -- dont forget the newline
        end

        buffer = string.sub(buffer, idx_buff + 1) -- dont forget the newline
    end

    io.close(hFile)
    --local first_time_sec = getTotalSeconds(start_time)
    --local last_time_sec = getTotalSeconds(end_time)
    --local total_seconds = last_time_sec - first_time_sec
    --m_log.info("getFileDataInfo: [%s] early exit! lines: %d, duration: %dsec", fileName, total_lines, total_seconds)
    --return total_lines, total_seconds, col_with_data_str, start_time, end_time -- startIndex, endIndex

    m_log.info("error: file too long, %s", fileName)
    return nil, nil, nil, nil, nil, nil
end

--endregion


---- #########################################################################
---- ###########  index file         #########################################
--region m_index_file

--local m_index_file = {}
m_index_file.idx_file_name = "/LOGS/log-viewer.csv"
--m_index_fileidx_file_name = "/SCRIPTS/TOOLS/LogViewer/log-viewer.csv"
m_index_file.log_files_index_info = {}


m_index_file.indexInit = function ()
    m_tables.table_clear(m_index_file.log_files_index_info)
    --log_files_index_info = {}
end

m_index_file.updateFile = function(file_name, start_time, end_time, total_seconds, total_lines, start_index, col_with_data_str)
    m_log.info("updateFile(%s)", file_name)

    m_index_file.log_files_index_info[#m_index_file.log_files_index_info + 1] = {
        file_name = m_utils.trim(file_name),
        start_time = m_utils.trim(start_time),
        end_time = m_utils.trim(end_time),
        total_seconds = tonumber(m_utils.trim(total_seconds)),
        total_lines = tonumber(m_utils.trim(total_lines)),
        start_index = tonumber(m_utils.trim(start_index)),
        col_with_data_str = m_utils.trim(col_with_data_str)
    }
    --m_log.info("22222222222: %d - %s", #log_files_index_info, file_name)
end

m_index_file.show = function(prefix)
    local tbl = m_index_file.log_files_index_info
    m_log.info("-------------show start (%s)", prefix)
    for i = 1, #tbl, 1 do
        local f_info = tbl[i]
        local s = string.format("%d. file_name:%s, start_time: %s, end_time: %s, total_seconds: %s, total_lines: %s, start_index: %s, col_with_data_str: [%s]", i,
            f_info.file_name,
            f_info.start_time,
            f_info.end_time,
            f_info.total_seconds,
            f_info.total_lines,
            f_info.start_index,
            f_info.col_with_data_str
        )

        m_log.info(s)
    end
    m_log.info("------------- show end")
end

m_index_file.indexRead = function()
    m_log.info("indexRead()")
    m_tables.table_clear(m_index_file.log_files_index_info)
    local hFile = io.open(m_index_file.idx_file_name, "r")
    if hFile == nil then
        return
    end

    -- read Header
    local data1 = io.read(hFile, 2048)
    local index = string.find(data1, "\n")
    if index == nil then
        m_log.info("Index header could not be found, file: %s", m_index_file.idx_file_name)
        return
    end

    -- get header line
    local headerLine = string.sub(data1, 1, index)
    m_log.info("indexRead: header: %s", headerLine)

    io.seek(hFile, index)
    local data2 = io.read(hFile, 2048 * 32)

    --m_index_file.show("indexRead-should-be-empty")
    for line in string.gmatch(data2, "([^\n]+)\n") do

        if string.sub(line,1,1) ~= "#" then
            m_log.info("indexRead: index-line: %s", line)
            local values = m_utils.split(line)

            local file_name = m_utils.trim(values[1])
            local start_time = m_utils.trim(values[2])
            local end_time = m_utils.trim(values[3])
            local total_seconds = m_utils.trim(values[4])
            local total_lines = m_utils.trim(values[5])
            local start_index = m_utils.trim(values[6])
            local col_with_data_str = m_utils.trim_safe(values[7])
            --m_log.info(string.format("indexRead: got: file_name: %s, start_time: %s, end_time: %s, total_seconds: %s, total_lines: %s, start_index: %s, col_with_data_str: %s", file_name, start_time, end_time, total_seconds, total_lines, start_index, col_with_data_str))
            m_index_file.updateFile(file_name, start_time, end_time, total_seconds, total_lines, start_index, col_with_data_str)
        end
    end

    io.close(hFile)
    m_index_file.show("indexRead-should-with-data")
end

m_index_file.getFileDataInfo = function(file_name)
    m_log.info("getFileDataInfo(%s)", file_name)
    --m_index_file.show("getFileDataInfo-start")

    for i = 1, #m_index_file.log_files_index_info do
        local f_info = m_index_file.log_files_index_info[i]
        --m_log.info("getFileDataInfo: %s ?= %s", file_name, f_info.file_name)
        if file_name == f_info.file_name then
            m_log.info("getFileDataInfo: info from cache %s", file_name)
            return false, f_info.start_time, f_info.end_time, f_info.total_seconds, f_info.total_lines, f_info.start_index, f_info.col_with_data_str
        end
    end

    m_log.info("getFileDataInfo: file not in index, indexing... %s", file_name)
    --m_index_file..show("getFileDataInfo-2")

    local start_time, end_time, total_seconds, total_lines, start_index, col_with_data_str = m_log_parser.getFileDataInfo(file_name)

    if start_time == nil then
        return false, nil, nil, nil, nil, nil, nil
    end

    --m_index_file.show("getFileDataInfo-2.5")

    m_index_file.updateFile(
        file_name,
        start_time, end_time, total_seconds,
        total_lines,
        start_index,
        col_with_data_str)

    --m_index_file.show("getFileDataInfo-3")
    m_index_file.indexSave()
    return true, start_time, end_time, total_seconds, total_lines, start_index, col_with_data_str
    --return nil, nil, nil, nil
end

m_index_file.indexSave = function()
    m_log.info("indexSave()")
    --local is_exist = is_file_exists(idx_file_name)
    local hFile = io.open(m_index_file.idx_file_name, "w")

    -- header
    local line_format = "%-42s,%-10s,%-10s,%-13s,%-11s,%-11s,%s\n"
    local headline = string.format(line_format, "file_name", "start_time", "end_time", "total_seconds", "total_lines", "start_index", "col_with_data_str")
    io.write(hFile, headline)
    local ver_line = "# api_ver=1\n"
    io.write(hFile, ver_line)

    --m_index_file.show("log_files_index_info")
    m_log.info("#log_files_index_info: %d", #m_index_file.log_files_index_info)
    for i = 1, #m_index_file.log_files_index_info, 1 do
        local info = m_index_file.log_files_index_info[i]

        local line = string.format( line_format,
            info.file_name,
            info.start_time,
            info.end_time,
            info.total_seconds,
            info.total_lines,
            info.start_index,
            info.col_with_data_str)

        io.write(hFile, line)
    end

    io.close(hFile)
end

--endregion

---- #########################################################################


local function doubleDigits(value)
    if value < 10 then
        return "0" .. value
    else
        return value
    end
end

local function toDuration1(totalSeconds)
    local hours = math_floor(totalSeconds / 3600)
    totalSeconds = totalSeconds - (hours * 3600)
    local minutes = math_floor(totalSeconds / 60)
    local seconds = totalSeconds - (minutes * 60)

    return doubleDigits(hours) .. ":" .. doubleDigits(minutes) .. ":" .. doubleDigits(seconds);
end

local function toDuration2(totalSeconds)
    local minutes = math_floor(totalSeconds / 60)
    local seconds = totalSeconds - (minutes * 60)

    return doubleDigits(minutes) .. "." .. doubleDigits(seconds) .. "min";

    --local minutes = math_floor(totalSeconds / 60)
    --return minutes .. " minutes";
    --return totalSeconds .. " sec";
end

local function getTotalSeconds(time)
    local total = tonumber(string.sub(time, 1, 2)) * 3600
    total = total + tonumber(string.sub(time, 4, 5)) * 60
    total = total + tonumber(string.sub(time, 7, 8))
    return total
end

local function collectData()
    if hFile == nil then
        buffer = ""
        hFile = io.open("/LOGS/" .. filename, "r")
        io.seek(hFile, current_session.startIndex)
        index = current_session.startIndex

        valPos = 0
        lines = 0
        m_log.info(string.format("current_session.total_lines: %d", current_session.total_lines))

        _points = {}
        _values = {}

        for varIndex = 1, 4, 1 do
            if sensorSelection[varIndex].value >= 2 then
                _points[varIndex] = {}
                _values[varIndex] = {}
            end
        end
    end

    local read = io.read(hFile, heap)
    if read == "" then
        io.close(hFile)
        hFile = nil
        return true
    end

    buffer = buffer .. read
    local i = 0

    for line in string_gmatch(buffer, "([^\n]+)\n") do
        if math.fmod(lines, skipLines) == 0 then
            local vals = m_utils.split(line)
            --m_log.info(string.format("collectData: 1: %s, 2: %s, 3: %s, 4: %s, line: %s", vals[1], vals[2], vals[3], vals[4], line))

            for varIndex = 1, 4, 1 do
                if sensorSelection[varIndex].value >= FIRST_VALID_COL then
                    local colId = sensorSelection[varIndex].value + 1
                    --m_log.info(string.format("collectData: varIndex: %d, value: %d, %d", varIndex, sensorSelection[varIndex].value, vals[colId]))
                    _values[varIndex][valPos] = vals[colId]
                end
            end

            valPos = valPos + 1
        end

        lines = lines + 1

        if lines > current_session.total_lines then
            io.close(hFile)
            hFile = nil
            return true
        end

        i = i + string.len(line) + 1 --dont forget the newline ;)
    end

    buffer = string.sub(buffer, i + 1) --dont forget the newline ;
    index = index + heap
    io.seek(hFile, index)
    return false
end

-- ---------------------------------------------------------------------------------------------------------

local function compare_file_names(a, b)
    a1 = string.sub(a, -21, -5)
    b1 = string.sub(b, -21, -5)
    --m_log.info("ab, %s ? %s", a, b)
    --m_log.info("a1b1, %s ? %s", a1, b1)
    return a1 > b1
end

local function compare_dates(a, b)
    return a > b
end

local function compare_names(a, b)
    return a < b
end

local function list_ordered_insert2(lst, newVal, cmp, firstValAt)
    -- remove duplication
    for i = 1, #lst do
        if lst[i] == newVal then
            return
        end
    end

    lst[#lst + 1] = newVal

    -- sort
    for i = #lst - 1, firstValAt, -1 do
        if cmp(lst[i], lst[i + 1]) == false then
            local tmp = lst[i]
            lst[i] = lst[i + 1]
            lst[i + 1] = tmp
        end
    end
    --print("list_ordered_insert:----------------\n")
    --print_table("list_ordered_insert", log_file_list)
end

local function list_ordered_insert(lst, newVal, cmp, firstValAt)
    --print("list_ordered_insert:----------------\n")

    -- sort
    for i = firstValAt, #lst, 1 do
        -- remove duplication
        --m_log.info("list_ordered_insert - %s ? %s",  newVal, lst[i] )
        if newVal == lst[i] then
            --print_table("list_ordered_insert - duplicated", lst)
            return
        end

        if cmp(newVal, lst[i]) == true then
            table.insert(lst, i, newVal)
            --print_table("list_ordered_insert - inserted", lst)
            return
        end
        --print_table("list_ordered_insert-loop", lst)
    end
    table.insert(lst, newVal)
    --print_table("list_ordered_insert-inserted-to-end", lst)
end

local function drawProgress(y, current, total)
    --m_log.info(string.format("drawProgress(%d. %d, %d)", y, current, total))
    local x = 140
    local pct = current / total
    lcd.drawFilledRectangle(x + 1, y + 1, (470 - x - 2) * pct, 14, TEXT_INVERTED_BGCOLOR)
    lcd.drawRectangle(x, y, 470 - x, 16, TEXT_COLOR)
end

-- read log file list
local function read_and_index_file_list()

    m_log.info("read_and_index_file_list(%d, %d)", log_file_list_raw_idx, #log_file_list_raw)

    if (#log_file_list_raw == 0) then
        m_log.info("read_and_index_file_list: init")
        m_index_file.indexInit()
        --log_file_list_raw = dir("/LOGS")
        log_file_list_raw_idx = 0
        for fn in dir("/LOGS") do
            --print_table("log_file_list_raw", log_file_list_raw)
            m_log.info("fn: %s", fn)
            log_file_list_raw[log_file_list_raw_idx + 1] = fn
            log_file_list_raw_idx = log_file_list_raw_idx + 1
        end
        --m_log.info("1 log_file_list_raw: %s", log_file_list_raw)
        log_file_list_raw_idx = 0
        m_tables.table_print("log_file_list_raw", log_file_list_raw)
        m_index_file.indexRead()
    end

    --math.min(10, #log_file_list_raw - log_file_list_raw_idx)

    for i = 1, 10, 1 do
        log_file_list_raw_idx = log_file_list_raw_idx + 1
        local fileName = log_file_list_raw[log_file_list_raw_idx]
        if fileName ~= nil then

            lcd.drawText(5, 30, "Analyzing & indexing files", TEXT_COLOR + BOLD)
            lcd.drawText(5, 60, string.format("indexing files: (%d/%d)", log_file_list_raw_idx, #log_file_list_raw), TEXT_COLOR + SMLSIZE)
            drawProgress(60, log_file_list_raw_idx, #log_file_list_raw)

            m_log.info("log file: (%d/%d) %s (detecting...)", log_file_list_raw_idx, #log_file_list_raw, fileName)

            -- F3A UNI recorde-2022-02-09-082937.csv
            local modelName, year, month, day, hour, min, sec, m, d, y = string.match(fileName, "^(.*)-(%d+)-(%d+)-(%d+)-(%d%d)(%d%d)(%d%d).csv$")
            if modelName ~= nil then
                --m_log.info("log file: %s (is csv)", fileName)
                --m_log.info(string.format("modelName:%s, day:%s, month:%s, year:%s, hour:%s, min:%s, sec:%s", modelName, day, month, year, hour, min, sec))

                --m_log.info("os.time", os.time{year=year, month=month, day=day, hour=hour, min=min, sec=sec})
                local model_datetime = string.format("%s-%s-%sT%s:%s:%s", year, month, day, hour, min, sec)
                local model_day = string.format("%s-%s-%s", year, month, day)

                -- read file
                local is_new, start_time, end_time, total_seconds, total_lines, start_index, col_with_data_str = m_index_file.getFileDataInfo(fileName)

                if total_seconds ~= nil then
                    --m_log.info("read_and_index_file_list: total_lines: %s, total_seconds: %s, col_with_data_str: [%s]", total_lines, total_seconds, col_with_data_str)
                    m_log.info("read_and_index_file_list: total_seconds: %s", total_seconds)
                    if total_seconds > min_log_sec_to_show then
                        list_ordered_insert(log_file_list, fileName, compare_file_names, 1)
                        list_ordered_insert(model_name_list, modelName, compare_names, 2)
                        list_ordered_insert(date_list, model_day, compare_dates, 2)
                    else
                        m_log.info("read_files_list: skipping short duration: %dsec, line: [%s]", total_seconds, fileName)
                    end

                    -- due to cpu load, early exit
                    if is_new then
                        return false
                    end
                end

            end
        end


        if log_file_list_raw_idx >= #log_file_list_raw then
            --m_index_file.indexSave()
            return true
        end
    end

    return false

end

local function onLogFileChange(obj)
    --m_tables.table_print("log_file_list ww", log_file_list)
    --print("111")
    --m_tables.table_print("log_file_list_filtered", log_file_list_filtered)
    --print("222")

    local i = obj.selected
    --labelDropDown.title = "Selected switch: " .. dropDownItems[i] .. " [" .. dropDownIndices[i] .. "]"
    m_log.info("Selected switch: " .. i)
    m_log.info("Selected switch: " .. log_file_list_filtered[i])
    filename = log_file_list_filtered[i]
    filename = log_file_list_filtered[i]
    filename_idx = i
    m_log.info("filename: " .. filename)
end

local function onAccuracyChange(obj)
    local i = obj.selected
    accuracy = i
    m_log.info("Selected accuracy: %s (%d)", accuracy_list[i], i)

    if accuracy == 4 then
        skipLines = 10
        heap = 2048 * 16
    elseif accuracy == 3 then
        skipLines = 5
        heap = 2048 * 16
    elseif accuracy == 2 then
        skipLines = 2
        heap = 2048 * 8
    else
        skipLines = 1
        heap = 2048 * 4
    end
end

local function filter_log_file_list(filter_model_name, filter_date)
    m_log.info("need to filter by: [%s] [%s]", filter_model_name, filter_date)

    m_tables.table_clear(log_file_list_filtered)

    for i = 1, #log_file_list do
        local ln = log_file_list[i]
        --m_log.info("filter_log_file_list: %d. %s", i, ln)

        --local is_model_name = (filter_model_name ~= nil) and (string.find(ln, filter_model_name) or string.sub(ln, 1,2)=="--")
        --local is_date = (filter_date ~= nil) and (string.find(ln, "[" .. filter_date .. "]") or string.sub(ln, 1,2)=="--")

        local modelName, year, month, day, hour, min, sec, m, d, y = string.match(ln, "^(.*)-(%d+)-(%d+)-(%d+)-(%d%d)(%d%d)(%d%d).csv$")

        local is_model_name
        if filter_model_name == nil or string.sub(filter_model_name, 1, 2) == "--" then
            is_model_name = true
        else
            is_model_name = (modelName == filter_model_name)
        end

        local is_date
        if filter_date == nil or string.sub(filter_date, 1, 2) == "--" then
            is_date = true
        else
            local model_day = string.format("%s-%s-%s", year, month, day)
            is_date = (model_day == filter_date)
        end

        if is_model_name and is_date then
            m_log.info("[%s] - OK (%s,%s)", ln, filter_model_name, filter_date)
            table.insert(log_file_list_filtered, ln)
        else
            print("The word tiger was not found.")
            m_log.info("[%s] - NOT-FOUND (%s,%s)", ln, filter_model_name, filter_date)
        end

    end

    if #log_file_list_filtered == 0 then
        table.insert(log_file_list_filtered, "not found")
    end
    m_tables.table_print("filter_log_file_list", log_file_list_filtered)

    -- update the log combo to first
    onLogFileChange(ddLogFile)
    ddLogFile.selected = 1
end

local function state_INIT(event, touchState)
    local is_done = read_and_index_file_list()

    if (is_done == true) then
        state = STATE.SELECT_FILE_INIT
    end

    return 0
end

local function state_SELECT_FILE_init(event, touchState)
    m_tables.table_clear(log_file_list_filtered)
    for i = 1, #log_file_list do
        table.insert(log_file_list_filtered, log_file_list[i])
    end

    m_log.info("++++++++++++++++++++++++++++++++")
    if ctx1 == nil then
        -- creating new window gui
        m_log.info("creating new window gui")
        ctx1 = libGUI.newGUI()

        ctx1.label(10, 25, 120, 24, "log file...", BOLD)

        ctx1.label(10, 55, 60, 24, "Model")
        ctx1.dropDown(90, 55, 380, 24, model_name_list, 1,
            function(obj)
                local i = obj.selected
                filter_model_name = model_name_list[i]
                m_log.info("Selected model-name: " .. filter_model_name)
                filter_log_file_list(filter_model_name, filter_date)
            end
        )

        ctx1.label(10, 80, 60, 24, "Date")
        ctx1.dropDown(90, 80, 380, 24, date_list, 1,
            function(obj)
                local i = obj.selected
                filter_date = date_list[i]
                m_log.info("Selected filter_date: " .. filter_date)
                filter_log_file_list(filter_model_name, filter_date)
            end
        )

        ctx1.label(10, 105, 60, 24, "Log file")
        ddLogFile = ctx1.dropDown(90, 105, 380, 24, log_file_list_filtered, filename_idx,
            onLogFileChange
        )
        onLogFileChange(ddLogFile)

        ctx1.label(10, 130, 60, 24, "Accuracy")
        dd4 = ctx1.dropDown(90, 130, 380, 24, accuracy_list, 1, onAccuracyChange)
        onAccuracyChange(dd4)
    end

    state = STATE.SELECT_FILE
    return 0
end

local function state_SELECT_SENSORS_INIT(event, touchState)
    m_log.info("state_SELECT_SENSORS_INIT")
    for varIndex = 1, 4, 1 do
        sensorSelection[varIndex].values[0] = "---"
        for i = 2, #columns, 1 do
            sensorSelection[varIndex].values[i - 1] = columns[i]
        end
    end

    current_option = 1

    if ctx2 == nil then
        -- creating new window gui
        m_log.info("creating new window gui")
        ctx2 = libGUI.newGUI()

        ctx2.label(10, 25, 120, 24, "Select sensors...", BOLD)

        --local model_name_list = { "-- all --", "aaa", "bbb", "ccc" }
        --local date_list = { "-- all --", "2017", "2018", "2019" }
        ctx2.label(10, 55, 60, 24, "Field 1")
        ctx2.dropDown(90, 55, 380, 24, columns, sensorSelection[1].value,
            function(obj)
                local i = obj.selected
                local var1 = columns[i]
                m_log.info("Selected var1: " .. var1)
                sensorSelection[1].value = i
            end
        )

        ctx2.label(10, 80, 60, 24, "Field 2")
        ctx2.dropDown(90, 80, 380, 24, columns, sensorSelection[2].value,
            function(obj)
                local i = obj.selected
                local var2 = columns[i]
                m_log.info("Selected var2: " .. var2)
                sensorSelection[2].value = i
            end
        )

        ctx2.label(10, 105, 60, 24, "Field 3")
        ctx2.dropDown(90, 105, 380, 24, columns, sensorSelection[3].value,
            function(obj)
                local i = obj.selected
                local var3 = columns[i]
                m_log.info("Selected var3: " .. var3)
                sensorSelection[3].value = i
            end
        )

        ctx2.label(10, 130, 60, 24, "Field 4")
        ctx2.dropDown(90, 130, 380, 24, columns, sensorSelection[4].value,
            function(obj)
                local i = obj.selected
                local var4 = columns[i]
                m_log.info("Selected var4: " .. var4)
                sensorSelection[4].value = i
            end
        )

    end

    state = STATE.SELECT_SENSORS
    return 0
end

local function state_SELECT_FILE_refresh(event, touchState)
    -- ## file selected
    if event == EVT_VIRTUAL_NEXT_PAGE then
        --Reset file load data
        m_log.info("Reset file load data")
        buffer = ""
        lines = 0
        heap = 2048 * 12
        --prevTotalSeconds = 0

        local is_new, start_time, end_time, total_seconds, total_lines, start_index, col_with_data_str = m_index_file.getFileDataInfo(filename)

        current_session = {
            startTime = start_time,
            endTime = end_time,
            total_seconds = total_seconds,
            total_lines = total_lines,
            startIndex = start_index,
            col_with_data_str = col_with_data_str
        }

        -- update columns
        local columns_temp, cnt = m_utils.split_pipe(col_with_data_str)
        m_log.info("state_SELECT_FILE_refresh: #col: %d", cnt)
        m_tables.table_clear(columns)
        columns[1] = "---"
        for i = 1, #columns_temp, 1 do
            local col = columns_temp[i]
            columns[#columns + 1] = col
            --m_log.info("state_SELECT_FILE_refresh: col: %s", col)
        end

        state = STATE.SELECT_SENSORS_INIT
        return 0
    end

    -- --color test
    --local dx = 250
    --local dy = 50
    --lcd.drawText(dx, dy, "COLOR_THEME_PRIMARY1", COLOR_THEME_PRIMARY1)
    --dy = dy +20
    --lcd.drawText(dx, dy, "COLOR_THEME_PRIMARY2", COLOR_THEME_PRIMARY2)
    --dy = dy +20
    --lcd.drawText(dx, dy, "COLOR_THEME_PRIMARY3", COLOR_THEME_PRIMARY3)
    --dy = dy +20
    --lcd.drawText(dx, dy, "COLOR_THEME_SECONDARY1", COLOR_THEME_SECONDARY1)
    --dy = dy +20
    --lcd.drawText(dx, dy, "COLOR_THEME_SECONDARY2", COLOR_THEME_SECONDARY2)
    --dy = dy +20
    --lcd.drawText(dx, dy, "COLOR_THEME_SECONDARY3", COLOR_THEME_SECONDARY3)
    --dy = dy +20
    --lcd.drawText(dx, dy, "COLOR_THEME_FOCUS", COLOR_THEME_FOCUS)
    --dy = dy +20
    --lcd.drawText(dx, dy, "COLOR_THEME_EDIT", COLOR_THEME_EDIT)
    --dy = dy +20
    --lcd.drawText(dx, dy, "COLOR_THEME_ACTIVE", COLOR_THEME_ACTIVE)
    --dy = dy +20
    --lcd.drawText(dx, dy, "COLOR_THEME_WARNING", COLOR_THEME_WARNING)
    --dy = dy +20
    --lcd.drawText(dx, dy, "COLOR_THEME_DISABLED", COLOR_THEME_DISABLED)

    ctx1.run(event, touchState)

    return 0
end

local function state_SELECT_SENSORS_refresh(event, touchState)
    if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_PREV_PAGE then
        state = STATE.SELECT_FILE_INIT
        return 0

    elseif event == EVT_VIRTUAL_NEXT_PAGE then
        state = STATE.READ_FILE_DATA
        return 0
    end

    ctx2.run(event, touchState)

    ---- draw sensor grid
    --local x = 200
    --local y = 50
    --local dx = 80
    --local dy = 25
    --local iCol = 2
    --local ix = 0
    --for iy = 0, 10, 1 do
    --    if iCol < #columns then
    --        local col_name = columns[iCol]
    --        m_log.info("col: %s", columns[i])
    --        lcd.drawFilledRectangle(x + dx * ix, y + dy * iy, 100, 20, TEXT_INVERTED_BGCOLOR)
    --        lcd.drawRectangle(x + dx * ix, y + dy * iy, 100, 20, TEXT_COLOR)
    --        lcd.drawText(x + dx * ix + 5, y + dy * iy, col_name, SMLSIZE + TEXT_COLOR)
    --        iCol = iCol +1
    --    end
    --end

    --for i = 1, #columns, 1 do
    --    local col_name = columns[i]
    --    m_log.info("col: %s", columns[i])
    --    lcd.drawText(x + dx, y + dy, col_name, SMLSIZE + TEXT_COLOR)
    --    y = y +dy
    --    dx = math.floor(i / 10)
    --end

    return 0
end

local function display_read_data_progress(conversionSensorId, conversionSensorProgress)
    --m_log.info("display_read_data_progress(%d, %d)", conversionSensorId, conversionSensorProgress)
    lcd.drawText(5, 25, "Reading data from file...", TEXT_COLOR)

    lcd.drawText(5, 60, "Reading line: " .. lines, TEXT_COLOR)
    drawProgress(60, lines, current_session.total_lines)

    local done_var_1 = 0
    local done_var_2 = 0
    local done_var_3 = 0
    local done_var_4 = 0
    if conversionSensorId == 1 then
        done_var_1 = conversionSensorProgress
    end
    if conversionSensorId == 2 then
        done_var_1 = valPos
        done_var_2 = conversionSensorProgress
    end
    if conversionSensorId == 3 then
        done_var_1 = valPos
        done_var_2 = valPos
        done_var_3 = conversionSensorProgress
    end
    if conversionSensorId == 4 then
        done_var_1 = valPos
        done_var_2 = valPos
        done_var_3 = valPos
        done_var_4 = conversionSensorProgress
    end
    local y = 85
    local dy = 25
    lcd.drawText(5, y, "Parsing Field 1: ", TEXT_COLOR)
    drawProgress(y, done_var_1, valPos)
    y = y + dy
    lcd.drawText(5, y, "Parsing Field 2: ", TEXT_COLOR)
    drawProgress(y, done_var_2, valPos)
    y = y + dy
    lcd.drawText(5, y, "Parsing Field 3: ", TEXT_COLOR)
    drawProgress(y, done_var_3, valPos)
    y = y + dy
    lcd.drawText(5, y, "Parsing Field 4: ", TEXT_COLOR)
    drawProgress(y, done_var_4, valPos)

end

local function state_READ_FILE_DATA_refresh(event, touchState)
    if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_PREV_PAGE then
        state = STATE.SELECT_SENSORS_INIT
        return 0
    end

    display_read_data_progress(0, 0)

    local is_done = collectData()
    if is_done then
        conversionSensorId = 0
        state = STATE.PARSE_DATA
    end

    return 0
end

local function state_PARSE_DATA_refresh(event, touchState)
    if event == EVT_VIRTUAL_EXIT then
        return 2

    elseif event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_PREV_PAGE then
        state = STATE.SELECT_SENSORS_INIT
        return 0
    end

    display_read_data_progress(conversionSensorId, conversionSensorProgress)

    local cnt = 0

    -- prepare
    if conversionSensorId == 0 then
        conversionSensorId = 1
        conversionSensorProgress = 0
        local fileTime = getTotalSeconds(current_session.endTime) - getTotalSeconds(current_session.startTime)
        graphTimeBase = valPos / fileTime

        for varIndex = 1, 4, 1 do
            if sensorSelection[varIndex].value >= FIRST_VALID_COL then
                local columnName = columns[sensorSelection[varIndex].value]
                -- remove column units if exist
                local i = string.find(columnName, "%(")
                local unit = ""

                if i ~= nil then
                    --m_log.info("read-header: %d, %s", i, unit)
                    unit = string.sub(columnName, i + 1, #columnName - 1)
                    columnName = string.sub(columnName, 0, i - 1)
                end
                --m_log.info("state_PARSE_DATA_refresh: col-name: %d. %s", varIndex, columnName)
                _points[varIndex] = {
                    min = 9999,
                    max = -9999,
                    minpos = 0,
                    maxpos = 0,
                    points = {},
                    name = columnName,
                    unit = unit
                }
            end
        end
        return 0
    end

    --
    if sensorSelection[conversionSensorId].value >= FIRST_VALID_COL then
        for i = conversionSensorProgress, valPos - 1, 1 do
            local val = tonumber(_values[conversionSensorId][i])
            _values[conversionSensorId][i] = val
            conversionSensorProgress = conversionSensorProgress + 1
            cnt = cnt + 1
            --m_log.info(string.format("PARSE_DATA: %d.%s %d min:%d max:%d", conversionSensorId, _points[conversionSensorId].name, #_points[conversionSensorId].points, _points[conversionSensorId].min, _points[conversionSensorId].max))

            if val > _points[conversionSensorId].max then
                _points[conversionSensorId].max = val
                _points[conversionSensorId].maxpos = i
            elseif val < _points[conversionSensorId].min then
                _points[conversionSensorId].min = val
                _points[conversionSensorId].minpos = i
            end

            if cnt > 100 then
                return 0
            end
        end
    end

    if conversionSensorId == 4 then
        graphStart = 0
        graphSize = valPos
        cursor = 50
        graphMode = GRAPH_MODE.CURSOR
        state = STATE.SHOW_GRAPH
    else
        conversionSensorProgress = 0
        conversionSensorId = conversionSensorId + 1
    end

    return 0
end

local function drawMain()
    lcd.clear()

    -- draw background
    if state == STATE.SHOW_GRAPH then
        --    lcd.drawFilledRectangle(0, 0, LCD_W, LCD_H, BLACK)
        --lcd.drawText(LCD_W - 85, LCD_H - 18, "Offer Shmuely", SMLSIZE + GREEN)
        lcd.drawBitmap(img2, 0, 0)
    else
        -- lcd.drawFilledRectangle(0, 0, LCD_W, LCD_H, WHITE)

        -- draw top-bar
        lcd.drawFilledRectangle(0, 0, LCD_W, 20, TITLE_BGCOLOR)
        --lcd.drawText(LCD_W - 95, LCD_H - 18, "Offer Shmuely", SMLSIZE)
        lcd.drawBitmap(img1, 0, 0)
    end

    --draw top-bar
    --lcd.drawFilledRectangle(0, 0, LCD_W, 20, TITLE_BGCOLOR)
    --lcd.setColor(CUSTOM_COLOR, lcd.RGB(193, 198, 215))

    if filename ~= nil then
        lcd.drawText(30, 1, "/LOGS/" .. filename, WHITE + SMLSIZE)
    end

end

local function run_GRAPH_Adjust(amount, mode)
    local scroll_due_cursor = 0

    if mode == GRAPH_MODE.CURSOR then
        cursor = cursor + math.floor(amount)
        if cursor > 100 then
            cursor = 100
            scroll_due_cursor = 1
        elseif cursor < 0 then
            cursor = 0
            scroll_due_cursor = -1
        end
    end

    if mode == GRAPH_MODE.ZOOM then
        if amount > 40 then
            amount = 40
        elseif amount < -40 then
            amount = -40
        end

        local oldGraphSize = graphSize
        graphSize = math.floor(graphSize / (1 + (amount * 0.02)))

        -- max zoom control
        if graphSize < 31 then
            graphSize = 31
        elseif graphSize > valPos then
            graphSize = valPos
        end

        if graphSize > (valPos - graphStart) then
            if amount > 0 then
                graphSize = valPos - graphStart
            else
                graphStart = valPos - graphSize
            end
        else
            local delta = oldGraphSize - graphSize
            graphStart = graphStart + math_floor((delta * (cursor / 100)))

            if graphStart < 0 then
                graphStart = 0
            elseif graphStart + graphSize > valPos then
                graphStart = valPos - graphSize
            end
        end

        graphSize = math_floor(graphSize)

        for varIndex = 1, 4, 1 do
            if sensorSelection[varIndex].value >= FIRST_VALID_COL then
                _points[varIndex].points = {}
            end
        end
    end

    if mode == GRAPH_MODE.MINMAX then
        local point = _points[(math.floor(graphMinMaxIndex / 2)) + 1]

        local delta = math.floor((point.max - point.min) / 50 * amount)

        if amount > 0 and delta < 1 then
            delta = 1
        elseif amount < 0 and delta > -1 then
            delta = -1
        end

        if graphMinMaxIndex % 2 == 0 then
            point.max = point.max + delta

            if point.max < point.min then
                point.max = point.min + 1
            end
        else
            point.min = point.min + delta

            if point.min > point.max then
                point.min = point.max - 1
            end
        end
    end

    if mode == GRAPH_MODE.SCROLL or scroll_due_cursor ~= 0 then

        if mode == GRAPH_MODE.CURSOR then
            amount = scroll_due_cursor
        end

        graphStart = graphStart + math.floor((graphSize / 100) * amount)
        if graphStart + graphSize > valPos then
            graphStart = valPos - graphSize
        elseif graphStart < 0 then
            graphStart = 0
        end

        graphStart = math_floor(graphStart)

        for varIndex = 1, 4, 1 do
            if sensorSelection[varIndex].value >= FIRST_VALID_COL then
                _points[varIndex].points = {}
            end
        end
    end
end

local function drawGraph_base()
    local txt
    if graphMode == GRAPH_MODE.CURSOR then
        txt = "Cursor"
    elseif graphMode == GRAPH_MODE.ZOOM then
        txt = "Zoom"
    elseif graphMode == GRAPH_MODE.MINMAX then
        txt = "min/max"
    else
        txt = "Scroll"
    end

    --lcd.drawFilledRectangle(390, 1, 100, 18, DARKGREEN)
    lcd.drawText(380, 3, "Mode: " .. txt, SMLSIZE + BLACK)
    --lcd.drawText(LCD_W - 85, LCD_H - 18, "Offer Shmuely", SMLSIZE + GREEN)
end

local function drawGraph_points(points, min, max)
    if min == max then
        return
    end

    local yScale = (max - min) / 200
    local prevY = graphConfig.y_end - ((points[0] - min) / yScale)
    prevY = math.min(math.max(prevY, graphConfig.y_start), graphConfig.y_end)
    --if prevY > graphConfig.y_end then
    --    prevY = graphConfig.y_end
    --elseif prevY < graphConfig.y_start then
    --    prevY = graphConfig.y_start
    --end

    for i = 0, #points - 1, 1 do
        local x1 = graphConfig.x_start + (xStep * i)
        local y = graphConfig.y_end - ((points[i + 1] - min) / yScale)

        y = math.min(math.max(y, graphConfig.y_start), graphConfig.y_end)
        --if y > graphConfig.y_end then
        --    y = graphConfig.y_end
        --elseif y < graphConfig.y_start then
        --    y = graphConfig.y_start
        --end

        lcd.drawLine(x1, prevY, x1 + xStep, y, SOLID, CUSTOM_COLOR)
        prevY = y
    end
end

local function drawGraph()
    local skip = graphSize / 101

    lcd.setColor(CUSTOM_COLOR, BLACK)
    drawGraph_base()

    -- draw cursor
    local cursor_x = graphConfig.x_start + (xStep * cursor)
    lcd.drawLine(cursor_x, graphConfig.y_start, cursor_x, graphConfig.y_end, DOTTED, WHITE)

    local cursorLine = math_floor((graphStart + (cursor * skip)) / graphTimeBase)
    local cursorTime = toDuration1(cursorLine)

    if cursorLine < 3600 then
        cursorTime = string.sub(cursorTime, 4)
    end

    -- draw cursor time
    lcd.drawText(cursor_x, 20, cursorTime, WHITE)

    -- draw bottom session line
    local viewScale = valPos / 479
    local viewStart = math.floor(graphStart / viewScale)
    local viewEnd = math.floor((graphStart + graphSize) / viewScale)
    lcd.drawLine(viewStart, 269, viewEnd, 269, SOLID, RED)
    lcd.drawLine(viewStart, 270, viewEnd, 270, SOLID, RED)
    lcd.drawLine(viewStart, 271, viewEnd, 271, SOLID, RED)

    -- draw all lines
    for varIndex = 1, 4, 1 do
        if (sensorSelection[varIndex].value >= FIRST_VALID_COL) and (_points[varIndex].min ~= 0 or _points[varIndex].max ~= 0) then
            local varPoints = _points[varIndex]
            local varCfg = graphConfig[varIndex]
            --m_log.info(string.format("drawGraph: %d.%s %d min:%d max:%d", varIndex, varPoints.name, #varPoints.points, varPoints.min, varPoints.max))
            --m_log.info("drawGraph: %d. %s", varIndex, varPoints.columnName)
            if #varPoints.points == 0 then
                for i = 0, 100, 1 do
                    --print("i:" .. i .. ", skip: " .. skip .. ", result:" .. math_floor(graphStart + (i * skip)))
                    varPoints.points[i] = _values[varIndex][math_floor(graphStart + (i * skip))]
                    if varPoints.points[i] == nil then
                        varPoints.points[i] = 0
                    end
                end
            end

            -- points
            lcd.setColor(CUSTOM_COLOR, varCfg.color)
            drawGraph_points(varPoints.points, varPoints.min, varPoints.max)

            -- draw min/max
            local minPos = math_floor((varPoints.minpos + 1 - graphStart) / skip)
            local maxPos = math_floor((varPoints.maxpos + 1 - graphStart) / skip)
            minPos = math.min(math.max(minPos, 0), 100)
            maxPos = math.min(math.max(maxPos, 0), 100)

            local x = graphConfig.x_start + (minPos * xStep)
            lcd.drawLine(x, 240, x, 250, SOLID, CUSTOM_COLOR)

            local x = graphConfig.x_start + (maxPos * xStep)
            lcd.drawLine(x, 30, x, graphConfig.y_start, SOLID, CUSTOM_COLOR)

            -- draw max
            if graphMode == GRAPH_MODE.MINMAX and graphMinMaxIndex == (varIndex - 1) * 2 then
                local txt = string.format("Max: %d", varPoints.max)
                local w, h = lcd.sizeText(txt, MIDSIZE)
                lcd.drawFilledRectangle(varCfg.maxx, varCfg.maxy, w + 4, h, GREY, 3)
                lcd.drawRectangle(varCfg.maxx, varCfg.maxy, w + 4, h, CUSTOM_COLOR)
                lcd.drawText(varCfg.maxx, varCfg.maxy, txt, MIDSIZE + CUSTOM_COLOR)
            else
                lcd.drawFilledRectangle(varCfg.maxx - 5, varCfg.maxy, 35, 14, GREY, 5)
                lcd.drawText(varCfg.maxx, varCfg.maxy, varPoints.max, SMLSIZE + CUSTOM_COLOR)
            end

            -- draw min
            if graphMode == GRAPH_MODE.MINMAX and graphMinMaxIndex == ((varIndex - 1) * 2) + 1 then
                local txt = string.format("Min: %d", varPoints.min)
                local w, h = lcd.sizeText(txt, MIDSIZE)
                lcd.drawFilledRectangle(varCfg.minx, varCfg.miny, w + 4, h, GREY, 5)
                lcd.drawRectangle(varCfg.minx, varCfg.miny, w + 4, h, CUSTOM_COLOR)
                lcd.drawText(varCfg.minx, varCfg.miny, txt, MIDSIZE + CUSTOM_COLOR)
                --lcd.drawText(cfg.minx, cfg.miny, points.min, MIDSIZE + TEXT_INVERTED_COLOR + INVERS)
            else
                lcd.drawFilledRectangle(varCfg.minx - 5, varCfg.miny, 35, 14, GREY, 5)
                lcd.drawText(varCfg.minx, varCfg.miny, varPoints.min, SMLSIZE + CUSTOM_COLOR)
            end

            -- col-name and value at cursor
            if varPoints.points[cursor] ~= nil then
                lcd.drawText(varCfg.valx, varCfg.valy, varPoints.name .. "=" .. varPoints.points[cursor] .. varPoints.unit, CUSTOM_COLOR)

                local yScale = (varPoints.max - varPoints.min) / 200
                local cursor_y = graphConfig.y_end - ((varPoints.points[cursor] - varPoints.min) / yScale)
                local x1 = cursor_x + 30
                local y1 = 120 + 25 * varIndex
                lcd.drawFilledRectangle(x1, y1, 40, 20, CUSTOM_COLOR)
                lcd.drawLine(x1, y1 + 10, cursor_x, cursor_y, DOTTED, CUSTOM_COLOR)
                lcd.drawFilledCircle(cursor_x, cursor_y, 4, CUSTOM_COLOR)
                lcd.drawText(x1 + 40, y1, varPoints.points[cursor] .. varPoints.unit, BLACK + RIGHT)
            end
        end
    end
end

local function state_SHOW_GRAPH_refresh(event, touchState)
    if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_PREV_PAGE then
        state = STATE.SELECT_SENSORS_INIT
        return 0
    end

    if graphMode == GRAPH_MODE.MINMAX and event == EVT_PAGEDN_FIRST then
        graphMinMaxIndex = graphMinMaxIndex + 1

        if graphMinMaxIndex == 8 then
            graphMinMaxIndex = 0
        end
        if graphMinMaxIndex == 2 and sensorSelection[2].value == 0 then
            graphMinMaxIndex = 4
        end
        if graphMinMaxIndex == 4 and sensorSelection[3].value == 0 then
            graphMinMaxIndex = 6
        end
        if graphMinMaxIndex == 6 and sensorSelection[4].value == 0 then
            graphMinMaxIndex = 0
        end
        if graphMinMaxIndex == 0 and sensorSelection[1].value == 0 then
            graphMinMaxIndex = 2
        end
    elseif graphMode == GRAPH_MODE.MINMAX and event == EVT_PAGEUP_FIRST then
        graphMinMaxIndex = graphMinMaxIndex - 1

        if graphMinMaxIndex < 0 then
            graphMinMaxIndex = 7
        end
        if graphMinMaxIndex == 7 and sensorSelection[4].value == 0 then
            graphMinMaxIndex = 5
        end
        if graphMinMaxIndex == 5 and sensorSelection[3].value == 0 then
            graphMinMaxIndex = 3
        end
        if graphMinMaxIndex == 3 and sensorSelection[2].value == 0 then
            graphMinMaxIndex = 1
        end
        if graphMinMaxIndex == 1 and sensorSelection[1].value == 0 then
            graphMinMaxIndex = 7
        end
    elseif event == EVT_VIRTUAL_ENTER or event == EVT_ROT_BREAK then
        if graphMode == GRAPH_MODE.CURSOR then
            graphMode = GRAPH_MODE.ZOOM
        elseif graphMode == GRAPH_MODE.ZOOM then
            graphMode = GRAPH_MODE.SCROLL
        elseif graphMode == GRAPH_MODE.SCROLL then
            graphMode = GRAPH_MODE.MINMAX
        else
            graphMode = GRAPH_MODE.CURSOR
        end
    elseif event == EVT_PLUS_FIRST or event == EVT_ROT_RIGHT or event == EVT_PLUS_REPT then
        run_GRAPH_Adjust(1, graphMode)
    elseif event == EVT_MINUS_FIRST or event == EVT_ROT_LEFT or event == EVT_MINUS_REPT then
        run_GRAPH_Adjust(-1, graphMode)
    end

    if event == EVT_TOUCH_SLIDE then
        m_log.info("EVT_TOUCH_SLIDE")
        m_log.info("EVT_TOUCH_SLIDE, startX:%d   x:%d", touchState.startX, touchState.x)
        m_log.info("EVT_TOUCH_SLIDE, startY:%d   y:%d", touchState.startY, touchState.y)
        local dx = touchState.startX - touchState.x
        local adjust = math.floor(dx / 100)
        m_log.info("EVT_TOUCH_SLIDE, dx:%d,   adjust:%d", dx, adjust)
        run_GRAPH_Adjust(adjust, GRAPH_MODE.SCROLL)
    end

    local adjust = getValue('ail')
    if math.abs(adjust) > 100 then
        if math.abs(adjust) < 800 then
            adjust = adjust / 100
        else
            adjust = adjust / 50
        end
        if graphMode ~= GRAPH_MODE.MINMAX then
            run_GRAPH_Adjust(adjust, GRAPH_MODE.SCROLL)
        end
    end

    adjust = getValue('ele') / 200
    if math.abs(adjust) > 0.5 then
        if graphMode ~= GRAPH_MODE.MINMAX then
            run_GRAPH_Adjust(adjust, GRAPH_MODE.ZOOM)
        else
            run_GRAPH_Adjust(-adjust, GRAPH_MODE.MINMAX)
        end
    end

    adjust = getValue('rud') / 200
    if math.abs(adjust) > 0.5 then
        run_GRAPH_Adjust(adjust, GRAPH_MODE.CURSOR)
    end

    --adjust = getValue('jsy') / 200
    --if math.abs(adjust) > 0.5 then
    --    run_GRAPH_Adjust(adjust, GRAPH_MODE.ZOOM)
    --end

    --adjust = getValue('jsx') / 200
    --if math.abs(adjust) > 0.5 then
    --    run_GRAPH_Adjust(adjust, GRAPH_MODE.SCROLL)
    --end

    drawGraph()
    return 0
end

local function init()
end

local function run(event, touchState)
    if event == nil then
        error("Cannot be run as a model script!")
        return 2
    end

    --m_log.info("run() ---------------------------")
    --m_log.info("event: %s", event)

    --if event == EVT_TOUCH_SLIDE then
    --    m_log.info("EVT_TOUCH_SLIDE")
    --    m_log.info("EVT_TOUCH_SLIDE, startX:%d   x:%d", touchState.startX, touchState.x)
    --    m_log.info("EVT_TOUCH_SLIDE, startY:%d   y:%d", touchState.startY, touchState.y)
    --    local d = math.floor((touchState.startY - touchState.y) / 20 + 0.5)
    --end

    drawMain()

    if state == STATE.INIT then
        m_log.info("STATE.INIT")
        return state_INIT()

    elseif state == STATE.SELECT_FILE_INIT then
        m_log.info("STATE.SELECT_FILE_INIT")
        return state_SELECT_FILE_init(event, touchState)

    elseif state == STATE.SELECT_FILE then
        --m_log.info("STATE.state_SELECT_FILE_refresh")
        return state_SELECT_FILE_refresh(event, touchState)

    elseif state == STATE.SELECT_SENSORS_INIT then
        m_log.info("STATE.SELECT_SENSORS_INIT")
        return state_SELECT_SENSORS_INIT(event, touchState)

    elseif state == STATE.SELECT_SENSORS then
        --m_log.info("STATE.SELECT_SENSORS")
        return state_SELECT_SENSORS_refresh(event, touchState)

    elseif state == STATE.READ_FILE_DATA then
        m_log.info("STATE.READ_FILE_DATA")
        return state_READ_FILE_DATA_refresh(event, touchState)

    elseif state == STATE.PARSE_DATA then
        m_log.info("STATE.PARSE_DATA")
        return state_PARSE_DATA_refresh(event, touchState)

    elseif state == STATE.SHOW_GRAPH then
        return state_SHOW_GRAPH_refresh(event, touchState)

    end

    --impossible state
    error("Something went wrong with the script!")
    return 2
end


return { init = init, run = run }
