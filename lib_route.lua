--[[
Wagon-route helper: sequence a list of pull/open commands, then hand off.

Each command is either a wagon pull ('pull wagon ...') or an open ('open ...').
Pulls wait for 'You stop pulling' followed by an unbusy line before advancing;
opens advance immediately on 'You open' / 'is already open'. After the final
command, on_done() runs — typically after.finish('<next_leg>') or a set_mode
into a wagon sell that carries its own after:<mode>.

Usage (one file per resumable leg):
    local route = require('lib_route')
    local after = require('lib_after')
    return route.mode(
        { 'pull wagon ne 3 e 8 n 5', 'pull wagon e 3 s 1' },
        function() after.finish('next_leg') end
    )

Because each leg is its own mode, a broken run resumes by re-running that leg.
on_start honors an after:<mode> arg, so legs that finish via after.finish can
have their tail overridden (e.g. /mode <leg> after:disable).
]]
local strings = require('lib_strings')
local after = require('lib_after')

local R = {}

local function is_open(cmd)
    return cmd:sub(1, 4) == 'open'
end

-- Total rooms a 'pull wagon <spec>' command moves (e.g. 'e 3 s 1' -> 4).
local function pull_rooms(cmd)
    local spec = cmd:match('^pull%s+wagon%s+(.+)$')
    if not spec then return 0 end
    local total = 0
    for tok in spec:gmatch('%S+') do
        local n = tonumber(tok)
        -- A direction counts as one room; a following number sets its count.
        total = total + (n and (n - 1) or 1)
    end
    return total
end

-- 'You stop pulling' is emitted only when some direction moves more than one
-- room (a sustained run). A pull made only of single-room legs ('pull wagon e',
-- 'pull wagon w 1 n 1') produces no stop marker — just one unbusy per leg — so
-- such pulls advance by counting those unbusy lines instead of waiting on a stop.
local function emits_stop(cmd)
    for tok in cmd:gmatch('%S+') do
        local n = tonumber(tok)
        if n and n > 1 then return true end
    end
    return false
end

-- Build a route mode from an ordered command list and a completion callback.
function R.mode(steps, on_done)
    local M = {}

    local function send_step(i)
        state.set('route_idx', i)
        state.set('route_waiting_stop', false)
        state.set('route_unbusy', 0)
        send(steps[i])
    end

    local function advance()
        local i = state.get('route_idx')
        if i >= #steps then
            on_done()
        else
            send_step(i + 1)
        end
    end

    function M.on_start(args)
        after.parse(args)
        send_step(1)
    end

    M.reactions = {
        -- Pull finished moving; wait for the following unbusy before advancing.
        {
            match = 'You stop pulling',
            action = function()
                state.set('route_waiting_stop', true)
            end,
        },
        -- Open is instantaneous — advance as soon as it resolves.
        {
            match = { 'You open', 'is already open' },
            action = function()
                if is_open(steps[state.get('route_idx')]) then advance() end
            end,
        },
        -- Unbusy completes a pull. Runs that emit a stop marker advance on the
        -- unbusy following it; all-single-room pulls have no stop marker, so we
        -- advance once we've seen one unbusy per leg.
        {
            match = strings.unbusy,
            action = function()
                local cmd = steps[state.get('route_idx')]
                if is_open(cmd) then return end
                if emits_stop(cmd) then
                    if not state.get('route_waiting_stop') then return end
                    state.set('route_waiting_stop', false)
                    advance()
                else
                    local seen = (state.get('route_unbusy') or 0) + 1
                    state.set('route_unbusy', seen)
                    if seen >= pull_rooms(cmd) then advance() end
                end
            end,
        },
    }

    return M
end

return R
