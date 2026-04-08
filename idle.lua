--[[
Checks your fatigue level until back to 100%
]]
local M = {}

function M.on_start(args)
    state.set('next_mode', args[1] or 'disable')

    -- Send initial status check
    send('ss')

    -- Schedule recurring keepalive every 7-11 minutes
    set_interval(function()
        send('ss')
    end, 420000 + math.random(0, 240000))
end

M.reactions = {
    {
        match = 'Fatigue: 100%',
        action = function()
            local next = state.get('next_mode')
            notify('Idle Complete', 'Fatigue full, switching to ' .. next)
            set_mode(next)
        end,
    },
}

return M
