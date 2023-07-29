local m_log,m_utils,m_libgui  = ...

-- Author: Offer Shmuely (2023)
local ver = "0.1"
local app_name = "set_timer1"

local M = {}

local ctx2
local label_new_time
local label_org_time

---------------------------------------------------------------------------------------------------
local Fields = {
    timer1_hour = { text = 'hours:'  , x = 160, y = 115 , w = 30, is_visible = 1, default_value = 6, min = 0, max = 1000 },
    timer1_min  = { text = 'minutes:', x = 160, y = 140 , w = 30, is_visible = 1, default_value = 6, min = 0, max = 60   },
    timer1_sec  = { text = 'seconds:', x = 160, y = 165 , w = 30, is_visible = 1, default_value = 6, min = 0, max = 60   },
}
---------------------------------------------------------------------------------------------------

function M.getVer()
    return ver
end

local function log(fmt, ...)
    m_log.info(fmt, ...)
    print(app_name .. string.format(fmt, ...))
end
---------------------------------------------------------------------------------------------------

local function formatTime(t1)
    local dd_raw = t1.value / 86400 -- 24*3600
    local dd = math.floor(dd_raw)
    local hh_raw = (dd_raw - dd) * 24
    local hh = math.floor(hh_raw)
    local mm_raw = (hh_raw - hh) * 60
    local mm = math.floor(mm_raw)
    local ss_raw = (mm_raw - mm) * 60
    local ss = math.floor(ss_raw)
    local time_str
    if dd == 0 and hh == 0 then
        -- less then 1 hour, 59:59
        time_str = string.format("%02d:%02d", mm, ss)
    elseif dd == 0 then
        -- lass then 24 hours, 23:59:59
        time_str = string.format("%02d:%02d:%02d", hh, mm, ss)
    else
        -- more than 24 hours

        -- use_hours 25:59:59
        time_str = string.format("%02d:%02d:%02d", dd * 24 + hh, mm, ss)
        -- use days: 5d 23:59:59
        --time_str = string.format("%dd %02d:%02d:%02d", dd, hh, mm, ss)
    end
    --log("test: " .. time_str)
    return dd, hh, mm, ss
end
local function formatTime2(hh, mm, ss)
    local time_str
    if 0 and hh == 0 then
        -- less then 1 hour, 59:59
        time_str = string.format("%02d:%02d", mm, ss)
    else
        -- lass then 24 hours, 23:59:59
        time_str = string.format("%02d:%02d:%02d", hh, mm, ss)
    end
    --log("test: " .. time_str)
    return time_str
end

function M.init()
    local menu_x = 50
    local menu_w = 60
    local menu_h = 26

    local t1 = model.getTimer(0)
    local dd, hh, mm, ss = formatTime(t1)

    ctx2 = m_libgui.newGUI()

    ctx2.label(menu_x, 60, 0, menu_h, "original time:", m_utils.FONT_8)
    label_org_time = ctx2.label(160, 60, 0, menu_h, formatTime2(hh, mm, ss), m_utils.FONT_8)


    ctx2.label(menu_x, 90, 0, menu_h, "new time:", m_utils.FONT_8)

    local p = Fields.timer1_hour
    ctx2.label(menu_x, p.y, menu_w, menu_h, "Hour", m_utils.FONT_8)
    p.gui_obj = ctx2.number(p.x, p.y, p.w, menu_h, hh, nil, m_utils.FONT_8, p.min, p.max)

    local p = Fields.timer1_min
    ctx2.label(menu_x, p.y, menu_w, menu_h, "Min", m_utils.FONT_8)
    p.gui_obj = ctx2.number(p.x, p.y, p.w, menu_h, mm, nil, m_utils.FONT_8, p.min, p.max)

    local p = Fields.timer1_sec
    ctx2.label(menu_x, p.y, menu_w, menu_h, "Sec", m_utils.FONT_8)
    p.gui_obj = ctx2.number(p.x, p.y, p.w, menu_h, ss, nil, m_utils.FONT_8, p.min, p.max)

    label_new_time = ctx2.label(260, 140, 0, menu_h, formatTime2(hh, mm, ss), m_utils.FONT_16)

    ctx2.label(menu_x, 220, 0, menu_h, "Setting timer to count up", m_utils.FONT_8)
    ctx2.label(menu_x, 240, 0, menu_h, "Setting timer to be persistent", m_utils.FONT_8)

    --return m_utils.PRESET_RC.OK_CONTINUE
    return nil
end


function M.draw_page(event, touchState)

    local hh = Fields.timer1_hour.gui_obj.value
    local mm = Fields.timer1_min.gui_obj.value
    local ss = Fields.timer1_sec.gui_obj.value
    label_new_time.title = formatTime2(hh, mm, ss)

    ctx2.run(event, touchState)

    return m_utils.PRESET_RC.OK_CONTINUE
end

function M.do_update_model()
    log("preset::do_update_model()")

    local hh = Fields.timer1_hour.gui_obj.value
    local mm = Fields.timer1_min.gui_obj.value
    local ss = Fields.timer1_sec.gui_obj.value

    local t1 = model.getTimer(0)
    t1.value = hh*3600 + mm*60 + ss
    t1.start = 0
    --t1.persistent = 2
    model.setTimer(0, t1)

    return m_utils.PRESET_RC.OK_CONTINUE
end

return M