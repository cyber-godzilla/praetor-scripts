--[[
The primary combat script most of this repo uses.
Simply rotates through 6 attacks one after another
]]
local strings = require('lib_strings')
local combat = require('lib_combat')

local M = {}

-- Set these macros on your character to a set of 
local default_actions = {'at1', 'at2', 'at3', 'at4', 'at5', 'at6'}

function M.on_start(args)
    state.set('do_kill', true)
    state.set('approached', true)
    state.set('target_ko', false)

    local actions = {}
    for _, v in ipairs(default_actions) do actions[#actions + 1] = v end
    state.set('actions_list', actions)

    for _, arg in ipairs(args) do
        if arg == 'nokill' then state.set('do_kill', false) end
    end

    metrics.track('kills', 'Kills')
    metrics.track('crits', 'Crits')
    metrics.track('actions', 'Actions')

    log('Macro mode started')
    combat.start_watchdog()
end

function M.on_stop()
    combat.stop_watchdog()
end

M.reactions = {
    -- Success roll: dispatch kill/KO/rotate via combat handler
    {
        match = strings.success,
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
    -- Unbusy: deferred command or ko check or attack
    {
        match = strings.unbusy,
        action = function()
            metrics.inc('actions')
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
    -- Falls unconscious (backup: also caught by [Success:] handler)
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
    -- Can't find opening: advance target
    {
        match = "You can't find an opening",
        action = function()
            state.set("target_count", (state.get("target_count") or 1) + 1)
            combat.attack()
        end,
    },
    -- Arrival: approach
    {
        match = combat.arrival,
        action = function() combat.approach() end,
    },
    -- Kill strings (backup: also caught by [Success:] handler)
    {
        match = combat.kill,
        action = function() combat.on_kill() end,
    },
    -- Approached strings
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
    -- No targets left
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
