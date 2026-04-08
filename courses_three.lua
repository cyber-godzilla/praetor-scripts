--[[
Simple courses three-part script
]]
local strings = require('lib_strings')
local courses = require('lib_courses')

local M = {}

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
            set_mode('disable')
            notify('Completed', 'Attribute processing')
        end,
    },
}

return M
