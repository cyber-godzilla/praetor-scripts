--[[
Custom version of macro.lua used for fighting in the bottom floor of the Aralex pits
Accepts one argument (direction), which is the direction it automatically tries to go after the spawned lizards are dead.
/mode lizard_macro n
]]
local strings = require('lib_strings')
local lizard_strings = require('lib_lizard_macro')
local combat = require('lib_combat')

local M = {}

local default_actions = {'at1', 'at2', 'at3', 'at4', 'at5', 'at6'}

function M.on_start(args)
    state.set('do_kill', true)
    state.set('approached', true)
    state.set('target_ko', false)
    state.set('direction', args[1] or nil)
    state.set('moving', false)

    local actions = {}
    for _, v in ipairs(default_actions) do actions[#actions + 1] = v end
    state.set('actions_list', actions)

    for _, arg in ipairs(args) do
        if arg == 'nokill' then state.set('do_kill', false) end
    end

    metrics.track('kills', 'Kills')
    metrics.track('crits', 'Crits')
    metrics.track('actions', 'Actions')

    log('Lizard macro mode started, direction: ' .. (args[1] or 'none'))

    if args[1] then
        state.set('moving', true)
        send(args[1])
    end
end

M.reactions = {
    -- Success roll: dispatch kill/KO/rotate via combat handler
    {
        match = '[Success:',
        action = function(text)
            if combat.handle_success(text) then return end
            metrics.inc('actions')
        end,
    },
    -- Must stand
    {
        match = strings.must_stand,
        action = function() send('stand') end,
    },
    -- Unbusy
    {
        match = strings.unbusy,
        action = function()
            metrics.inc('actions')
            if state.get('moving') then
                state.set('moving', false)
                return
            end
            local deferred = state.get('deferred_cmd')
            if deferred then
                send(deferred)
                state.set('deferred_cmd', nil)
                return
            end
            if combat.try_kill() then return end
            combat.attack()
        end,
    },
    -- Falls unconscious
    {
        match = 'falls unconscious',
        action = function() combat.on_ko() end,
    },
    -- Rewield
    {
        match = combat.rewield,
        action = function()
            state.set('deferred_cmd', 'r')
            send('r')
        end,
    },
    -- Can't find opening
    {
        match = "You can't find an opening",
        action = function()
            state.set("target_count", (state.get("target_count") or 1) + 1)
            combat.attack()
        end,
    },
    -- Arrival
    {
        match = combat.arrival,
        action = function() combat.approach() end,
    },
    -- Kill strings
    {
        match = combat.kill,
        action = function() combat.on_kill() end,
    },
    -- Approached
    {
        match = combat.approached,
        action = function()
            state.set('approached', true)
            combat.attack()
        end,
    },
    -- Already engaging: attack
    {
        match = 'You are already engaging',
        action = function() combat.attack() end,
    },
    -- Lizard dead: move to next area
    {
        match = lizard_strings.lizard_dead,
        action = function()
            state.set('target_ko', false)
            state.set('approached', false)
            local fatigue = status.fatigue
            if fatigue <= 0 then
                notify('Lizard Macro', 'Out of fatigue')
                set_mode('idle')
                return
            end
            if fatigue <= 10 then
                notify('Lizard Macro', 'Low fatigue: ' .. fatigue .. '%')
            end
            state.set('moving', true)
            local dir = state.get('direction')
            if dir then send(dir) end
        end,
    },
    -- No targets
    {
        match = combat.no_targets,
        action = function()
            state.set('target_ko', false)
            state.set('approached', false)
        end,
    },
    -- Wrong stance
    {
        match = {'You are not in the correct stance', 'You must be in'},
        action = function() send('doStance') end,
    },
    -- Not close enough: advance toward target
    {
        match = combat.not_close_enough,
        action = function() send('adv1', 0) end,
    },
}

return M
