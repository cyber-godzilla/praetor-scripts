--[[
Loops through every corpse in the area, taking the list of items given, and
rotating stowage containers as each one fills up.

The item list is pipe-delimited and won't support spaces. For example:
/mode loot bronze|alanti|retalq|boison <-- Works
/mode loot bronze helm|manksana|nagoda <-- Does not work

If you need to include items with a space in the name, like "bronze helm", add a custom shorthand in lib_loot.lua

Every other argument is a key:value token and may appear in any position:
  start:<corpse#>     -- corpse to begin on (default: 1)
  stow:<container>    -- container word for the game's `stow <#> <container>`,
                         one word only since args are split on spaces
  stow_start:<n>      -- earliest instance of that container that may be used;
                         stowed to before looting begins
  drop:<item|list>    -- pipe-delimited; anything taken whose message matches an
                         entry is dropped instead of kept

/mode loot hand stow:pack stow_start:3 drop:rawhide|hide <-- Loot the "hand" list into
the third pack onward, dropping any rawhide or hide taken
]]
local loot_tables = require('lib_loot')
local after = require('lib_after')

local M = {}

M.usage = '<item|alias> [start:<corpse#>] [stow:<container>] [stow_start:<n>] [drop:<item|list>]'
M.desc = 'Take a pipe-delimited item list from every corpse, rotating stowage containers'
M.chains = true

--[[
Stowage rotation. Self-contained on purpose: it owns its two patterns and its
own `stow_` state keys, reads nothing else, and leaves `awaiting` to its
callers. Lifting the block into lib_stow.lua when a second mode needs stowage
rotation is a cut, a require, and nothing else.
]]
local stow = {}

stow.hands_full = "You don't have enough free hands"
stow.confirmed = 'will be used for stowage'

-- Remember what to rotate through. An index of 0 means no opening stow: the
-- current stowage is left alone and rotation starts at 1 when hands first fill.
function stow.configure(container, start_index)
    state.set('stow_container', container or '')
    state.set('stow_index', start_index or 0)
end

-- Stow to the earliest usable container. Returns false when none was asked for.
function stow.begin()
    local container = state.get('stow_container')
    local index = state.get('stow_index')
    if container == '' or index == 0 then return false end
    send('stow ' .. index .. ' ' .. container)
    return true
end

-- Move stowage to the next container. Returns false when none was configured.
-- Always increments, so a run walks off the end of the list rather than looping.
function stow.rotate()
    local container = state.get('stow_container')
    if container == '' then return false end
    local index = state.get('stow_index') + 1
    state.set('stow_index', index)
    send('stow ' .. index .. ' ' .. container)
    return true
end

local option_keys = {start = true, stow = true, stow_start = true, drop = true}

-- Consume key:value tokens wherever they sit, following the same convention
-- lib_after uses for after:<mode>; the first bare token is the item list.
-- Returns nil plus a message when an argument doesn't make sense.
local function parse_args(args)
    local config = {item = nil, start = 1, stow = '', stow_start = nil, drop = {}}
    for _, arg in ipairs(args) do
        local key, value = arg:match('^(.-):(.*)$')
        if key and option_keys[key] then
            if key == 'start' then
                config.start = tonumber(value)
                if not config.start then return nil, 'start: needs a number' end
            elseif key == 'stow' then
                config.stow = value
            elseif key == 'stow_start' then
                config.stow_start = tonumber(value)
                if not config.stow_start then return nil, 'stow_start: needs a number' end
            elseif key == 'drop' then
                for entry in value:gmatch('[^|]+') do
                    config.drop[#config.drop + 1] = entry
                end
            end
        elseif key then
            return nil, 'unknown option "' .. arg .. '"'
        elseif not config.item then
            config.item = arg
        end
    end
    if not config.item then
        return nil, 'requires at least one argument (item name)'
    end
    if config.stow_start and config.stow == '' then
        return nil, 'stow_start: needs a stow:<container> to rotate through'
    end
    return config
end

-- Every command records what reply it waits on, so the failure both share can
-- tell an exhausted corpse run from exhausted stowage.
local function send_get()
    send('get ' .. state.get('item') .. ' from ' .. state.get('corpse') .. ' corpse')
    state.set('awaiting', 'get')
end

function M.on_start(args)
    args = after.parse(args)

    local config, err = parse_args(args)
    if not config then
        log('loot mode ' .. err)
        set_mode('disable')
        return
    end

    state.set('item', loot_tables.resolve(config.item))
    state.set('corpse', config.start)
    state.set('drop', config.drop)
    stow.configure(config.stow, config.stow_start)

    if stow.begin() then
        state.set('awaiting', 'stow')
    else
        send_get()
    end
end

M.reactions = {
    -- Glowing items need extinguishing
    {
        match = {'You take a glowing', "That's really not a very good idea"},
        action = function()
            send('extinguish my glowing')
        end,
    },
    -- Successfully took item, drop it if it matches drop:, else get next
    {
        match = 'You take',
        action = function(text)
            for _, entry in ipairs(state.get('drop')) do
                if text:find(entry, 1, true) then
                    send('drop ' .. entry)
                    return
                end
            end
            send_get()
        end,
    },
    -- Extinguished or dropped, continue looting
    {
        match = {'You extinguish', 'You drop*'},
        action = function()
            send_get()
        end,
    },
    -- Stowage container is full, move to the next one
    {
        match = stow.hands_full,
        action = function()
            if stow.rotate() then
                state.set('awaiting', 'stow')
                return
            end
            notify('Cannot proceed', 'Hands full, no stow: container given')
            set_mode('disable')
        end,
    },
    -- Stowage moved, retry what this corpse still has
    {
        match = stow.confirmed,
        action = function()
            send_get()
        end,
    },
    -- Out of corpses, or out of containers: the game says the same thing either
    -- way, so go by which command is outstanding. Must stay ABOVE the
    -- "You don't see" reaction below: the out-of-corpses line is "You don't see
    -- a corpse anywhere.", which contains both patterns, and the first matching
    -- reaction wins. Below it, the run advances the corpse counter forever.
    {
        match = {'anywhere.', "There aren't that many here"},
        action = function()
            if state.get('awaiting') == 'stow' then
                notify('Cannot proceed', 'No containers available')
                set_mode('disable')
                return
            end
            notify('Completed', 'Loot collection finished')
            after.finish()
        end,
    },
    -- Item not on this corpse, try next
    {
        match = "You don't see",
        action = function()
            state.set('corpse', state.get('corpse') + 1)
            send_get()
        end,
    },
}

return M
