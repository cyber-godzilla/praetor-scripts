--[[
Patterns for the drag_paces mode.

`arrived` is the only thing that counts as a pace, so it must match the line
the game prints when you actually change rooms while dragging.

`blocked` lists the failures worth reacting to immediately; drag_paces also
runs a timeout, so a failure that is not named here still stalls the run
rather than looping. Add lines here to shorten the wait, not to make the
mode notice at all.
]]
local S = {}

S.arrived = {'You arrive'}

S.blocked = {
    "You can't go that way",
    'There is no exit',
    'You must be standing',
    "You don't see",
    'too deep',    -- the water is too deep to drag through
    'too steep',   -- the slope is too steep to drag up
}

return S
