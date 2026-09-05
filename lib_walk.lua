--[[
On-foot travel helper: sequence walk commands and short scripted actions.

Each step is a command string or {cmd = '...', match = '...'}:
  - 'walk to <place>' advances on the pathing completion line
    'You stop walking, having reached your destination.'
  - 'walk <spec>' (multi-direction, e.g. 'walk e 2 s 1') advances on
    'You stop walking.' (the period keeps it from matching the line above)
  - anything else needs an explicit match: {cmd = 'u', match = 'You climb'}
  - add unbusy = true to a step whose command incurs a roundtime (e.g.
    unlocking a door): the next command is held until the unbusy line
    that follows the step's match

Usage (one file per leg):
    local walk = require('lib_walk')
    local after = require('lib_after')
    return walk.mode(
        { 'walk to somewhere', 'walk e 2 s 1', {cmd = 'u', match = 'You climb'} },
        function() after.finish('next_leg') end,
        { desc = '...', chains = true }
    )

on_start honors after:<mode>. Failure lines are not watched: a step whose
marker never arrives stalls the mode, and the run resumes by re-running
the leg. Single-pace moves should be bare directions with an arrival
match -- a one-room 'walk' command is not trusted to emit a stop line.
]]
local strings = require('lib_strings')
local after = require('lib_after')

local W = {}

local DEST = 'having reached your destination'
local STOP = 'You stop walking.'

-- Normalize a step into {cmd, match}; reject bare commands whose
-- completion line cannot be inferred.
local function step_of(s)
    if type(s) == 'table' then return s end
    if s:sub(1, 8) == 'walk to ' then return {cmd = s, match = DEST} end
    if s:sub(1, 5) == 'walk ' then return {cmd = s, match = STOP} end
    error('lib_walk: step "' .. s .. '" needs an explicit match')
end

-- Build a mode from an ordered step list and a completion callback.
-- `meta` carries mode metadata: {usage=, desc=, chains=, hidden=}.
function W.mode(steps, on_done, meta)
    local M = {}

    if meta then
        M.usage = meta.usage
        M.desc = meta.desc
        M.chains = meta.chains
        M.hidden = meta.hidden
    end

    local function send_step(i)
        state.set('walk_idx', i)
        state.set('walk_unbusy_wait', false)
        send(step_of(steps[i]).cmd)
    end

    local function advance()
        local i = state.get('walk_idx')
        if i >= #steps then
            state.set('walk_idx', nil)
            on_done()
        else
            send_step(i + 1)
        end
    end

    function M.on_start(args)
        after.parse(args)
        send_step(1)
    end

    -- One reaction per distinct marker, each firing only when it is the
    -- current step's marker, so a line for a later step never skips ahead.
    local seen, markers = {}, {}
    for _, s in ipairs(steps) do
        local m = step_of(s).match
        if not seen[m] then
            seen[m] = true
            markers[#markers + 1] = m
        end
    end

    M.reactions = {}
    for _, m in ipairs(markers) do
        M.reactions[#M.reactions + 1] = {
            match = m,
            condition = function()
                local i = state.get('walk_idx')
                return i ~= nil and step_of(steps[i]).match == m
                    and not state.get('walk_unbusy_wait')
            end,
            action = function()
                local step = step_of(steps[state.get('walk_idx')])
                if step.unbusy then
                    state.set('walk_unbusy_wait', true)
                else
                    advance()
                end
            end,
        }
    end

    -- A roundtime step's marker arrived: advance on the unbusy after it.
    M.reactions[#M.reactions + 1] = {
        match = strings.unbusy,
        condition = function()
            return state.get('walk_unbusy_wait') == true
        end,
        action = function()
            advance()
        end,
    }

    return M
end

return W
