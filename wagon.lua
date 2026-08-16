--[[
Sell contents of your wagon to a vendor.
Supports aliases (see lib_wagon.lua)
For aliases, the key must be the vendor name.

Without aliases, arguments are:
- item: pipe-delimited list of items you're giving the vendor
- target: The name of the vendor
- container: If not a wagon, what container.

/mode wagon romulus <-- Using the alias in lib_wagon.lua, get items from the wagon for Romulus
/mode wagon bronze|boss jovinus <-- Sell bronze|boss from wagon to Jovinus
/mode wagon tin telaria sack <-- Sell tin from sack to Telaria
]]
local wagon_tables = require('lib_wagon')
local after = require('lib_after')

local M = {}

M.usage = '<alias|items> [vendor] [container]'
M.desc = 'Sell the contents of a wagon to a vendor'
M.chains = true

function M.on_start(args)
    if not args[1] then
        log('wagon mode requires at least one argument')
        set_mode('disable')
        return
    end

    -- Strip after:<mode> so it doesn't collide with item/target/container args.
    local clean_args = after.parse(args)

    local container = 'wagon'
    local item, target

    if wagon_tables.wagon[clean_args[1]] then
        item = wagon_tables.wagon[clean_args[1]]
        target = clean_args[1]
        if clean_args[2] then container = clean_args[2] end
    else
        item = clean_args[1]
        target = clean_args[2] or ''
        if clean_args[3] then container = clean_args[3] end
    end

    state.set('item', item)
    state.set('wagon_target', target)
    state.set('container', container)
    send('get ' .. item .. ' from ' .. container)
end

M.reactions = {
    {
        match = 'You take',
        action = function()
            local item = state.get('item')
            local target = state.get('wagon_target')
            send('offer ' .. item .. ' to ' .. target)
        end,
    },
    {
        match = 'You offer',
        action = function()
            local item = state.get('item')
            local container = state.get('container')
            send('get ' .. item .. ' from ' .. container)
        end,
    },
    {
        match = "You don't see",
        action = function()
            notify('Completed', 'Wagon transfer finished')
            after.finish()
        end,
    },
}

return M
