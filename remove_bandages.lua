--[[
Iterates through removing all of your bandages.
Mostly useful for Kelestian lessons or after someone drags your battered body to a healer.
]]
local strings = require('lib_strings')

local M = {}

-- Parse body parts from condition text.
local function parse_parts(text, suffix)
    local startIdx = text:find('Your ')
    if not startIdx then return {} end
    local chunk = text:sub(startIdx + 5)
    local endIdx = chunk:find(suffix)
    if not endIdx then return {} end
    chunk = chunk:sub(1, endIdx - 1)
    chunk = chunk:gsub(', and ', ', ')
    chunk = chunk:gsub(' and ', ', ')
    local parts = {}
    for part in chunk:gmatch('[^,]+') do
        part = part:match('^%s*(.-)%s*$')
        if part ~= '' then
            parts[#parts + 1] = part
        end
    end
    return parts
end

function M.on_start(args)
    state.set('waiting_for_cond', true)
    state.set('body_parts', {})
    send('cond')

    -- Timeout: if no bandages found in cond output, disable.
    set_timeout(function()
        if state.get('waiting_for_cond') then
            state.set('waiting_for_cond', false)
            log('No bandages found, disabling')
            set_mode('disable')
        end
    end, 3000)
end

M.reactions = {
    -- Detect bandaged parts (plural): "Your X and Y are wrapped in bandages"
    {
        match = 'are wrapped in bandages',
        action = function(text)
            if not state.get('waiting_for_cond') then return end
            state.set('waiting_for_cond', false)
            local parts = parse_parts(text, ' are wrapped in bandages')
            state.set('body_parts', parts)
            send('tend me')
        end,
    },
    -- Detect bandaged parts (singular): "Your X is bandaged"
    {
        match = 'is bandaged',
        action = function(text)
            if not state.get('waiting_for_cond') then return end
            state.set('waiting_for_cond', false)
            local parts = parse_parts(text, ' is bandaged')
            state.set('body_parts', parts)
            send('tend me')
        end,
    },
    -- Patient must be sitting/lying
    {
        match = 'Your patient must be sitting or lying down',
        action = function() send('kneel') end,
    },
    -- Kneel success
    {
        match = 'You kneel',
        action = function() send('tend me') end,
    },
    -- Unbusy: cut bandages from next part
    {
        match = strings.unbusy,
        action = function()
            if state.get('waiting_for_cond') then return end
            local parts = state.get('body_parts') or {}
            if #parts == 0 then
                set_mode('disable')
                notify('Completed', 'Bandage removal finished')
                return
            end
            send('cut bandages from ' .. parts[1])
        end,
    },
    -- No bandages on that part: move to next
    {
        match = 'There are no bandages there',
        action = function()
            local parts = state.get('body_parts') or {}
            if #parts > 0 then
                table.remove(parts, 1)
                state.set('body_parts', parts)
            end
            if #parts == 0 then
                set_mode('disable')
                notify('Completed', 'Bandage removal finished')
                return
            end
            send('cut bandages from ' .. parts[1])
        end,
    },
}

return M
