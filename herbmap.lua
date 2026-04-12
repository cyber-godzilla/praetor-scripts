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

M.reactions = {}

return M
