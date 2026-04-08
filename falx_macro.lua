--[[
A variation of macro.lua which is specific to falx.
Every 6 moves, attempts to stun the opponent.
On a successful stun, attempts ankle drag.
On a successful ankle drag, repeats eviscerate until the opponent stands.
Requires:
- at1-6 macros
- st1 macro
- dr macro
- ev macro
]]
local strings = require('lib_strings')
local falx_strings = require('lib_falx_macro')
local combat = require('lib_combat')

local M = {}

local default_actions = {'at1', 'at2', 'at3', 'at4', 'at5', 'at6'}

local function exit_submode()
    state.set('falx_submode', nil)
    state.set('falx_cooldown', 6)
    state.set('falx_stun_rolled', false)
end

local function falx_attack()
    if state.get('falx_submode') then return end
    local cd = state.get('falx_cooldown') or 0
    if cd > 0 then
        state.set('falx_cooldown', cd - 1)
        combat.attack()
        return
    end
    state.set('falx_submode', 'stunSent')
    send('st1')
    state.set('last_command_time', time.now())
end

function M.on_start(args)
    state.set('do_kill', true)
    state.set('approached', true)
    state.set('target_ko', false)
    state.set('falx_submode', nil)
    state.set('falx_cooldown', 0)
    state.set('falx_stun_rolled', false)

    local actions = {}
    for _, v in ipairs(default_actions) do actions[#actions + 1] = v end
    state.set('actions_list', actions)

    for _, arg in ipairs(args) do
        if arg == 'nokill' then state.set('do_kill', false) end
    end

    metrics.track('kills', 'Kills')
    metrics.track('crits', 'Crits')
    metrics.track('actions', 'Actions')

    log('Falx macro mode started')
end

M.reactions = {
    -- Stun roll detection: check if stun also HIT in the same text.
    -- The game may send stun roll + stun hit in the same line or separate lines.
    {
        match = falx_strings.falx_stun_roll,
        action = function(text)
            if state.get('falx_submode') == 'stunSent' then
                if combat.text_matches(text, falx_strings.falx_stun) then
                    state.set('falx_submode', 'stunHit')
                else
                    state.set('falx_stun_rolled', true)
                end
            end
        end,
    },
    -- Stun hit on a separate line (if not already caught by stun roll handler)
    {
        match = falx_strings.falx_stun,
        action = function()
            if state.get('falx_submode') == 'stunSent' then
                state.set('falx_submode', 'stunHit')
            end
        end,
    },
    -- Fall detection for drag
    {
        match = falx_strings.falx_fall,
        action = function()
            if state.get('falx_submode') == 'dragSent' then
                state.set('falx_submode', 'dragHit')
            end
        end,
    },
    -- Drag fail: target must be standing (not the player — that's must_stand)
    {
        match = falx_strings.falx_drag_fail,
        action = function(text)
            -- Skip if this is about the player, not the target.
            if text and text:find('You must be standing', 1, true) then
                -- Fall through to must_stand handler on next line won't work
                -- (first-match-wins), so handle it here directly.
                if state.get('falx_submode') then exit_submode() end
                send('stand')
                return
            end
            if state.get('falx_submode') == 'dragSent' then
                state.set('falx_submode', 'ev')
                send('ev')
            end
        end,
    },
    -- Success roll: dispatch kill/KO/rotate via combat handler.
    -- Also handles 'falls unconscious' within [Success:] text.
    {
        match = '[Success:',
        action = function(text)
            if combat.handle_success(text, falx_attack) then
                if state.get('falx_submode') then exit_submode() end
                return
            end
            metrics.inc('actions')
        end,
    },
    -- Evict exit conditions (stands up, prone target, launched)
    {
        match = falx_strings.falx_ev_exit,
        action = function(text)
            if state.get('falx_submode') then
                exit_submode()
            end
            if text and text:find('falls unconscious', 1, true) then
                combat.on_ko()
            else
                -- Always resume attacking after ev exit, even if submode
                -- was already cleared (e.g., duplicate ev responses).
                falx_attack()
            end
        end,
    },
    -- Must stand
    {
        match = strings.must_stand,
        action = function()
            if state.get('falx_submode') then exit_submode() end
            send('stand')
        end,
    },
    -- Unbusy: state machine transitions
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
            local sub = state.get('falx_submode')
            if sub == 'stunHit' then
                state.set('falx_submode', 'dragSent')
                send('dr')
                return
            end
            if sub == 'stunSent' then
                if state.get('falx_stun_rolled') then
                    exit_submode()
                    falx_attack()
                else
                    send('st1')
                end
                return
            end
            if sub == 'dragHit' then
                state.set('falx_submode', 'ev')
                send('ev')
                return
            end
            if sub == 'dragSent' then
                exit_submode()
                falx_attack()
                return
            end
            if sub == 'ev' then
                send('ev')
                return
            end
            falx_attack()
        end,
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
            falx_attack()
        end,
    },
    -- Arrival
    {
        match = combat.arrival,
        action = function() combat.approach() end,
    },
    -- Kill strings (backup: also caught by [Success:] handler)
    {
        match = combat.kill,
        action = function() combat.on_kill() end,
    },
    -- Approached
    {
        match = combat.approached,
        action = function()
            state.set('approached', true)
            falx_attack()
        end,
    },
    -- Already engaging: attack
    {
        match = 'You are already engaging',
        action = function() falx_attack() end,
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
