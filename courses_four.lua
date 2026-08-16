--[[
Simple four-part courses script
]]
local strings = require('lib_strings')
local courses = require('lib_courses')
local after = require('lib_after')

local M = {}

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
        action = function() send('go south') end,
    },
    -- Mud pit
    {
        match = 'You arrive at a mud pit.',
        action = function() send('jump rope') end,
    },
    -- Swinging weights
    {
        match = 'You arrive at a path through swinging weights.',
        action = function() send('go path') end,
    },
    -- Circular track
    {
        match = 'You arrive at a circular track.',
        action = function() send('go track') end,
    },
    -- Hot coals
    {
        match = 'You arrive at a bed of hot coals.',
        action = function() send('go bed') end,
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
