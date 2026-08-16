--[[
Simple courses three-part script
]]
local strings = require('lib_strings')
local courses = require('lib_courses')
local after = require('lib_after')

local M = {}

M.desc = 'Run three-obstacle training courses'
M.chains = true

function M.on_start(args)
    after.parse(args)
end

M.reactions = {
    -- Must stand
    {
        match = strings.must_stand,
        action = function() send('stand') end,
    },
    -- Ready for next obstacle
    {
        match = courses.can_start_course,
        action = function() send('go east') end,
    },
    -- Climbing wall
    {
        match = 'You arrive at a climbing wall.',
        action = function() send('climb rope') end,
    },
    -- Pool
    {
        match = 'You arrive at a pool.',
        action = function() send('go plank') end,
    },
    -- Dropping pole
    {
        match = 'You arrive at a dropping pole',
        action = function() send('go path') end,
    },
    -- Course complete
    {
        match = courses.course_complete,
        action = function()
            notify('Completed', 'Attribute processing')
            after.finish()
        end,
    },
}

return M
