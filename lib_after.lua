--[[
Mode chaining via an `after:<mode>` argument token.

Usage in a mode file:
    local after = require('lib_after')

    function M.on_start(args)
        args = after.parse(args)   -- strips after:<mode>, returns the rest
        -- ... normal arg handling on the cleaned args ...
    end

    -- at each successful-completion point, instead of set_mode('disable'):
    after.finish()          -- chain to after:<mode>, else 'disable'
    after.finish('idle')    -- chain to after:<mode>, else 'idle'

The `after:` token may appear in any arg position, so it never collides
with a mode's positional args. Chains nest: each mode carries its own after:.
]]
local A = {}

-- Strip any `after:<mode>` token from args, remember the target mode,
-- and return the remaining args. Call at the top of on_start.
function A.parse(args)
    local rest = {}
    for _, a in ipairs(args or {}) do
        if type(a) == 'string' and a:sub(1, 6) == 'after:' then
            state.set('after_mode', a:sub(7))
        else
            rest[#rest + 1] = a
        end
    end
    return rest
end

-- Switch to the chained mode if one was given, else `fallback` (default 'disable').
-- Use in place of set_mode('disable') at successful-completion points.
function A.finish(fallback)
    set_mode(state.get('after_mode') or fallback or 'disable')
end

return A
