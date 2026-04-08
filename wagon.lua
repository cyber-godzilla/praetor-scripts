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

local M = {}

function M.on_start(args)
    if not args[1] then
        log('wagon mode requires at least one argument')
        set_mode('disable')
        return
    end

    -- Check for after:mode_name in any arg position for mode chaining.
    -- Same pattern used by idle (next_mode),
    -- but prefixed to avoid ambiguity with item/target/container args.
    local clean_args = {}
    for _, a in ipairs(args) do
        if a:sub(1, 6) == 'after:' then
            state.set('after_mode', a:sub(7))
        else
            clean_args[#clean_args + 1] = a
        end
    end

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
            local after = state.get('after_mode')
            if after then
                set_mode(after)
            else
                set_mode('disable')
                notify('Completed', 'Wagon transfer finished')
            end
        end,
    },
}

return M
