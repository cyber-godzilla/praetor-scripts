--[[
Loops through every corpse in the area, taking the requested items and routing
them according to the first matching rule.

The item, drop, and special lists are pipe-delimited. Item aliases from
lib_loot.lua are also accepted.

Every other argument is a key:value token and may appear in any position:
  start:<corpse#>       -- corpse to begin on (default: 1)
  from:<noun>           -- replaces "corpse" in the get command
  stow:<container>      -- ordinary-loot container type
  stow_start:<n>        -- first numbered ordinary-loot container (default: 1)
  drop:<item|list>      -- taken items matching this list are dropped
  special:<item|list>   -- taken items matching this list go to special_dest
  special_dest:<dest>   -- a literal destination such as "1 sack", or a bare
                           container type such as sack that rotates from 1

/mode loot . stow:sack stow_start:2 special:pouch|armband special_dest:"1 sack" drop:sack|junk|garbage
]]
local loot_tables = require('lib_loot')
local after = require('lib_after')

local M = {}

M.usage = '<item|alias> [start:<corpse#>] [from:<noun>] [stow:<container>] [stow_start:<n>] [drop:<item|list>] [special:<item|list> special_dest:<destination>]'
M.desc = 'Take and route loot from every corpse, rotating containers as they fill'
M.chains = true

local FULL_CONTAINER = 'There is not enough room to put'
local HANDS_FULL = "You don't have enough free hands"
local STOW_CONFIRMED = 'will be used for stowage'

local option_keys = {
    start = true,
    from = true,
    stow = true,
    stow_start = true,
    drop = true,
    special = true,
    special_dest = true,
}

local function split_list(value)
    local result = {}
    for entry in value:gmatch('[^|]+') do
        result[#result + 1] = entry
    end
    return result
end

local function parse_args(args)
    local config = {
        item = nil,
        start = 1,
        from = 'corpse',
        stow = '',
        stow_start = nil,
        drop = {},
        special = {},
        special_dest = '',
    }

    for _, arg in ipairs(args) do
        local key, value = arg:match('^(.-):(.*)$')
        if key and option_keys[key] then
            if key == 'start' then
                config.start = tonumber(value)
                if not config.start then return nil, 'start: needs a number' end
            elseif key == 'from' then
                if value == '' then return nil, 'from: needs a noun' end
                config.from = value
            elseif key == 'stow' then
                if value == '' then return nil, 'stow: needs a container' end
                config.stow = value
            elseif key == 'stow_start' then
                config.stow_start = tonumber(value)
                if not config.stow_start then return nil, 'stow_start: needs a number' end
            elseif key == 'drop' then
                config.drop = split_list(value)
                if #config.drop == 0 then return nil, 'drop: needs at least one item' end
            elseif key == 'special' then
                config.special = split_list(value)
                if #config.special == 0 then return nil, 'special: needs at least one item' end
            elseif key == 'special_dest' then
                if value == '' then return nil, 'special_dest: needs a destination' end
                config.special_dest = value
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
    if #config.special > 0 and config.special_dest == '' then
        return nil, 'special: needs a special_dest:<destination>'
    end
    if config.special_dest ~= '' and #config.special == 0 then
        return nil, 'special_dest: needs a special:<item|list>'
    end

    return config
end

local function list_match(text, entries)
    local lower = text:lower()
    for _, entry in ipairs(entries) do
        if lower:find(entry:lower(), 1, true) then return entry end
    end
    return nil
end

local function disposition(text)
    local drop_match = list_match(text, state.get('drop'))
    if drop_match then return 'drop', drop_match end
    local special_match = list_match(text, state.get('special'))
    if special_match then return 'special', special_match end
    return 'stow'
end

local function taken_name(text)
    return text:match('^You take (.-) from ')
        or text:match('^You take (.-)%.$')
        or text:match('^You take (.+)$')
end

local function put_name(text)
    return text:match('^You put (.-) in ')
        or text:match('^You put (.-) on ')
        or text:match('^You put (.-) under ')
end

local function command_name(name)
    return name:gsub('^an? ', ''):gsub('^some ', ''):gsub('^the ', '')
end

local function held_items()
    return state.get('held_items')
end

local function remember_item(name, route, route_target)
    local items = held_items()
    items[#items + 1] = {name = name, route = route, route_target = route_target}
    state.set('held_items', items)
    return items[#items]
end

local function forget_item(name)
    local items = held_items()
    for i, item in ipairs(items) do
        if item.name == name then
            table.remove(items, i)
            state.set('held_items', items)
            return
        end
    end
end

local function main_destination()
    local container = state.get('stow_container')
    local index = state.get('stow_index')
    if container == '' or index == 0 then return nil end
    return index .. ' ' .. container
end

local function special_destination()
    if state.get('special_rotates') then
        return state.get('special_index') .. ' ' .. state.get('special_container')
    end
    return state.get('special_dest')
end

local function send_get()
    state.set('awaiting', 'get')
    send('get ' .. state.get('item') .. ' from ' .. state.get('corpse') .. ' ' .. state.get('from'))
end

local function send_stow(resume)
    local destination = main_destination()
    if not destination then return false end
    state.set('stow_resume', resume)
    state.set('awaiting', 'stow')
    send('stow ' .. destination)
    return true
end

local function rotate_stow(resume)
    if state.get('stow_container') == '' then return false end
    state.set('stow_index', state.get('stow_index') + 1)
    return send_stow(resume)
end

local route_current
local cleanup_next

local function retry_current_put()
    local current = state.get('current_item')
    if not current then return end
    local target = current.route_target or command_name(current.name)
    if current.route == 'special' then
        send('put ' .. target .. ' in ' .. special_destination())
    else
        send('put ' .. target .. ' in ' .. main_destination())
    end
end

route_current = function(cleanup)
    local current = state.get('current_item')
    if current.route == 'drop' then
        state.set('awaiting', cleanup and 'cleanup_drop' or 'drop')
        send('drop ' .. current.route_target)
    elseif current.route == 'special' then
        state.set('awaiting', cleanup and 'cleanup_special' or 'special')
        send('put ' .. current.route_target .. ' in ' .. special_destination())
    elseif cleanup and main_destination() then
        state.set('awaiting', 'cleanup_stow')
        send('put ' .. command_name(current.name) .. ' in ' .. main_destination())
    elseif cleanup and state.get('stow_container') ~= '' then
        state.set('stow_index', 1)
        send_stow('cleanup_stow')
    elseif cleanup then
        state.set('current_item', nil)
        state.set('cleanup_index', state.get('cleanup_index') + 1)
        cleanup_next()
    else
        send_get()
    end
end

local function finish()
    notify('Completed', 'Loot collection finished')
    after.finish()
end

cleanup_next = function()
    local queue = state.get('cleanup_queue')
    local index = state.get('cleanup_index')
    if index > #queue then
        finish()
        return
    end
    state.set('current_item', queue[index])
    route_current(true)
end

local function begin_cleanup()
    state.set('awaiting', 'inhand')
    send('inhand')
end

local function abort(message)
    notify('Cannot proceed', 'loot stopped: ' .. message)
    set_mode('disable')
end

function M.on_start(args)
    args = after.parse(args)

    local config, err = parse_args(args)
    if not config then
        log('loot mode ' .. err)
        set_mode('disable')
        return
    end

    local fixed_index = config.special_dest:match('^%d+%s+')
    local special_rotates = config.special_dest ~= ''
        and not fixed_index
        and not config.special_dest:find('%s')

    state.set('item', loot_tables.resolve(config.item))
    state.set('corpse', config.start)
    state.set('from', config.from)
    state.set('drop', config.drop)
    state.set('special', config.special)
    state.set('special_dest', config.special_dest)
    state.set('special_rotates', special_rotates)
    state.set('special_container', special_rotates and config.special_dest or '')
    state.set('special_index', 1)
    state.set('stow_container', config.stow)
    -- Without stow_start, retain the character's current stowage during the
    -- run and begin numbered rotation at 1 only when it becomes necessary.
    state.set('stow_index', config.stow_start or 0)
    state.set('held_items', {})
    state.set('current_item', nil)

    if config.stow ~= '' and config.stow_start then
        send_stow('get')
    else
        send_get()
    end
end

M.reactions = {
    -- A successful take is routed drop first, special second, and ordinary
    -- stowage last. Ordinary items stay in hand until the following get makes
    -- the game's configured stowage put them away.
    {
        match = 'You take',
        action = function(text)
            local name = taken_name(text)
            if not name then return end
            local route, route_target = disposition(text)
            local current = remember_item(name, route, route_target)
            state.set('current_item', current)
            if text:find('glowing', 1, true) then
                state.set('after_extinguish', 'route')
                state.set('awaiting', 'extinguish')
                send('extinguish my glowing')
                return
            end
            route_current(false)
        end,
    },

    -- A glowing held item can also block the automatic put attempted by get.
    {
        match = "That's really not a very good idea",
        action = function()
            state.set('after_extinguish', state.get('awaiting'))
            state.set('awaiting', 'extinguish')
            send('extinguish my glowing')
        end,
    },
    {
        match = 'You extinguish',
        action = function()
            local resume = state.get('after_extinguish')
            state.set('after_extinguish', nil)
            if resume == 'route' then
                route_current(false)
            elseif resume == 'special' or resume == 'cleanup_special' or resume == 'cleanup_stow' then
                state.set('awaiting', resume)
                retry_current_put()
            else
                send_get()
            end
        end,
    },

    -- Explicit and automatic puts both remove an item from the set this run
    -- may need to clean up. Automatic puts need no new command: their get is
    -- still producing the following take/failure response.
    {
        match = 'You put',
        action = function(text)
            local name = put_name(text)
            if name then forget_item(name) end
            local awaiting = state.get('awaiting')
            if awaiting == 'special' then
                state.set('current_item', nil)
                send_get()
            elseif awaiting == 'cleanup_special' or awaiting == 'cleanup_stow' then
                state.set('current_item', nil)
                state.set('cleanup_index', state.get('cleanup_index') + 1)
                cleanup_next()
            end
        end,
    },
    {
        match = {'You drop*', 'You discard*'},
        action = function()
            local current = state.get('current_item')
            if current then forget_item(current.name) end
            local awaiting = state.get('awaiting')
            state.set('current_item', nil)
            if awaiting == 'cleanup_drop' then
                state.set('cleanup_index', state.get('cleanup_index') + 1)
                cleanup_next()
            else
                send_get()
            end
        end,
    },

    -- A full explicit destination can be retried directly. A full automatic
    -- stow destination must first select the next numbered main container.
    {
        match = FULL_CONTAINER,
        action = function()
            local awaiting = state.get('awaiting')
            if awaiting == 'special' or awaiting == 'cleanup_special' then
                if not state.get('special_rotates') then
                    abort('special destination is full')
                    return
                end
                state.set('special_index', state.get('special_index') + 1)
                retry_current_put()
            elseif awaiting == 'cleanup_stow' then
                if not rotate_stow('cleanup_stow') then
                    abort('ordinary destination is full and no stow container is configured')
                end
            else
                if not rotate_stow('get') then
                    abort('ordinary destination is full and no stow container is configured')
                end
            end
        end,
    },
    {
        match = HANDS_FULL,
        action = function()
            if not rotate_stow('get') then
                abort('hands are full and no stow container is configured')
            end
        end,
    },
    {
        match = STOW_CONFIRMED,
        action = function()
            local resume = state.get('stow_resume')
            state.set('stow_resume', nil)
            if resume == 'cleanup_stow' then
                state.set('awaiting', 'cleanup_stow')
                retry_current_put()
            else
                send_get()
            end
        end,
    },

    -- The final numbered source failure starts hand cleanup instead of ending
    -- immediately. Stow/special lookup failures are fatal and never advance the
    -- corpse counter.
    {
        match = {'anywhere.', "There aren't that many here"},
        action = function()
            local awaiting = state.get('awaiting')
            if awaiting == 'stow' then
                abort('no ordinary containers available')
            elseif awaiting == 'special' or awaiting == 'cleanup_special' then
                abort('no special containers available')
            elseif awaiting == 'cleanup_stow' then
                abort('no ordinary containers available')
            elseif awaiting == 'get' then
                begin_cleanup()
            end
        end,
    },
    {
        match = "You don't see",
        condition = function()
            local awaiting = state.get('awaiting')
            return awaiting == 'special'
                or awaiting == 'cleanup_special'
                or awaiting == 'cleanup_stow'
        end,
        action = function()
            if state.get('awaiting') == 'cleanup_stow' then
                abort('no ordinary containers available')
            else
                abort('no special containers available')
            end
        end,
    },
    {
        match = "You don't see",
        condition = function()
            return state.get('awaiting') == 'get'
        end,
        action = function()
            state.set('corpse', state.get('corpse') + 1)
            send_get()
        end,
    },

    -- INHAND has one stable line containing both hands. Only items recorded as
    -- taken by this run are queued, so an unrelated weapon/tool is left alone.
    {
        match = '^You are holding * in your right hand and * in your left hand.$',
        condition = function()
            return state.get('awaiting') == 'inhand'
        end,
        action = function(text)
            local right, left = text:match('^You are holding (.-) in your right hand and (.-) in your left hand%.$')
            local available = held_items()
            local used = {}
            local queue = {}

            local function add_if_looted(name)
                if name == 'nothing' then return end
                for i, item in ipairs(available) do
                    if not used[i] and item.name == name then
                        used[i] = true
                        queue[#queue + 1] = item
                        return
                    end
                end
            end

            add_if_looted(right)
            add_if_looted(left)
            state.set('cleanup_queue', queue)
            state.set('cleanup_index', 1)
            cleanup_next()
        end,
    },
}

return M
