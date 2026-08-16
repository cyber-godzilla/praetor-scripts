--[[
Everyone's first 2001-era TEC Script: 'Send . every time you're no longer busy'
]]
local strings = require('lib_strings')

local M = {}

M.desc = 'Send "." every time you are no longer busy'

function M.on_start(args)
    send('.')
end

M.reactions = {
    {
        match = strings.unbusy,
        action = function() send('.') end,
    },
}

return M
