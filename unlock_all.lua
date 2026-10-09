--[[
Unlock, open, and drop every matching container from a source container.
Containers whose locks are too difficult to unjam are moved to a reject
container instead.

Defaults match the usual sorting workflow:
  /mode unlock_all
  /mode unlock_all sack
  /mode unlock_all "2 sack"
  /mode unlock_all from:wagon reject:sack targets:chest|coffer|trunk
  /mode unlock_all from:"2 sack" reject:"worn large sack"

Options:
  <container>         -- positional source container
  from:<container>    -- source container (default: large sack)
  reject:<container>  -- destination for skipped containers (default: worn large sack)
  targets:<type>|<type>  -- ordered container nouns (default: chest|coffer|trunk)

Unjam policy:
  Success <= 50  -- give up after five "jam the mechanism even more" results
  Success 51-99  -- give up after two such results
  Success 100    -- give up immediately

Unlock failures are retried indefinitely unless Success is 100.
]]
local strings = require('lib_strings')
local after = require('lib_after')

local M = {}

M.usage = '[<source>|from:<container>] [reject:<container>] [targets:<type>|<type>...]'
M.desc = 'Unlock, open, and drop containers while setting difficult jams aside'
M.chains = true

local targets = {}

local function split_targets(value)
    local result = {}
    for target in value:gmatch('[^|]+') do
        result[#result + 1] = target
    end
    return result
end

local function parse_args(args)
    local config = {
        source = 'large sack',
        reject = 'worn large sack',
        targets = {'chest', 'coffer', 'trunk'},
    }
    local source_set = false

    for _, arg in ipairs(args) do
        local key, value = arg:match('^(.-):(.*)$')
        if not key then
            if source_set then
                return nil, 'source container specified more than once'
            end
            config.source = arg
            source_set = true
        elseif value == '' then
            return nil, key .. ': needs a value'
        elseif key == 'from' then
            if source_set then
                return nil, 'source container specified more than once'
            end
            config.source = value
            source_set = true
        elseif key == 'reject' then
            config.reject = value
        elseif key == 'targets' then
            config.targets = split_targets(value)
            if #config.targets == 0 then
                return nil, 'targets: needs at least one container type'
            end
        else
            return nil, 'unknown option "' .. arg .. '"'
        end
    end

    return config
end

local function current_target()
    return targets[state.get('target_index')]
end

local function finish()
    local completed = state.get('completed') or 0
    local skipped = state.get('skipped') or 0
    notify('Completed', 'unlock_all finished: ' .. completed .. ' opened, ' .. skipped .. ' skipped')
    after.finish()
end

local function abort(message)
    log('unlock_all: ' .. message)
    notify('Cannot proceed', 'unlock_all stopped: ' .. message)
    set_mode('disable')
end

local function reset_container()
    state.set('unjam_difficulty', nil)
    state.set('worsened', 0)
end

local function send_take()
    reset_container()
    state.set('phase', 'take')
    send('get ' .. current_target() .. ' from ' .. state.get('source'))
end

local function next_container()
    send_take()
end

local function next_target()
    local index = state.get('target_index') + 1
    state.set('target_index', index)
    if index > #targets then
        finish()
        return
    end
    send_take()
end

local function send_unlock()
    state.set('phase', 'unlock_busy')
    send('unlock ' .. current_target() .. ' with lockpick')
end

local function send_unjam()
    state.set('phase', 'unjam_busy')
    send('unjam ' .. current_target() .. ' with lockpick')
end

local function send_open()
    state.set('phase', 'opening')
    send('open ' .. current_target())
end

local function send_drop()
    state.set('phase', 'dropping')
    send('drop ' .. current_target())
end

local function send_reject()
    state.set('phase', 'rejecting')
    local reject = state.get('reject')
    if reject == 'here' then
        send('drop ' .. current_target())
    else
        send('put ' .. current_target() .. ' in ' .. reject)
    end
end

local function mark_completed()
    state.set('completed', state.get('completed') + 1)
    next_container()
end

local function mark_skipped()
    state.set('skipped', state.get('skipped') + 1)
    next_container()
end

local function worsening_limit(difficulty)
    if difficulty <= 50 then return 5 end
    return 2
end

function M.on_start(args)
    args = after.parse(args)
    local config, err = parse_args(args)
    if not config then
        abort(err)
        return
    end

    targets = config.targets
    state.set('source', config.source)
    state.set('reject', config.reject)
    state.set('target_index', 1)
    state.set('completed', 0)
    state.set('skipped', 0)
    reset_container()

    -- Keep the pick in hand for the whole batch. Taking it first leaves the
    -- other hand available for each container and makes hand failures obvious.
    state.set('phase', 'pick_initial')
    send('get my lockpick')
end

M.reactions = {
    -- These concrete successes must precede the generic [Success:] reaction:
    -- Praetor runs only the first matching reaction for each line.
    {
        match = 'You feel an obstruction release',
        condition = function()
            return state.get('phase') == 'unjam_busy'
        end,
        action = function()
            state.set('phase', 'unlock_wait')
        end,
    },
    {
        match = 'You hear a click as a tumbler mechanism releases',
        condition = function()
            return state.get('phase') == 'unlock_busy'
        end,
        action = function()
            state.set('phase', 'open_wait')
        end,
    },

    -- A failed ordinary unlock is harmless. Retry after roundtime unless the
    -- displayed difficulty is 100, which cannot succeed under this policy.
    {
        match = 'You are unable to get a tumbler mechanism to release',
        condition = function()
            return state.get('phase') == 'unlock_busy'
        end,
        action = function(text)
            local difficulty = tonumber(text:match('%[Success:%s*(%d+)'))
            if difficulty and difficulty >= 100 then
                state.set('phase', 'reject_wait')
            end
        end,
    },

    -- Unjam results all carry [Success:], including neutral and partial
    -- progress. The separate worsening line is counted before this line.
    {
        match = strings.success,
        condition = function()
            return state.get('phase') == 'unjam_busy'
        end,
        action = function(text)
            local difficulty = tonumber(text:match('%[Success:%s*(%d+)'))
            if not difficulty then return end
            state.set('unjam_difficulty', difficulty)

            if difficulty >= 100 or
                state.get('worsened') >= worsening_limit(difficulty) then
                state.set('phase', 'reject_wait')
            end
        end,
    },
    {
        match = 'You manage to jam the mechanism even more',
        condition = function()
            return state.get('phase') == 'unjam_busy'
        end,
        action = function()
            state.set('worsened', state.get('worsened') + 1)
        end,
    },

    -- The first unlock attempt reveals a jam without starting roundtime, so
    -- begin unjamming immediately.
    {
        match = 'This lock is jammed',
        condition = function()
            return state.get('phase') == 'unlock_busy'
        end,
        action = function()
            state.set('worsened', 0)
            state.set('unjam_difficulty', nil)
            send_unjam()
        end,
    },

    -- A redundant queued unjam can arrive after the real success. Treat it as
    -- an idempotent confirmation and continue instead of stalling.
    {
        match = 'There is nothing jammed open.',
        condition = function()
            local phase = state.get('phase')
            return phase == 'unjam_busy' or phase == 'unlock_wait'
        end,
        action = function()
            send_unlock()
        end,
    },

    -- Pre-existing completed states are safe to process.
    {
        match = {'It is already unlocked.', 'It is already unlocked and open.'},
        condition = function()
            return state.get('phase') == 'unlock_busy'
        end,
        action = function(text)
            if text:match('and open') then
                send_drop()
            else
                send_open()
            end
        end,
    },
    {
        match = 'It is already open.',
        condition = function()
            return state.get('phase') == 'opening'
        end,
        action = function()
            send_drop()
        end,
    },

    -- Obtain the pick once, before taking the first container. If a later
    -- command says it is missing, recover it while retaining the container.
    {
        match = {'You take * lockpick', 'You are already carrying * lockpick'},
        condition = function()
            local phase = state.get('phase')
            return phase == 'pick_initial' or phase == 'pick_for_container'
        end,
        action = function()
            if state.get('phase') == 'pick_initial' then
                send_take()
            else
                send_unlock()
            end
        end,
    },
    {
        match = 'You must be holding * lockpick',
        action = function()
            state.set('phase', 'pick_for_container')
            send('get my lockpick')
        end,
    },

    -- Container lifecycle: take, unlock/unjam, open, then drop.
    {
        match = 'You take',
        condition = function()
            return state.get('phase') == 'take'
        end,
        action = function()
            send_unlock()
        end,
    },
    {
        match = 'You open',
        condition = function()
            return state.get('phase') == 'opening'
        end,
        action = function()
            send_drop()
        end,
    },
    {
        match = 'You drop',
        condition = function()
            local phase = state.get('phase')
            return phase == 'dropping' or phase == 'rejecting'
        end,
        action = function()
            if state.get('phase') == 'dropping' then
                mark_completed()
            else
                mark_skipped()
            end
        end,
    },
    {
        match = 'You put',
        condition = function()
            return state.get('phase') == 'rejecting'
        end,
        action = function()
            mark_skipped()
        end,
    },

    -- Exhaust one actual noun before trying the next. Pipe-delimited values
    -- are configuration only and are never sent literally to the game.
    {
        match = {"You don't see", "There aren't that many"},
        action = function(text)
            local phase = state.get('phase')
            if phase == 'take' then
                if text:find(current_target(), 1, true) then
                    next_target()
                else
                    abort('source container not found')
                end
                return
            end
            if phase == 'pick_initial' or phase == 'pick_for_container' then
                abort('lockpick not found')
                return
            end
            if phase == 'rejecting' then
                abort('reject destination not found while holding ' .. current_target())
            end
        end,
    },
    {
        match = {'You do not have enough free hands', "You don't have enough free hands", 'You must remove'},
        action = function()
            abort('hands are full')
        end,
    },

    -- Every skill attempt with roundtime resumes from the state established
    -- by its result line. This prevents commands from being queued ahead.
    {
        match = strings.unbusy,
        action = function()
            local phase = state.get('phase')
            if phase == 'unlock_busy' then
                send_unlock()
            elseif phase == 'unjam_busy' then
                send_unjam()
            elseif phase == 'unlock_wait' then
                send_unlock()
            elseif phase == 'open_wait' then
                send_open()
            elseif phase == 'reject_wait' then
                send_reject()
            end
        end,
    },
}

return M
