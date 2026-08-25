--[[
Drag an item along a fixed path, one room at a time.

A wagon covers a whole route in one 'pull wagon <dir> <count> ...' command, but
not everything is a wagon — anything else has to be dragged room by room. This
mode does that: it sends 'drag <item> <dir>' on every unbusy and counts arrivals
until the current leg's pace count is met, then starts the next leg.

    /mode drag_paces sled n:3 e:8 s w:2 after:wagon

A bare direction is a single pace, so 's' and 's:1' mean the same thing. Legs
run in the order given.

Progress is counted from 'You arrive', not from commands sent, so a drag that
never lands never advances the run. When a leg stalls — an animal blocking the
way, a closed gate, water too deep — the mode notifies once and stops sending.
Clear the blocker however you like, then drag one room yourself: that arrival
counts as a pace and the loop picks up again on the next unbusy. A retreat does
not leave the room, so fighting your way clear cannot miscount.
]]
local strings = require('lib_strings')
local drag = require('lib_drag_paces')
local after = require('lib_after')

local M = {}

M.usage = '<item> <dir>[:<count>]...'
M.desc = 'Drag an item a set number of paces along a direction list'
M.chains = true

-- How long to wait for an arrival before assuming the drag is blocked. This is
-- the backstop for failures drag.blocked does not name.
local STUCK_MS = 8000

-- Legs of the current run, in order: { {dir = 'n', count = 3}, ... }.
-- Held file-local the way lib_route holds its step list; only the position
-- within the run goes through state.
local legs = {}

-- Argument errors stop with a bare disable so a bad run never chains onward.
local function abort(msg)
    log('drag_paces: ' .. msg)
    set_mode('disable')
end

-- 'n:3' -> {dir = 'n', count = 3}; a bare 'n' is one pace.
-- Returns nil on anything malformed so on_start can abort instead of guess.
local function parse_leg(token)
    local dir, count = token:match('^(%a+):(%d+)$')
    if dir then
        count = tonumber(count)
        if count < 1 then return nil end
        return {dir = dir, count = count}
    end
    if token:match('^%a+$') then
        return {dir = token, count = 1}
    end
    return nil
end

local function clear_stuck_timer()
    local id = state.get('stuck_timer')
    if id then clear_timer(id) end
    state.set('stuck_timer', false)
end

-- Stop sending and tell the player once. Staying quiet from here keeps the
-- mode out of the way while they fight or open whatever is in the way.
local function stall(reason)
    clear_stuck_timer()
    if state.get('paused') then return end
    state.set('paused', true)
    notify('Cannot proceed', reason)
end

local function send_drag()
    local leg = legs[state.get('leg')]
    clear_stuck_timer()
    send('drag ' .. state.get('what') .. ' ' .. leg.dir)
    state.set('stuck_timer', set_timeout(function()
        stall('No arrival after dragging ' .. leg.dir)
    end, STUCK_MS))
end

function M.on_start(args)
    args = after.parse(args)

    local what = args[1]
    if not what then
        abort('requires an item to drag')
        return
    end

    legs = {}
    for i = 2, #args do
        local leg = parse_leg(args[i])
        if not leg then
            abort('bad leg "' .. args[i] .. '", expected <dir> or <dir>:<count>')
            return
        end
        legs[#legs + 1] = leg
    end
    if #legs == 0 then
        abort('requires at least one <dir>[:<count>] leg')
        return
    end

    state.set('what', what)
    state.set('leg', 1)
    state.set('paced', 0)
    state.set('paused', false)
    state.set('stuck_timer', false)
    send_drag()
end

function M.on_stop()
    clear_stuck_timer()
end

M.reactions = {
    -- The room actually changed, so this is a pace. It also clears a stall:
    -- unsticking by hand and dragging one room resumes the run.
    {
        match = drag.arrived,
        action = function()
            clear_stuck_timer()
            state.set('paused', false)

            local leg = state.get('leg')
            local paced = state.get('paced') + 1
            if paced < legs[leg].count then
                state.set('paced', paced)
                return
            end

            if leg >= #legs then
                -- Pause before handing off so a trailing unbusy cannot squeeze
                -- one more drag out between here and the mode switch.
                state.set('paused', true)
                notify('Completed', 'drag_paces finished')
                after.finish()
                return
            end
            state.set('leg', leg + 1)
            state.set('paced', 0)
        end,
    },
    -- A named failure stalls straight away instead of waiting out STUCK_MS.
    {
        match = drag.blocked,
        action = function(text)
            stall(text)
        end,
    },
    -- Free to act: take the next pace. While stalled this does nothing, so a
    -- retreat's unbusy correctly leaves the run parked.
    {
        match = strings.unbusy,
        action = function()
            if state.get('paused') then return end
            send_drag()
        end,
    },
}

return M
