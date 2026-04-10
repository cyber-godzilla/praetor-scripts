--[[
Batch-process locked/jammed containers using locksmithing skills.
All options use key:value format and have defaults, so bare /mode locksmith works.

Options:
  cont:chest|coffer|trunk    -- container types (pipe-delimited, game resolves)
  from:here                  -- source: here (ground) or container name
  to:here                    -- disposition: here, direction, or container name
  stow:my neckpouch|sack|backpack|satchel -- where to stow lockpick when hands must be empty
  open:false                 -- open containers after unlocking
  empty:<target>             -- empty contents into target (implies open)
  unjam_first:false          -- two-pass: unjam all, then unlock all
  skip:60                    -- skip unjams where Success > this value

Examples:
  /mode locksmith
  /mode locksmith cont:chest from:wagon to:n open:true
  /mode locksmith skip:75 unjam_first:true empty:sack to:wagon
]]
local strings = require('lib_strings')

local M = {}

local directions = {
    n = true, s = true, e = true, w = true,
    ne = true, nw = true, se = true, sw = true,
}

local function parse_args(args)
    local config = {
        cont = 'chest|coffer|trunk',
        from = 'here',
        to = 'here',
        stow = 'my neckpouch|sack|backpack|satchel',
        open = false,
        empty = nil,
        unjam_first = false,
        skip = 60,
    }
    for _, arg in ipairs(args) do
        local key, value = arg:match('^(.+):(.+)$')
        if key == 'cont' then config.cont = value
        elseif key == 'from' then config.from = value
        elseif key == 'to' then config.to = value
        elseif key == 'stow' then config.stow = value
        elseif key == 'open' then config.open = (value == 'true')
        elseif key == 'empty' then
            config.empty = value
            config.open = true
        elseif key == 'unjam_first' then config.unjam_first = (value == 'true')
        elseif key == 'skip' then config.skip = tonumber(value) or 60
        end
    end
    return config
end

local function build_work_cmd(verb)
    local cont = state.get('cont')
    if state.get('in_place') then
        local idx = state.get('container_index')
        return verb .. ' ' .. idx .. ' ' .. cont .. ' with lockpick'
    end
    return verb .. ' ' .. cont .. ' with lockpick'
end

local function build_get_cmd()
    local cont = state.get('cont')
    local from = state.get('from')
    if from == 'here' then
        return 'get ' .. cont
    end
    return 'get ' .. cont .. ' from ' .. from
end

local function build_dispose_cmd()
    local cont = state.get('cont')
    local to = state.get('to')
    if to == 'here' then
        return 'drop ' .. cont
    elseif directions[to] then
        return 'toss ' .. cont .. ' ' .. to
    else
        return 'put ' .. cont .. ' in ' .. to
    end
end

local function reset_container_state()
    state.set('is_jammed', false)
    state.set('is_locked', true)
    state.set('is_opened', false)
    state.set('is_emptied', false)
    state.set('skipped', false)
    state.set('unjam_done', false)
    state.set('pending_action', nil)
end

local function finish()
    notify('Completed', 'Locksmith finished')
    set_mode('disable')
end

local send_action, advance

send_action = function()
    -- Advance if container was skipped or unjam completed in unjam_first phase
    if state.get('skipped') then
        advance()
        return
    end
    if state.get('unjam_first') and state.get('phase') == 'unjam' and state.get('unjam_done') then
        state.set('unjam_done', false)
        advance()
        return
    end

    -- In pick-up mode, get container first
    if not state.get('in_place') and not state.get('holding') then
        send(build_get_cmd())
        return
    end

    -- unjam_first, unjam phase: only unjam
    if state.get('unjam_first') and state.get('phase') == 'unjam' then
        send(build_work_cmd('unjam'))
        return
    end

    -- Sequential or unlock phase: work through steps
    if state.get('is_jammed') then
        send(build_work_cmd('unjam'))
        return
    end

    if state.get('is_locked') then
        send(build_work_cmd('unlock'))
        return
    end

    if state.get('open') and not state.get('is_opened') then
        send('open ' .. state.get('cont'))
        return
    end

    if state.get('empty') and not state.get('is_emptied') then
        send('empty ' .. state.get('cont') .. ' into ' .. state.get('empty'))
        return
    end

    -- All steps done, advance to next container
    advance()
end

advance = function()
    reset_container_state()

    if state.get('in_place') then
        state.set('container_index', state.get('container_index') + 1)
        send_action()
    else
        -- In unjam_first unjam phase, put container back in source
        if state.get('unjam_first') and state.get('phase') == 'unjam' then
            local cont = state.get('cont')
            local from = state.get('from')
            if from == 'here' then
                send('drop ' .. cont)
            else
                send('put ' .. cont .. ' in ' .. from)
            end
        else
            send(build_dispose_cmd())
        end
    end
end

function M.on_start(args)
    local config = parse_args(args)

    -- Store config in state
    state.set('cont', config.cont)
    state.set('from', config.from)
    state.set('to', config.to)
    state.set('stow', config.stow)
    state.set('open', config.open)
    state.set('empty', config.empty)
    state.set('unjam_first', config.unjam_first)
    state.set('skip', config.skip)

    -- Derived state
    local in_place = (config.from == 'here' and config.to == 'here')
    state.set('in_place', in_place)
    state.set('container_index', 1)
    state.set('phase', config.unjam_first and 'unjam' or 'unlock')
    state.set('holding', false)

    reset_container_state()

    log('Locksmith mode started')
    send_action()
end

M.reactions = {
    -- Difficulty check: skip hard unjams
    {
        match = '[Success:',
        action = function(text)
            local success = tonumber(text:match('%[Success:%s*(%d+)'))
            if not success then return end
            local unjamming = state.get('is_jammed') or
                (state.get('unjam_first') and state.get('phase') == 'unjam')
            if unjamming and success > state.get('skip') then
                state.set('skipped', true)
            end
        end,
    },

    -- Unjam success
    {
        match = 'You feel an obstruction release',
        action = function()
            state.set('is_jammed', false)
            if state.get('unjam_first') and state.get('phase') == 'unjam' then
                state.set('unjam_done', true)
            end
        end,
    },

    -- Unlock success
    {
        match = 'You hear a click as the tumbler mechanism releases',
        action = function()
            state.set('is_locked', false)
        end,
    },

    -- Discovered jam during unlock attempt
    {
        match = 'This lock is jammed',
        action = function()
            state.set('is_jammed', true)
            send(build_work_cmd('unjam'))
        end,
    },

    -- Already unjammed or already unlocked
    {
        match = 'It is already',
        action = function()
            if state.get('unjam_first') and state.get('phase') == 'unjam' then
                -- Not jammed, advance to next in unjam phase
                advance()
                return
            end
            -- Could be "already unjammed" or "already unlocked"
            if state.get('is_jammed') then
                state.set('is_jammed', false)
            else
                state.set('is_locked', false)
            end
        end,
    },

    -- Need lockpick
    {
        match = {'You must be holding', "You don't see any"},
        action = function() send('get my lockpick') end,
    },

    -- Empty hands needed (for open/empty)
    {
        match = 'Your hands must be empty',
        action = function()
            local cont = state.get('cont')
            local pending
            if state.get('open') and not state.get('is_opened') then
                pending = 'open ' .. cont
            elseif state.get('empty') and not state.get('is_emptied') then
                pending = 'empty ' .. cont .. ' into ' .. state.get('empty')
            end
            state.set('pending_action', pending)
            send('put lockpick in ' .. state.get('stow'))
        end,
    },

    -- Take: distinguish lockpick recovery from container pickup
    {
        match = {'You take', 'You are already carrying * lockpick'},
        action = function(text)
            if text:match('lockpick') then
                -- Lockpick recovered
                local pending = state.get('pending_action')
                if pending then
                    state.set('pending_action', nil)
                    send(pending)
                    return
                end
                send_action()
                return
            end
            -- Container picked up
            state.set('holding', true)
            send_action()
        end,
    },

    -- Unbusy: main dispatch
    {
        match = strings.unbusy,
        action = function()
            send_action()
        end,
    },
}

return M
