--[[
Pull a wagon from the Monlon east gate to Romulus
]]
local strings = require('lib_strings')

local M = {}

local steps = {
    'pull wagon w 2 n 1',
    'pull wagon w 2 n 1',
    'pull wagon w 3 sw 1 w 1',
    'pull wagon s 2 sw 1',
    'pull wagon s 2 sw 2 s 1 w 1',
}

function M.on_start(args)
    state.set('step_index', 1)
    state.set('waiting_for_stop', false)
    send(steps[1])
end

M.reactions = {
    {
        match = 'You stop pulling',
        action = function()
            state.set('waiting_for_stop', true)
        end,
    },
    {
        match = strings.unbusy,
        action = function()
            if not state.get('waiting_for_stop') then return end
            state.set('waiting_for_stop', false)
            local idx = state.get('step_index') + 1
            state.set('step_index', idx)
            if idx > #steps then
                notify('East To Romulus', 'Route complete')
                set_mode('disable')
                return
            end
            send(steps[idx])
        end,
    },
}

return M
