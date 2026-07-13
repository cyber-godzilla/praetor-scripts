--[[
Variation of macro.lua which is specific to chainblade.
Uses nomind every 30 seconds, but typical rotation otherwise.
]]
local strings = require('lib_strings')
local chain_strings = require('lib_chain_macro')
local combat = require('lib_combat')

local M = {}

local default_actions = {'at1', 'at2', 'at3', 'at4', 'at5', 'at6', 'at7'}

local function chain_attack()
    local now = time.now()
    local last_nm = state.get('last_nomind') or 0
    if time.since(last_nm) > 30000 then
        state.set('last_nomind', now)
        send('nm')
        state.set('last_command_time', now)
        return
    end
    combat.attack()
end

function M.on_start(args)
    state.set('do_kill', true)
    state.set('approached', true)
    state.set('target_ko', false)
    state.set('last_nomind', 0)
    state.set('winding_up', false)

    local actions = {}
    for _, v in ipairs(default_actions) do actions[#actions + 1] = v end
    state.set('actions_list', actions)

    for _, arg in ipairs(args) do
        if arg == 'nokill' then state.set('do_kill', false) end
    end

    metrics.track('kills', 'Kills')
    metrics.track('crits', 'Crits')
    metrics.track('actions', 'Actions')

    log('Chain macro mode started')
    combat.start_watchdog(chain_attack)
end

function M.on_stop()
    combat.stop_watchdog()
end

M.reactions = {
    -- Success roll: dispatch kill/KO/rotate via combat handler
    {
        match = strings.success,
        action = function(text)
            if combat.handle_success(text, chain_attack) then return end
            if state.get('winding_up') then
                state.set('winding_up', false)
                chain_attack()
                return
            end
            metrics.inc('actions')
        end,
    },
    -- Chainblade windup
    {
        match = chain_strings.chainblade_windup,
        action = function()
            state.set('winding_up', true)
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
            local deferred = state.get('deferred_cmd')
            if deferred then
                send(deferred)
                state.set('deferred_cmd', nil)
                return
            end
            if combat.try_kill() then return end
            chain_attack()
        end,
    },
    -- Falls unconscious (backup)
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
            chain_attack()
        end,
    },
    -- Arrival
    {
        match = combat.arrival,
        action = function() combat.approach() end,
    },
    -- Kill strings (backup)
    {
        match = combat.kill,
        action = function() combat.on_kill() end,
    },
    -- Approached
    {
        match = combat.approached,
        action = function()
            state.set('approached', true)
            chain_attack()
        end,
    },
    -- Already engaging: attack
    {
        match = 'You are already engaging',
        action = function() chain_attack() end,
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
