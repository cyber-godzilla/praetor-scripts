--[[
Loops through every corpse in the area, taking the list of items given.
Uses the pipe-delimited format, but won't support spaces. For example:
/mode loot bronze|alanti|retalq|boison <-- Works
/mode loot bronze helm|manksana|nagoda <-- Does not work

If you need to include items with a space in the name, like "bronze helm", add a custom shorthand in lib_loot.lua

Optional drop:<item> argument in any position. When set, anything you take whose
message contains <item> is dropped instead of kept. For example:
/mode loot hand drop:rawhide <-- Loot the "hand" list, but drop any rawhide taken
]]
local loot_tables = require('lib_loot')
local after = require('lib_after')

local M = {}

M.usage = '<item|alias> [corpse#] [drop:<item>]'
M.desc = 'Take a pipe-delimited item list from every corpse in the room'
M.chains = true

function M.on_start(args)
    args = after.parse(args)

    -- Strip drop:<item> from any arg position, following the same
    -- prefixed-token convention lib_after uses for after:<mode>.
    local clean_args = {}
    local drop = ''
    for _, a in ipairs(args) do
        if a:sub(1, 5) == 'drop:' then
            drop = a:sub(6)
        else
            clean_args[#clean_args + 1] = a
        end
    end
    if not clean_args[1] then
        log('loot mode requires at least one argument (item name)')
        set_mode('disable')
        return
    end
    state.set('drop', drop)

    local item = loot_tables.resolve(clean_args[1])
    state.set('item', item)
    local corpse = tonumber(clean_args[2]) or 1
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
    -- Successfully took item, drop it if it matches drop:<item>, else get next
    {
        match = 'You take',
        action = function(text)
            local drop = state.get('drop')
            if drop and drop ~= '' and text:find(drop, 1, true) then
                send('drop ' .. drop)
                return
            end
            local item = state.get('item')
            local corpse = state.get('corpse')
            send('get ' .. item .. ' from ' .. corpse .. ' corpse')
        end,
    },
    -- Extinguished or dropped, continue looting
    {
        match = {'You extinguish', 'You drop*'},
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
            notify('Completed', 'Loot collection finished')
            after.finish()
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
