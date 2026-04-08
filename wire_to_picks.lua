--[[
A very opinionated workflow for taking broken wires from lockpick fashioning and forging them into functional lockpicks.
Only really useful if you're using board.lua without perfected lockpick fashioning
]]
local strings = require('lib_strings')

local M = {}

function M.on_start(args)
    log('Starting broken wire to pick processing')
    state.set('step', 'begin')
    send('get my mold')
end

M.reactions = {
    -- Got mold
    {
        match = 'You take a clay mold of a lockpick',
        action = function()
            if state.get('step') == 'begin' then
                state.set('step', 'haveMold')
                send('drop mold')
            end
        end,
    },
    -- Dropped mold
    {
        match = 'You drop a clay mold of a lockpick',
        action = function()
            if state.get('step') == 'haveMold' then
                state.set('step', 'droppedMold')
                send('get tongs')
            end
        end,
    },
    -- Got tongs
    {
        match = 'You take a pair of iron tongs',
        action = function()
            local step = state.get('step')
            if step == 'droppedMold' then
                state.set('step', 'haveTongs')
                send('get crucible')
            end
            if step == 'haveCrucibleCheckTongs' then
                state.set('step', 'activelyHeating')
                send('heat cruc over iron furnace')
            end
        end,
    },
    -- Got crucible
    {
        match = 'You take a crucible',
        action = function()
            local step = state.get('step')
            if step == 'haveTongs' then
                state.set('step', 'haveCrucible')
                send('drop crucible')
            end
            if step == 'readyToHeat' then
                state.set('step', 'activelyHeating')
                send('heat cruc over iron furnace')
            end
            if step == 'filledCrucibleAfterFailedPick' then
                state.set('step', 'haveCrucibleCheckTongs')
                send('get tongs')
            end
        end,
    },
    -- Already carrying crucible
    {
        match = 'You are already carrying a crucible',
        action = function()
            if state.get('step') == 'filledCrucibleAfterFailedPick' then
                state.set('step', 'haveCrucibleCheckTongs')
                send('get tongs')
            end
        end,
    },
    -- Already carrying tongs
    {
        match = 'You are already carring a pair of iron tongs',
        action = function()
            if state.get('step') == 'haveCrucibleCheckTongs' then
                state.set('step', 'activelyHeating')
                send('heat cruc over iron furnace')
            end
        end,
    },
    -- Dropped crucible
    {
        match = 'You drop a crucible',
        action = function()
            local step = state.get('step')
            if step == 'haveCrucible' then
                state.set('step', 'droppedCrucible')
                send('get broken')
            end
            if step == 'successfulPick' then
                state.set('step', 'droppedCrucible')
            end
        end,
    },
    -- Got broken wire
    {
        match = 'You take a broken thin length',
        action = function()
            if state.get('step') == 'droppedCrucible' then
                state.set('step', 'filledCrucible')
                send('put broken in crucible')
            end
        end,
    },
    -- Put broken wire in crucible
    {
        match = 'You put a broken thin length',
        action = function()
            if state.get('step') == 'filledCrucible' then
                state.set('step', 'readyToHeat')
                send('get crucible')
            end
        end,
    },
    -- Unbusy: continue current step
    {
        match = strings.unbusy,
        action = function()
            local step = state.get('step')
            if step == 'activelyHeating' then
                send('heat cruc over iron furnace')
            end
            if step == 'timeToPour' then
                send('forge tool with cruc and mold')
            end
            if step == 'droppedCrucible' then
                send('get broken')
            end
        end,
    },
    -- Metal is molten
    {
        match = {'all that remains is some molten metal', 'The metal is already molten'},
        action = function()
            state.set('step', 'timeToPour')
        end,
    },
    -- Successful pick
    {
        match = 'After a short while, you crack the clay open',
        action = function()
            state.set('step', 'successfulPick')
            send('drop crucible')
        end,
    },
    -- Failed pick: lump falls out
    {
        match = 'A lump of unformed metal falls out',
        action = function()
            state.set('step', 'failedPick')
            state.set('deferred_cmd', 'put lump in crucible')
        end,
    },
    -- Put lump in crucible
    {
        match = 'You put a tiny lump',
        action = function()
            if state.get('step') == 'failedPick' then
                state.set('step', 'filledCrucibleAfterFailedPick')
                send('get crucible')
            end
        end,
    },
}

return M
