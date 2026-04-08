--[[
Everyone's first 2001-era TEC Script: 'Send . every time you're no longer busy'
]]
local strings = require('lib_strings')

local M = {}

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
