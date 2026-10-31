--[[
Shared mechanics for the four bulk locksmithing modes.

Nothing about the batch is inferred from character variables or hard-coded
containers. Every run names its targets, and workflows that move containers
also name their source and both dispositions.

  /mode unlock_all targets:chest|coffer from:wagon done:"large sack" reject:"worn sack" open:true stow:neckpouch
  /mode unlock_toss targets:chest|coffer from:here done:n reject:s open:false
  /mode unlock_floor_pass targets:chest|coffer|trunk
  /mode unlock_floor_each targets:chest|coffer|trunk

For unlock_all, `here` means the floor; other destinations are containers.
For unlock_toss, the two destinations are directions.

Unjam policy (shared by every workflow): Success <= 50 gives up after five
worsening results; Success 51-99 gives up after two; Success 100 gives up
immediately. Ordinary unlock failures retry unless Success is 100.
]]
local strings = require('lib_strings')
local after = require('lib_after')

local B = {}

local targets = {}
local moving_workflows = {carry = true, toss = true}
local floor_workflows = {floor_pass = true, floor_each = true}
local workflow_names = {
    carry = 'unlock_all',
    toss = 'unlock_toss',
    floor_pass = 'unlock_floor_pass',
    floor_each = 'unlock_floor_each',
}
local directions = {
    n = true, s = true, e = true, w = true,
    ne = true, nw = true, se = true, sw = true,
    up = true, down = true, u = true, d = true,
}

local function split_targets(value)
    local result = {}
    for target in value:gmatch('[^|]+') do result[#result + 1] = target end
    return result
end

local function parse_bool(key, value)
    if value == 'true' then return true end
    if value == 'false' then return false end
    return nil, key .. ': needs true or false'
end

local function parse_args(workflow, args)
    local allowed = floor_workflows[workflow]
        and {targets = true}
        or {targets = true, from = true, done = true, reject = true, open = true, stow = true}
    local values = {}

    for _, arg in ipairs(args) do
        local key, value = arg:match('^(.-):(.*)$')
        if not key then return nil, 'expected a named argument, got "' .. arg .. '"' end
        if not allowed[key] then return nil, 'unknown option "' .. key .. ':"' end
        if value == '' then return nil, key .. ': needs a value' end
        if values[key] ~= nil then return nil, key .. ': specified more than once' end
        values[key] = value
    end

    if not values.targets then return nil, 'targets: is required' end
    local parsed_targets = split_targets(values.targets)
    if #parsed_targets == 0 then return nil, 'requires at least one container type' end

    local config = {workflow = workflow, targets = parsed_targets}
    if floor_workflows[workflow] then
        return config
    end

    for _, key in ipairs({'from', 'done', 'reject', 'open'}) do
        if not values[key] then return nil, key .. ': is required' end
    end
    local open, err = parse_bool('open', values.open)
    if err then return nil, err end
    if open and not values.stow then return nil, 'stow: is required when open:true' end
    if not open and values.stow then return nil, 'stow: only applies when open:true' end

    local done, reject
    if workflow == 'carry' then
        done = values.done == 'here' and {kind = 'drop'} or {kind = 'put', target = values.done}
        reject = values.reject == 'here' and {kind = 'drop'} or {kind = 'put', target = values.reject}
    else
        if not directions[values.done] then return nil, 'unknown successful toss direction "' .. values.done .. '"' end
        if not directions[values.reject] then return nil, 'unknown rejected toss direction "' .. values.reject .. '"' end
        done = {kind = 'toss', target = values.done}
        reject = {kind = 'toss', target = values.reject}
    end

    config.from = values.from
    config.done = done
    config.reject = reject
    config.open = open
    config.stow = values.stow
    return config
end

local function current_target() return targets[state.get('target_index')] end
local function floor_ref() return state.get('item_index') .. ' ' .. current_target() end

local function reset_attempt()
    state.set('unjam_difficulty', nil)
    state.set('worsened', 0)
end

local function worsening_limit(difficulty)
    if difficulty <= 50 then return 5 end
    return 2
end

local function abort(message)
    local name = workflow_names[state.get('workflow')] or 'locksmithing'
    log(name .. ': ' .. message)
    notify('Cannot proceed', name .. ' stopped: ' .. message)
    set_mode('disable')
end

local function finish()
    local completed = state.get('completed') or 0
    local skipped = state.get('skipped') or 0
    local name = workflow_names[state.get('workflow')] or 'locksmithing'
    notify('Completed', name .. ' finished: ' .. completed .. ' unlocked, ' .. skipped .. ' skipped')
    after.finish()
end

local function command_for_destination(destination)
    local target = current_target()
    if destination.kind == 'drop' then return 'drop ' .. target end
    if destination.kind == 'put' then return 'put ' .. target .. ' in ' .. destination.target end
    return 'toss ' .. target .. ' ' .. destination.target
end

local function send_take()
    reset_attempt()
    state.set('phase', 'take')
    if state.get('from') == 'here' then send('get ' .. current_target())
    else send('get ' .. current_target() .. ' from ' .. state.get('from')) end
end

local function send_carry_unlock()
    state.set('phase', 'carry_unlock_busy')
    send('unlock ' .. current_target() .. ' with lockpick')
end

local function send_carry_unjam()
    state.set('phase', 'carry_unjam_busy')
    send('unjam ' .. current_target() .. ' with lockpick')
end

local function send_open()
    state.set('phase', 'opening')
    send('open ' .. current_target())
end

local function send_disposition(which)
    state.set('phase', 'disposing_' .. which)
    send(command_for_destination(state.get(which)))
end

local function next_carried_container()
    if state.get('pick_stowed') then
        state.set('phase', 'pick_for_next')
        send('get my lockpick')
    else
        send_take()
    end
end

local function mark_carried(which)
    if which == 'done' then state.set('completed', state.get('completed') + 1)
    else state.set('skipped', state.get('skipped') + 1) end
    next_carried_container()
end

local send_floor_action

local function start_floor_pass(pass)
    state.set('pass', pass)
    state.set('target_index', 1)
    state.set('item_index', 1)
    reset_attempt()
    send_floor_action()
end

local function floor_next_target_or_finish()
    local next_target = state.get('target_index') + 1
    if next_target <= #targets then
        state.set('target_index', next_target)
        state.set('item_index', 1)
        reset_attempt()
        send_floor_action()
        return
    end
    if state.get('workflow') == 'floor_pass' and state.get('pass') == 'unjam' then
        start_floor_pass('unlock')
    else
        finish()
    end
end

local function floor_advance(skipped)
    if skipped then state.set('skipped', state.get('skipped') + 1)
    elseif state.get('pass') == 'unlock' or state.get('workflow') == 'floor_each' then
        state.set('completed', state.get('completed') + 1)
    end
    state.set('item_index', state.get('item_index') + 1)
    reset_attempt()
    send_floor_action()
end

local function send_floor_unjam(repair)
    state.set('phase', repair and 'floor_repair_unjam_busy' or 'floor_unjam_busy')
    send('unjam ' .. floor_ref() .. ' with lockpick')
end

local function send_floor_unlock()
    state.set('phase', 'floor_unlock_busy')
    send('unlock ' .. floor_ref() .. ' with lockpick')
end

send_floor_action = function()
    if state.get('workflow') == 'floor_each' or state.get('pass') == 'unjam' then
        send_floor_unjam(false)
    else
        send_floor_unlock()
    end
end

local function resume_after_pick(phase)
    if phase == 'carry_unlock_busy' then send_carry_unlock()
    elseif phase == 'carry_unjam_busy' then send_carry_unjam()
    elseif phase == 'floor_unlock_busy' then send_floor_unlock()
    elseif phase == 'floor_unjam_busy' then send_floor_unjam(false)
    elseif phase == 'floor_repair_unjam_busy' then send_floor_unjam(true)
    else abort('cannot resume after recovering the lockpick') end
end

local function on_start(workflow, args)
    args = after.parse(args)
    state.set('workflow', workflow)
    local config, err = parse_args(workflow, args)
    if not config then abort(err) return end

    targets = config.targets
    state.set('from', config.from)
    state.set('done', config.done)
    state.set('reject', config.reject)
    state.set('open', config.open)
    state.set('stow', config.stow)
    state.set('target_index', 1)
    state.set('item_index', 1)
    state.set('completed', 0)
    state.set('skipped', 0)
    state.set('pick_stowed', false)
    state.set('pass', config.workflow == 'floor_pass' and 'unjam' or 'each')
    reset_attempt()
    state.set('phase', 'pick_initial')
    send('get my lockpick')
end

local reactions = {
    {
        match = 'You feel an obstruction release',
        condition = function()
            local phase = state.get('phase')
            return phase == 'carry_unjam_busy' or phase == 'floor_unjam_busy' or
                phase == 'floor_repair_unjam_busy'
        end,
        action = function()
            local phase = state.get('phase')
            if phase == 'carry_unjam_busy' then state.set('phase', 'carry_unlock_wait')
            elseif phase == 'floor_repair_unjam_busy' or state.get('workflow') == 'floor_each' then
                state.set('phase', 'floor_unlock_wait')
            else state.set('phase', 'floor_advance_wait') end
        end,
    },
    {
        match = {'You hear a click as the tumbler mechanism releases',
            'You hear a click as a tumbler mechanism releases'},
        condition = function()
            local phase = state.get('phase')
            return phase == 'carry_unlock_busy' or phase == 'floor_unlock_busy'
        end,
        action = function()
            if state.get('phase') == 'carry_unlock_busy' then
                state.set('phase', state.get('open') and 'carry_open_wait' or 'carry_done_wait')
            else state.set('phase', 'floor_completed_wait') end
        end,
    },
    {
        match = 'You manage to jam the mechanism even more',
        condition = function()
            return (state.get('phase') or ''):find('unjam_busy', 1, true) ~= nil
        end,
        action = function() state.set('worsened', state.get('worsened') + 1) end,
    },
    {
        match = strings.success,
        condition = function()
            return (state.get('phase') or ''):find('unjam_busy', 1, true) ~= nil
        end,
        action = function(text)
            local difficulty = tonumber(text:match('%[Success:%s*(%d+)'))
            if not difficulty then return end
            state.set('unjam_difficulty', difficulty)
            if difficulty < 100 and state.get('worsened') < worsening_limit(difficulty) then return end
            if moving_workflows[state.get('workflow')] then state.set('phase', 'carry_reject_wait')
            else state.set('phase', 'floor_skipped_wait') end
        end,
    },
    {
        match = 'You are unable to get a tumbler mechanism to release',
        condition = function()
            local phase = state.get('phase')
            return phase == 'carry_unlock_busy' or phase == 'floor_unlock_busy'
        end,
        action = function(text)
            local difficulty = tonumber(text:match('%[Success:%s*(%d+)'))
            if not difficulty or difficulty < 100 then return end
            if state.get('phase') == 'carry_unlock_busy' then state.set('phase', 'carry_reject_wait')
            else state.set('phase', 'floor_skipped_wait') end
        end,
    },
    {
        match = 'This lock is jammed',
        condition = function()
            local phase = state.get('phase')
            return phase == 'carry_unlock_busy' or phase == 'floor_unlock_busy'
        end,
        action = function()
            reset_attempt()
            if state.get('phase') == 'carry_unlock_busy' then send_carry_unjam()
            else send_floor_unjam(true) end
        end,
    },
    {
        match = {'There is nothing jammed open.', 'It is already unjammed.'},
        condition = function()
            local phase = state.get('phase')
            return phase == 'carry_unjam_busy' or phase == 'floor_unjam_busy' or
                phase == 'floor_repair_unjam_busy'
        end,
        action = function()
            if state.get('phase') == 'carry_unjam_busy' then
                send_carry_unlock()
            elseif state.get('phase') == 'floor_repair_unjam_busy' or
                state.get('workflow') == 'floor_each' then
                send_floor_unlock()
            else floor_advance(false) end
        end,
    },
    {
        match = {'It is already unlocked.', 'It is already unlocked and open.'},
        condition = function()
            local phase = state.get('phase')
            return phase == 'carry_unlock_busy' or phase == 'floor_unlock_busy'
        end,
        action = function(text)
            if state.get('phase') == 'floor_unlock_busy' then floor_advance(false)
            elseif state.get('open') and not text:find('and open', 1, true) then send_open()
            else send_disposition('done') end
        end,
    },
    {
        match = 'It is already open.',
        condition = function() return state.get('phase') == 'opening' end,
        action = function() send_disposition('done') end,
    },
    {
        match = {'You take * lockpick', 'You are already carrying * lockpick'},
        condition = function()
            local phase = state.get('phase')
            return phase == 'pick_initial' or phase == 'pick_recover' or phase == 'pick_for_next'
        end,
        action = function()
            state.set('pick_stowed', false)
            local phase = state.get('phase')
            if phase == 'pick_recover' then
                local resume = state.get('resume_phase')
                state.set('resume_phase', nil)
                resume_after_pick(resume)
            elseif moving_workflows[state.get('workflow')] then send_take()
            else send_floor_action() end
        end,
    },
    {
        match = 'You must be holding * lockpick',
        action = function()
            state.set('resume_phase', state.get('phase'))
            state.set('phase', 'pick_recover')
            send('get my lockpick')
        end,
    },
    {
        match = "You don't see any lockpick",
        condition = function()
            local phase = state.get('phase')
            return phase ~= 'pick_initial' and phase ~= 'pick_recover' and phase ~= 'pick_for_next'
        end,
        action = function()
            state.set('resume_phase', state.get('phase'))
            state.set('phase', 'pick_recover')
            send('get my lockpick')
        end,
    },
    {
        match = 'You take',
        condition = function() return state.get('phase') == 'take' end,
        action = function() send_carry_unlock() end,
    },
    {
        match = 'Your hands must be empty',
        condition = function() return state.get('phase') == 'opening' end,
        action = function()
            state.set('phase', 'stowing_pick')
            send('put lockpick in ' .. state.get('stow'))
        end,
    },
    {
        match = 'You put',
        condition = function() return state.get('phase') == 'stowing_pick' end,
        action = function()
            state.set('pick_stowed', true)
            send_open()
        end,
    },
    {
        match = 'You open',
        condition = function() return state.get('phase') == 'opening' end,
        action = function() send_disposition('done') end,
    },
    {
        match = {'You drop', 'You put', 'You toss'},
        condition = function()
            local phase = state.get('phase')
            return phase == 'disposing_done' or phase == 'disposing_reject'
        end,
        action = function()
            if state.get('phase') == 'disposing_done' then mark_carried('done')
            else mark_carried('reject') end
        end,
    },
    {
        match = {"You don't see", "There aren't that many"},
        action = function(text)
            local phase = state.get('phase')
            if phase == 'pick_initial' or phase == 'pick_recover' or phase == 'pick_for_next' then
                if text:find('lockpick', 1, true) then abort('lockpick not found') end
                return
            end
            if phase == 'take' then
                if not text:find(current_target(), 1, true) then
                    abort('source not found while looking for ' .. current_target())
                    return
                end
                local next_target = state.get('target_index') + 1
                state.set('target_index', next_target)
                if next_target > #targets then finish() else send_take() end
                return
            end
            if phase == 'floor_unjam_busy' or phase == 'floor_unlock_busy' then
                if text:find(current_target(), 1, true) then
                    floor_next_target_or_finish()
                end
                return
            end
            if phase == 'stowing_pick' then
                abort('lockpick stow destination not found')
                return
            end
            if phase == 'disposing_done' or phase == 'disposing_reject' then
                abort('destination not found while holding ' .. current_target())
            end
        end,
    },
    {
        match = 'There is not enough room to put',
        condition = function()
            local phase = state.get('phase')
            return phase == 'stowing_pick' or phase == 'disposing_done' or
                phase == 'disposing_reject'
        end,
        action = function()
            if state.get('phase') == 'stowing_pick' then
                abort('lockpick stow destination is full')
            else
                abort('destination is full while holding ' .. current_target())
            end
        end,
    },
    {
        match = {'You do not have enough free hands', "You don't have enough free hands", 'You must remove'},
        action = function() abort('hands are full') end,
    },
    {
        match = strings.unbusy,
        action = function()
            local phase = state.get('phase')
            if phase == 'carry_unlock_busy' then send_carry_unlock()
            elseif phase == 'carry_unjam_busy' then send_carry_unjam()
            elseif phase == 'carry_unlock_wait' then send_carry_unlock()
            elseif phase == 'carry_open_wait' then send_open()
            elseif phase == 'carry_done_wait' then send_disposition('done')
            elseif phase == 'carry_reject_wait' then send_disposition('reject')
            elseif phase == 'floor_unjam_busy' then send_floor_unjam(false)
            elseif phase == 'floor_repair_unjam_busy' then send_floor_unjam(true)
            elseif phase == 'floor_unlock_busy' then send_floor_unlock()
            elseif phase == 'floor_unlock_wait' then send_floor_unlock()
            elseif phase == 'floor_advance_wait' then floor_advance(false)
            elseif phase == 'floor_completed_wait' then floor_advance(false)
            elseif phase == 'floor_skipped_wait' then floor_advance(true)
            end
        end,
    },
}

function B.mode(workflow, metadata)
    if not moving_workflows[workflow] and not floor_workflows[workflow] then
        error('unknown locksmith workflow: ' .. tostring(workflow))
    end
    return {
        usage = metadata.usage,
        desc = metadata.desc,
        chains = true,
        on_start = function(args) on_start(workflow, args) end,
        reactions = reactions,
    }
end

return B
