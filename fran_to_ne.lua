--[[
Leaves the Franlius baths to go to the northern half of Franlius.
Expects you to be laying when this starts.
]]
local strings = require('lib_strings')

local M = {}

function M.on_start(args)
    state.set('step', 1)
    send('stand')
end

M.reactions = {
    -- Step 1: stand -> unbusy -> go up
    {
        match = strings.unbusy,
        action = function()
            local step = state.get('step')
            if step == 1 then
                state.set('step', 2)
                send('u')
            end
        end,
    },
    -- Step 2: arrive at bath house -> walk to bridge
    {
        match = 'You arrive at a public bath house',
        action = function()
            state.set('step', 3)
            send('fran bath to bridge')
        end,
    },
    -- Step 3-4: stop walking -> jump bridge or finish
    {
        match = 'You stop walking',
        action = function()
            local step = state.get('step')
            if step == 3 then
                state.set('step', 4)
                send('jump bridge')
            elseif step == 5 then
                notify('Completed', 'Route parsing')
                set_mode('idle')
            end
        end,
    },
    -- Step 4: success -> walk north
    {
        match = '[Success:',
        action = function()
            if state.get('step') == 4 then
                state.set('step', 5)
                send('walk n 11')
            end
        end,
    },
}

return M
