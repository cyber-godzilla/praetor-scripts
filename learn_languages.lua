--[[
Language lessons
]]
local strings = require('lib_learn_languages')
local after = require('lib_after')

local M = {}

function M.on_start(args)
    after.parse(args)
end

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
        match = "I've taught you all I can for the day",
        action = function()
            notify('Completed', 'Language processing')
            after.finish()
        end,
    },
}

return M
