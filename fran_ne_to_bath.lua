--[[
From the northern half of Franlius, walks back to the Franlius baths.
Then transitions to idle, with instructions to go back to Northeast Franlius after.
]]
local strings = require('lib_strings')

local M = {}

function M.on_start(args)
    state.set('step', 1)
    send('walk s 11')
end

M.reactions = {
    -- Steps 1,3: stop walking -> jump bridge or go down
    {
        match = 'You stop walking',
        action = function()
            local step = state.get('step')
            if step == 1 then
                state.set('step', 2)
                send('jump bridge')
            elseif step == 3 then
                state.set('step', 4)
                send('d')
            end
        end,
    },
    -- Step 2: success -> walk to bath
    {
        match = strings.success,
        action = function()
            if state.get('step') == 2 then
                state.set('step', 3)
                send('fran bridge to bath')
            end
        end,
    },
    -- Step 4: arrive at bath -> lay down
    {
        match = 'You arrive at a warm bath',
        action = function()
            if state.get('step') == 4 then
                state.set('step', 5)
                send('lay')
            end
        end,
    },
    -- Step 5: relax -> done, switch to idle with fran_to_ne as next
    {
        match = 'You relax your body',
        action = function()
            if state.get('step') == 5 then
                notify('Completed', 'Route to bath')
                set_mode('idle', {'fran_to_ne'})
            end
        end,
    },
}

return M
