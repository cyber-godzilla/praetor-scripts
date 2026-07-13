--[[
Priority-aware combat macro with automatic target selection via 'ac .'.
/mode priority_macro [target1 target2 ...] [fallback:macro] [nokill]

Modes:
  With priority targets: scans room via ac, focuses highest-priority match,
    falls back to fallback:macro when no priority target is present.
  Fallback only (/mode priority_macro fallback:kel): fights current target,
    runs macro when no targets remain.
  No args: passthrough, behaves identically to macro mode.

Named params (colon syntax):
  fallback:kel    -- macro name to run when no priority targets are found

Priority targets are matched by substring against the full mob name.
  /mode priority_macro warrior servitor fallback:kel
    → targets warrior first, servitor second, falls back to 'kel' macro
]]
local strings = require('lib_strings')
local combat = require('lib_combat')

local M = {}

local function parse_args(args)
    local config = { priorities = {}, fallback = nil, nokill = false }
    for _, arg in ipairs(args) do
        local key, val = arg:match('^(.-):(.+)$')
        if key == 'fallback' then
            config.fallback = val
        elseif arg == 'nokill' then
            config.nokill = true
        else
            config.priorities[#config.priorities + 1] = arg:lower()
        end
    end
    return config
end

-- Guarded attack: skip if AC request is in flight (preempt other commands during AC)
local function attack()
    if state.get('ac_collecting') and not state.get('ac_header_received') then
        log('[pm] attack skipped: ac in flight')
        return
    end
    combat.attack()
end

local function send_ac()
    -- Dedup: don't send another ac if we're still waiting on prior response
    if state.get('ac_collecting') and not state.get('ac_header_received') then
        log('[pm] send_ac: skipped (ac already in flight)')
        return
    end
    log('[pm] send_ac: resetting candidates, sending ac .')
    state.set('ac_collecting', true)
    state.set('ac_header_received', false)
    state.set('next_target', nil)
    state.set('next_priority', 999)
    state.set('next_is_uco', false)
    state.set('ac_uco_count', 0)  -- reset count of unconscious mobs this scan
    state.set('last_command_time', time.now())  -- reset watchdog stall timer
    send('ac .', 0)
end

local function find_priority(name)
    local targets = state.get('priority_targets') or {}
    local lower = name:lower()
    for i, kw in ipairs(targets) do
        if lower:find(kw, 1, true) then
            return i, kw
        end
    end
    return nil, nil
end

local function update_ac_candidate(text)
    local num_str, rest = text:match('^(%d+): (.+)$')
    if not num_str then
        log('[pm] ac_line: no match on: |' .. text .. '|')
        return
    end
    -- Skip non-mob entries (player characters lack "a/an/the" article prefix)
    local lower_rest = rest:lower()
    if not (lower_rest:find('^a ') or lower_rest:find('^an ') or lower_rest:find('^the ')) then
        log('[pm] ac_line: skipping non-mob entry ' .. num_str .. ': ' .. rest)
        return
    end

    local flags = {}
    local name = rest:gsub('%s*%((%w+)%)', function(f)
        flags[f:lower()] = true
        return ''
    end):match('^(.-)%s*$')

    local flag_str = ''
    for f in pairs(flags) do flag_str = flag_str .. '(' .. f .. ') ' end
    log('[pm] ac_line: entry=' .. num_str .. ' name="' .. name .. '" flags=' .. flag_str)

    local is_uco = flags['unconscious'] == true
    -- Track total unconscious count for fallback k1 queueing
    if is_uco then
        state.set('ac_uco_count', (state.get('ac_uco_count') or 0) + 1)
    end
    local pri, kw = find_priority(name)
    if not pri then
        log('[pm] ac_line: no priority match for "' .. name .. '"')
        return
    end

    log('[pm] ac_line: priority match kw="' .. kw .. '" pri=' .. pri .. ' uco=' .. tostring(is_uco))

    local next_is_uco = state.get('next_is_uco')
    local next_pri = state.get('next_priority')

    if is_uco then
        if not next_is_uco or pri < next_pri then
            log('[pm] ac_line: new best (unconscious) -> ' .. kw)
            state.set('next_target', kw)
            state.set('next_priority', pri)
            state.set('next_is_uco', true)
        else
            log('[pm] ac_line: unconscious candidate ignored, already have uco pri=' .. tostring(next_pri))
        end
        return
    end

    if next_is_uco then
        log('[pm] ac_line: skipping ' .. kw .. ', already have unconscious candidate')
        return
    end

    if pri < next_pri then
        log('[pm] ac_line: new best -> ' .. kw .. ' pri=' .. pri)
        state.set('next_target', kw)
        state.set('next_priority', pri)
    else
        log('[pm] ac_line: ' .. kw .. ' pri=' .. pri .. ' not better than current best pri=' .. tostring(next_pri))
    end
end

local function run_fallback()
    local fb = state.get('fallback_macro')
    if not fb then
        log('[pm] run_fallback: no fallback macro set')
        return
    end
    -- Skip if already using fallback (game's @mtarg is still set from last send)
    if state.get('using_fallback') then
        log('[pm] run_fallback: skipped (already using fallback)')
        state.set('fallback_rotation_count', 0)
        return
    end
    log('[pm] run_fallback: sending ' .. fb)
    send(fb)
    state.set('using_fallback', true)
    state.set('current_target', nil)
    state.set('fallback_rotation_count', 0)
end

local function commit_ac()
    state.set('ac_collecting', false)
    local next_kw = state.get('next_target')
    local next_is_uco = state.get('next_is_uco')
    local current_kw = state.get('current_target')

    log('[pm] commit_ac: next_target=' .. tostring(next_kw) .. ' next_is_uco=' .. tostring(next_is_uco) .. ' current=' .. tostring(current_kw))

    state.set('next_target', nil)
    state.set('next_is_uco', false)

    if next_kw then
        if next_kw ~= current_kw then
            log('[pm] commit_ac: switching -> @mtarg ' .. next_kw)
            send('@mtarg ' .. next_kw)
            state.set('current_target', next_kw)
            state.set('using_fallback', false)
            -- Clear stale KO from previous target unless new target is uco
            if not next_is_uco then
                state.set('target_ko', false)
            end
        else
            log('[pm] commit_ac: already on ' .. next_kw .. ', no switch needed')
        end
        if next_is_uco and state.get('do_kill') then
            log('[pm] commit_ac: arming kill for unconscious target')
            state.set('target_ko', true)
        end
        return
    end

    log('[pm] commit_ac: no priority target found')
    if state.get('fallback_macro') then
        run_fallback()
        -- Queue one k1 per unconscious mob seen in this scan
        local uco_count = state.get('ac_uco_count') or 0
        if uco_count > 0 then
            state.set('pending_kills', uco_count)
            state.set('target_ko', false)  -- pending_kills supersedes try_kill to avoid double k1
            log('[pm] commit_ac: queued ' .. uco_count .. ' k1 for unconscious mobs')
        end
    end
end

function M.on_start(args)
    local config = parse_args(args)
    local has_priorities = #config.priorities > 0
    local use_ac = has_priorities or config.fallback ~= nil

    state.set('do_kill', not config.nokill)
    state.set('approached', true)
    state.set('target_ko', false)
    state.set('priority_targets', config.priorities)
    state.set('fallback_macro', config.fallback)
    state.set('current_target', nil)
    state.set('using_fallback', false)
    state.set('ac_collecting', false)
    state.set('fallback_rotation_count', 0)
    state.set('pending_kills', 0)
    state.set('ac_uco_count', 0)
    state.set('use_ac', use_ac)

    local actions = {'at1', 'at2', 'at3', 'at4', 'at5', 'at6'}
    state.set('actions_list', actions)

    metrics.track('kills', 'Kills')
    metrics.track('crits', 'Crits')
    metrics.track('actions', 'Actions')

    local pri_str = table.concat(config.priorities, ', ')
    local mode_label = has_priorities and '1-priority' or (config.fallback and '2-fallback' or '3-passthrough')
    log('[pm] on_start: mode=' .. mode_label .. ' priorities=[' .. pri_str .. '] fallback=' .. tostring(config.fallback) .. ' nokill=' .. tostring(config.nokill))

    if has_priorities then send_ac() end

    combat.start_watchdog(function()
        log('[pm] watchdog: fired, ac_collecting=' .. tostring(state.get('ac_collecting')) .. ' ac_header_received=' .. tostring(state.get('ac_header_received')))
        if state.get('ac_collecting') and state.get('ac_header_received') then
            commit_ac()
        elseif state.get('ac_collecting') then
            log('[pm] watchdog: ac response never arrived, clearing and retrying')
            state.set('ac_collecting', false)
            if #(state.get('priority_targets') or {}) > 0 then
                send_ac()
                return  -- let retry AC come back before next attack
            end
        end
        -- Recovery: if no current target, no fallback, and priorities configured, trigger AC
        if state.get('use_ac')
           and #(state.get('priority_targets') or {}) > 0
           and not state.get('current_target')
           and not state.get('using_fallback')
           and not state.get('ac_collecting') then
            log('[pm] watchdog: no target & no fallback, triggering ac')
            send_ac()
            return
        end
        if combat.try_kill() then return end
        attack()
    end)
end

function M.on_stop()
    combat.stop_watchdog()
    local priorities = state.get('priority_targets') or {}
    if #priorities > 0 then
        local restore = '@mtarg ' .. table.concat(priorities, '|')
        log('[pm] on_stop: restoring targets: ' .. restore)
        send(restore)
    else
        log('[pm] on_stop: no priorities to restore')
    end
end

M.reactions = {
    -- AC header: begin collection (gated to avoid spurious resets in passthrough)
    {
        match = 'Checking the approach status of "."',
        condition = function() return state.get('use_ac') == true end,
        action = function()
            log('[pm] ac_header: starting collection')
            state.set('ac_collecting', true)
            state.set('ac_header_received', true)
            state.set('next_target', nil)
            state.set('next_priority', 999)
            state.set('next_is_uco', false)
            state.set('ac_uco_count', 0)
        end,
    },
    -- Success roll: must come before AC list item patterns ('?:*' matches '[Success:')
    {
        match = strings.success,
        action = function(text)
            -- AC commit safety net: if header arrived but no unbusy yet, commit here
            if state.get('ac_collecting') and state.get('ac_header_received') then
                log('[pm] success: committing pending ac')
                commit_ac()
            end
            if combat.handle_success(text, attack) then
                -- handle_success returned true = kill or KO detected
                -- Detect kill specifically (vs KO) and trigger AC rescan for priority modes
                if combat.text_matches(text, combat.kill) then
                    log('[pm] success-kill: current_target=' .. tostring(state.get('current_target')))
                    state.set('current_target', nil)
                    -- Keep using_fallback intact: commit_ac will switch or run_fallback no-ops
                    if state.get('use_ac') and #(state.get('priority_targets') or {}) > 0 then
                        log('[pm] success-kill: rescanning via ac')
                        send_ac()
                    end
                end
                return
            end
            metrics.inc('actions')
        end,
    },
    -- AC list items: "N: Name [(flag)]" format
    {
        match = '?:*',
        condition = function() return state.get('ac_collecting') == true end,
        action = function(text) update_ac_candidate(text) end,
    },
    {
        match = '??:*',
        condition = function() return state.get('ac_collecting') == true end,
        action = function(text) update_ac_candidate(text) end,
    },
    -- Must stand
    {
        match = strings.must_stand,
        action = function() send('stand') end,
    },
    -- Unbusy: commit AC if pending, then kill or attack
    {
        match = strings.unbusy,
        action = function()
            metrics.inc('actions')
            local deferred = state.get('deferred_cmd')
            if deferred then
                log('[pm] unbusy: sending deferred: ' .. deferred)
                send(deferred)
                state.set('deferred_cmd', nil)
                return
            end
            if state.get('ac_collecting') then
                if state.get('ac_header_received') then
                    log('[pm] unbusy: ac response received, committing')
                    commit_ac()
                else
                    log('[pm] unbusy: ac sent but response not yet received, skipping commit')
                end
            end
            -- Drain pending k1s queued from fallback AC scan (one per unbusy)
            local pending = state.get('pending_kills') or 0
            if pending > 0 then
                log('[pm] unbusy: draining pending k1 (' .. pending .. ' remaining)')
                send('k1')
                state.set('pending_kills', pending - 1)
                return
            end
            if state.get('using_fallback') and #(state.get('priority_targets') or {}) > 0 then
                -- On fallback with priority targets: rescan once per full rotation
                local count = (state.get('fallback_rotation_count') or 0) + 1
                local actions = state.get('actions_list') or {}
                if count >= #actions then
                    log('[pm] unbusy: fallback rotation complete, rescanning for priorities')
                    state.set('fallback_rotation_count', 0)
                    send_ac()
                else
                    state.set('fallback_rotation_count', count)
                end
            end
            if combat.try_kill() then
                log('[pm] unbusy: try_kill fired')
                return
            end
            log('[pm] unbusy: attacking, current_target=' .. tostring(state.get('current_target')))
            attack()
        end,
    },
    -- KO: arm k1 only when KO'd mob matches our current targeting
    {
        match = 'falls unconscious',
        action = function(text)
            local lower = text:lower()
            local current = state.get('current_target')
            -- Priority mode: only arm k1 if KO'd mob matches current priority
            if current then
                if lower:find(current, 1, true) then
                    log('[pm] ko: current priority target (' .. current .. ') down, arming k1')
                    combat.on_ko()
                else
                    log('[pm] ko: non-priority mob down, k1 suppressed (current=' .. current .. ')')
                    notify('Priority Macro', 'Non-priority target unconscious')
                end
                return
            end
            -- Fallback or passthrough mode: let existing k1 mechanism handle it
            log('[pm] ko: no current priority, arming k1 (fallback/passthrough)')
            combat.on_ko()
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
    -- Can't find opening: advance target index
    {
        match = "You can't find an opening",
        action = function()
            state.set('target_count', (state.get('target_count') or 1) + 1)
            attack()
        end,
    },
    -- Arrival: just approach (no AC rescan - triggered only by kill/no_targets)
    {
        match = combat.arrival,
        action = function() combat.approach() end,
    },
    -- Kill: re-scan for next priority target
    {
        match = combat.kill,
        action = function()
            log('[pm] kill: current_target=' .. tostring(state.get('current_target')))
            combat.on_kill()
            state.set('current_target', nil)
            state.set('using_fallback', false)
            if state.get('use_ac') and #(state.get('priority_targets') or {}) > 0 then
                log('[pm] kill: rescanning via ac')
                send_ac()
            end
        end,
    },
    -- Approached
    {
        match = combat.approached,
        action = function()
            log('[pm] approached')
            state.set('approached', true)
            attack()
        end,
    },
    -- Already engaging
    {
        match = 'You are already engaging',
        action = function()
            log('[pm] already engaging, attacking')
            attack()
        end,
    },
    -- No targets: re-scan (mode 1) or run fallback (mode 2)
    {
        match = combat.no_targets,
        action = function(text)
            local lower = text:lower()
            -- Filter "You can't X the corpse of Y" (failed attack on dead mob, not no-targets)
            if lower:find("the corpse of", 1, true) then
                log('[pm] no_targets: ignoring corpse reference: ' .. text)
                state.set('target_ko', false)
                return
            end
            -- Filter k1 failures
            if lower:find("you can't break", 1, true) or lower:find("you can't kill", 1, true) then
                log('[pm] no_targets: ignoring k1 failure: ' .. text)
                state.set('target_ko', false)
                return
            end
            -- If we're still on a priority target, ignore remaining "can't" false positives
            if state.get('current_target') and not state.get('using_fallback') then
                log('[pm] no_targets: ignoring, still on current_target=' .. state.get('current_target'))
                state.set('target_ko', false)
                return
            end
            log('[pm] no_targets: use_ac=' .. tostring(state.get('use_ac')))
            state.set('target_ko', false)
            state.set('approached', false)
            state.set('current_target', nil)
            if state.get('use_ac') then
                if #(state.get('priority_targets') or {}) > 0 then
                    log('[pm] no_targets: rescanning via ac')
                    send_ac()
                else
                    log('[pm] no_targets: running fallback')
                    run_fallback()
                    attack()
                end
            end
        end,
    },
    -- Wrong stance
    {
        match = {'You are not in the correct stance', 'You must be in'},
        action = function() send('doStance') end,
    },
    -- Not close enough
    {
        match = combat.not_close_enough,
        action = function() send('adv1', 0) end,
    },
}

return M
