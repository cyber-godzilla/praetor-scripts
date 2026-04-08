--[[
Language lessons
]]
local strings = require('lib_learn_languages')

local M = {}

M.reactions = {
    -- Woman teacher
    {
        match = strings.woman_language,
        action = function() send('echo woman') end,
    },
    -- Man teacher
    {
        match = strings.man_language,
        action = function() send('echo man') end,
    },
    -- Done for today
    {
        -- This string may need updated
        match = "I've taught you all I can for today",
        action = function()
            set_mode('disable')
            notify('Completed', 'Language processing')
        end,
    },
}

return M
