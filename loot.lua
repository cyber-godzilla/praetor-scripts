--[[
Loops through every corpse in the area, taking the list of items given.
Uses the pipe-delimited format, but won't support spaces. For example:
/mode loot bronze|alanti|retalq|boison <-- Works
/mode loot bronze helm|manksana|nagoda <-- Does not work

If you need to include items with a space in the name, like "bronze helm", add a custom shorthand in lib_loot.lua
]]
local loot_tables = require('lib_loot')

local M = {}

function M.on_start(args)
    if not args[1] then
        log('loot mode requires at least one argument (item name)')
        set_mode('disable')
        return
    end
    local item = loot_tables.resolve(args[1])
    state.set('item', item)
    local corpse = tonumber(args[2]) or 1
    state.set('corpse', corpse)
    send('get ' .. item .. ' from ' .. corpse .. ' corpse')
end

M.reactions = {
    -- Glowing items need extinguishing
    {
        match = {'You take a glowing', "That's really not a very good idea"},
        action = function()
            send('extinguish my glowing')
        end,
    },
    -- Successfully took item, get next
    {
        match = 'You take',
        action = function()
            local item = state.get('item')
            local corpse = state.get('corpse')
            send('get ' .. item .. ' from ' .. corpse .. ' corpse')
        end,
    },
    -- Extinguished, continue looting
    {
        match = 'You extinguish',
        action = function()
            local item = state.get('item')
            local corpse = state.get('corpse')
            send('get ' .. item .. ' from ' .. corpse .. ' corpse')
        end,
    },
    -- No more corpses
    {
        match = {'anywhere.', "There aren't that many here"},
        action = function()
            set_mode('disable')
            notify('Completed', 'Loot collection finished')
        end,
    },
    -- Item not on this corpse, try next
    {
        match = "You don't see",
        action = function()
            local corpse = state.get('corpse') + 1
            state.set('corpse', corpse)
            local item = state.get('item')
            send('get ' .. item .. ' from ' .. corpse .. ' corpse')
        end,
    },
}

return M
