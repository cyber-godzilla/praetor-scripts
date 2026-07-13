--[[
Survey rooms for herb spawn rates, persist per-room data, optionally gather.
/mode herbmap <room-key> dir:<direction>
/mode herbmap boulder dir:n gather:rare stow:my backpack
/mode herbmap boulder dir:nw gather:all wagon:true

Options:
  dir:<direction>        -- travel direction between rooms (required)
  gather:none|rare|all   -- which herbs to pick up after surveying (default: none)
  stow:<container>       -- where to put gathered herbs (default: my backpack)
  wagon:true|false       -- use pull wagon instead of go (default: false)
]]
local strings = require('lib_strings')
local herbmap = require('lib_herbmap')

local M = {}

local function parse_args(args)
    local config = {
        room_key = nil,
        dir = nil,
        gather = 'none',
        stow = 'my backpack',
        wagon = false,
    }
    config.room_key = args[1]
    for i = 2, #args do
        local key, value = args[i]:match('^(.-):(.+)$')
        if key == 'dir' then config.dir = value
        elseif key == 'gather' then config.gather = value
        elseif key == 'stow' then config.stow = value
        elseif key == 'wagon' then config.wagon = (value == 'true')
        end
    end
    return config
end

local function move_cmd()
    local dir = state.get('dir')
    return state.get('wagon') and ('pull wagon ' .. dir) or ('go ' .. dir)
end

local function reset_herb_metrics()
    local tracked = state.get('tracked_herbs') or {}
    for herb_key in pairs(tracked) do
        metrics.set(herb_key, 0)
    end
    state.set('tracked_herbs', {})
end

local gather_next_herb

local function start_gathering_or_move()
    local gather = state.get('gather')
    local key = state.get('current_key')
    local map = state.get('herb_map')

    if gather ~= 'none' then
        local raw = herbmap.get_herbs_to_gather(map, key, gather)
        -- Resolve to get keywords, skip unmapped herbs
        local herbs = {}
        for _, name in ipairs(raw) do
            local kw = herbmap.herb_keywords[name]
            if kw then herbs[#herbs + 1] = kw end
        end
        if #herbs > 0 then
            state.set('phase', 'gathering')
            state.set('gather_list', herbs)
            state.set('gather_index', 1)
            return
        end
    end

    state.set('phase', 'moving')
    metrics.inc('rooms')
    send(move_cmd())
end

gather_next_herb = function()
    local herbs = state.get('gather_list')
    local idx = state.get('gather_index')
    if idx > #herbs then
        -- All herbs gathered, put everything away
        state.set('phase', 'putting_away')
        state.set('put_count', 0)
        send('put . in ' .. state.get('stow'))
        return
    end
    send('get ' .. herbs[idx] .. ' from here')
end

function M.on_start(args)
    local config = parse_args(args)

    if not config.room_key then
        log('herbmap requires a room key as first argument')
        set_mode('disable')
        return
    end
    if not config.dir then
        log('herbmap requires dir:<direction>')
        set_mode('disable')
        return
    end
    if config.gather ~= 'none' and config.gather ~= 'all' and config.gather ~= 'rare' then
        log('herbmap: invalid gather mode "' .. config.gather .. '", must be none|all|rare')
        set_mode('disable')
        return
    end

    state.set('current_key', config.room_key)
    state.set('dir', config.dir)
    state.set('gather', config.gather)
    state.set('stow', config.stow)
    state.set('wagon', config.wagon)
    state.set('phase', 'surveying')

    -- Load persisted map or initialize empty
    local map = state.get('herb_map') or {}
    state.set('herb_map', map)
    state.persist('herb_map')

    state.display('current_key', 'Room')
    state.display('phase', 'Phase')

    metrics.track('attempts', 'Attempts')
    metrics.track('finds', 'Finds')
    metrics.track('rooms', 'Rooms')

    -- Start surveying current room
    local key = state.get('current_key')
    herbmap.init_room(map, key)

    if herbmap.is_complete(map, key) then
        state.set('phase', 'moving')
        send(move_cmd(), 3500)
    else
        send('find herbs')
    end
end

M.reactions = {
    -- Herb found
    {
        match = herbmap.success_pattern,
        action = function(text)
            if state.get('phase') ~= 'surveying' then return end
            local herb = text:match('come across (.+)%.$')
            if not herb then return end
            local key = state.get('current_key')
            local map = state.get('herb_map')
            herbmap.record_herb(map, key, herb)
            state.set('herb_map', map)
            metrics.inc('attempts')
            metrics.inc('finds')
            -- Update per-herb metric for current room
            local herb_key = 'herb:' .. herb
            local tracked = state.get('tracked_herbs') or {}
            if not tracked[herb_key] then
                metrics.track(herb_key, herb)
                tracked[herb_key] = true
                state.set('tracked_herbs', tracked)
            end
            metrics.inc(herb_key)
            if herbmap.is_complete(map, key) then
                start_gathering_or_move()
            end
        end,
    },

    -- Searched but found nothing (miss)
    {
        match = herbmap.miss_patterns,
        condition = function() return #herbmap.miss_patterns > 0 end,
        action = function()
            if state.get('phase') ~= 'surveying' then return end
            local key = state.get('current_key')
            local map = state.get('herb_map')
            herbmap.record_miss(map, key)
            state.set('herb_map', map)
            metrics.inc('attempts')
            if herbmap.is_complete(map, key) then
                start_gathering_or_move()
            end
        end,
    },

    -- No usable herbs found — record and skip after threshold
    {
        match = herbmap.no_usable_patterns,
        condition = function() return #herbmap.no_usable_patterns > 0 end,
        action = function()
            if state.get('phase') ~= 'surveying' then return end
            local key = state.get('current_key')
            local map = state.get('herb_map')
            herbmap.record_herb(map, key, 'no_usable')
            state.set('herb_map', map)
            metrics.inc('attempts')
            local room = herbmap.get_room(map, key)
            local only_no_usable = true
            for name in pairs(room.herbs) do
                if name ~= 'no_usable' then only_no_usable = false break end
            end
            if only_no_usable and (room.herbs['no_usable'] or 0) >= herbmap.NO_USABLE_THRESHOLD then
                herbmap.mark_skip(map, key)
                state.set('herb_map', map)
                start_gathering_or_move()
            elseif herbmap.is_complete(map, key) then
                start_gathering_or_move()
            end
        end,
    },

    -- Cannot forage here — skip immediately
    {
        match = herbmap.no_forage_patterns,
        condition = function() return #herbmap.no_forage_patterns > 0 end,
        action = function()
            if state.get('phase') ~= 'surveying' then return end
            local key = state.get('current_key')
            local map = state.get('herb_map')
            herbmap.mark_skip(map, key)
            state.set('herb_map', map)
            start_gathering_or_move()
        end,
    },

    -- Unbusy: drive surveying and moving phases
    {
        match = strings.unbusy,
        action = function()
            local phase = state.get('phase')
            if phase == 'surveying' then
                send('find herbs')
            elseif phase == 'moving' then
                send(move_cmd())
            elseif phase == 'gathering' then
                gather_next_herb()
            end
        end,
    },

    -- Busy: retry last action after 1 second
    {
        match = 'You are in the middle of something',
        action = function()
            local phase = state.get('phase')
            if phase == 'surveying' then
                send('find herbs', 1000)
            elseif phase == 'moving' then
                send(move_cmd(), 1000)
            elseif phase == 'gathering' then
                local herbs = state.get('gather_list')
                local idx = state.get('gather_index')
                send('get ' .. herbs[idx] .. ' from here', 1000)
            elseif phase == 'putting_away' then
                send('put . in ' .. state.get('stow'), 1000)
            end
        end,
    },

    -- Gathering: picked up an herb, try for more of the same
    {
        match = 'You take',
        action = function()
            if state.get('phase') ~= 'gathering' then return end
            local herbs = state.get('gather_list')
            local idx = state.get('gather_index')
            send('get ' .. herbs[idx] .. ' from here')
        end,
    },

    -- Gathering: no more of this herb, move to next
    {
        match = {'You are already', 'You are unable to move'},
        action = function()
            if state.get('phase') ~= 'gathering' then return end
            state.set('gather_index', state.get('gather_index') + 1)
            gather_next_herb()
        end,
    },

    -- Putting away gathered herbs
    {
        match = {'You put', 'You must be carrying something to put it somewhere', "You can't"},
        action = function()
            local phase = state.get('phase')
            if phase == 'putting_away' then
                local count = state.get('put_count') + 1
                state.set('put_count', count)
                if count < 2 then
                    send('put . in ' .. state.get('stow'))
                else
                    -- Done putting away, move to next room
                    state.set('phase', 'moving')
                    metrics.inc('rooms')
                    send(move_cmd())
                end
            end
        end,
    },

    -- Arrived in new room
    {
        match = {'You arrive at', 'Your immediate surroundings are obscured by darkness'},
        action = function()
            if state.get('phase') ~= 'moving' then return end
            local key = state.get('current_key')
            local dir = state.get('dir')
            local new_key = herbmap.advance_key(key, dir)
            state.set('current_key', new_key)
            state.set('phase', 'surveying')
            reset_herb_metrics()

            local map = state.get('herb_map')
            herbmap.init_room(map, new_key)

            if herbmap.is_complete(map, new_key) then
                -- Already mapped, keep moving
                state.set('phase', 'moving')
                send(move_cmd(), 3500)
            else
                send('find herbs', 3500)
            end
        end,
    },

    -- Edge of map
    {
        match = herbmap.edge_patterns,
        action = function(text)
            if state.get('phase') ~= 'moving' then return end
            notify('Herbmap', 'Reached edge: ' .. text)
            set_mode('disable')
        end,
    },
}

return M
