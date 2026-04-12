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

local function start_gathering_or_move()
    local gather = state.get('gather')
    local key = state.get('current_key')
    local map = state.get('herb_map')

    if gather ~= 'none' then
        local herbs = herbmap.get_herbs_to_gather(map, key, gather)
        if #herbs > 0 then
            state.set('phase', 'gathering')
            state.set('gather_list', herbs)
            state.set('gather_index', 1)
            send('stow ' .. state.get('stow'))
            return
        end
    end

    state.set('phase', 'moving')
    metrics.inc('rooms')
    local dir = state.get('dir')
    send(state.get('wagon') and ('pull wagon ' .. dir) or ('go ' .. dir))
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
    metrics.track('rooms', 'Rooms')

    -- Start surveying current room
    local key = state.get('current_key')
    herbmap.init_room(map, key)

    if herbmap.is_complete(map, key) then
        state.set('phase', 'moving')
        send(config.wagon and ('pull wagon ' .. config.dir) or ('go ' .. config.dir))
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

    -- Room doesn't support herbs, skip permanently
    {
        match = herbmap.no_herbs_patterns,
        condition = function() return #herbmap.no_herbs_patterns > 0 end,
        action = function()
            if state.get('phase') ~= 'surveying' then return end
            local key = state.get('current_key')
            local map = state.get('herb_map')
            herbmap.mark_skip(map, key)
            state.set('herb_map', map)
            start_gathering_or_move()
        end,
    },

    -- Unbusy: fire next find herbs during surveying
    {
        match = strings.unbusy,
        action = function()
            local phase = state.get('phase')
            if phase == 'surveying' then
                send('find herbs')
            end
        end,
    },
}

return M
