local H = {}

H.RARE_THRESHOLD = 25
H.ATTEMPT_TARGET = 1000

H.success_pattern = 'You search the area carefully and come across *.'

H.miss_patterns = {}      -- user-populated: "searched but found nothing" messages

H.no_herbs_patterns = {   -- room doesn't support herbs at all
    'You search the area carefully and come to the conclusion there are no usable herbs here.',
}

H.edge_patterns = {
    "You can't go that direction",
    "The water is too deep",
}

function H.advance_key(key, direction)
    local base, last_dir, last_count = key:match('^(.+)-(%a+)-(%d+)$')
    if not base then
        return key .. '-' .. direction .. '-1'
    end
    last_count = tonumber(last_count)
    if last_dir == direction then
        return base .. '-' .. direction .. '-' .. (last_count + 1)
    else
        return key .. '-' .. direction .. '-1'
    end
end

function H.get_room(map, key)
    return map[key]
end

function H.init_room(map, key)
    if not map[key] then
        map[key] = { attempts = 0, herbs = {}, skip = false }
    end
    return map[key]
end

function H.record_herb(map, key, herb_name)
    local room = H.init_room(map, key)
    room.attempts = room.attempts + 1
    room.herbs[herb_name] = (room.herbs[herb_name] or 0) + 1
end

function H.record_miss(map, key)
    local room = H.init_room(map, key)
    room.attempts = room.attempts + 1
end

function H.mark_skip(map, key)
    local room = H.init_room(map, key)
    room.skip = true
end

function H.is_complete(map, key)
    local room = map[key]
    if not room then return false end
    return room.attempts >= H.ATTEMPT_TARGET or room.skip
end

function H.get_herbs_to_gather(map, key, gather_mode)
    local room = map[key]
    if not room or gather_mode == 'none' then return {} end
    local herbs = {}
    for name, count in pairs(room.herbs) do
        if gather_mode == 'all' then
            herbs[#herbs + 1] = name
        elseif gather_mode == 'rare' then
            local pct = (count / room.attempts) * 100
            if pct < H.RARE_THRESHOLD then
                herbs[#herbs + 1] = name
            end
        end
    end
    return herbs
end

return H
