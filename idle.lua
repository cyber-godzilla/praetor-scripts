--[[
Checks your fatigue level until back to 100%, then chains via after:<mode>.
]]
local after = require('lib_after')

local M = {}

M.desc = 'Wait for fatigue to recover, then chain onward'
M.chains = true

function M.on_start(args)
    after.parse(args)

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
            notify('Idle Complete', 'Fatigue full')
            after.finish()
        end,
    },
}

return M
