local H = {}

H.RARE_THRESHOLD = 25
H.ATTEMPT_TARGET = 100
H.NO_USABLE_THRESHOLD = 5

H.success_pattern = 'You search the area carefully and come across *.'

H.miss_patterns = {
    'You search the area carefully, but fail to find any usable herbs.',
}

H.no_usable_patterns = {  -- may trigger in rooms with only uncommon/rare herbs
    'You search the area carefully and come to the conclusion there are no usable herbs here.',
}

H.no_forage_patterns = {  -- room doesn't support herbs at all
    'You cannot forage here',
}

-- Maps singular herb name (from find pattern) to get keyword
H.herb_keywords = {
    ['a shriveled black piece of fruit'] = 'fruit',
    ['an enormous brownish-green leaf'] = 'brownish-green lea',
    ['a round reddish leaf'] = 'reddish lea',
    ['a bunch of grapes'] = 'grapes',
    ['a small furry green leaf'] = 'furry green',
    ['a tiny soft blue flower'] = 'soft blue flower',
    ['a small scarlet coned flower'] = 'scarlet coned',
    ['a fleshy bulbous brown mushroom cap'] = 'bulbous brown',
    ['a fleshy thick brown stem'] = 'brown stem',
    ['a tiny wrinkled black seedpod'] = 'seedpod',
    ['a green stem covered with hairs'] = 'stem',
    ['a spherical magenta flower atop a spiky thread-draped grey globe'] = 'flower',
    ['a clumped dark brown root'] = 'root',
    ['a red berry covered in pale gold seeds'] = 'gold seed',
    ['a small fur-covered heart-shaped leaf'] = 'heart-shaped',
    ['a violet flower'] = 'flower',
    ['a small crowned navy blue berry'] = 'blue berr',
    ['a thick squat brown root'] = 'brown root',
    ['a blue-ish mushroom cap'] = 'cap',
    ['a dense cluster of tiny creamy white flowers at the end of a branch'] = 'flower',
    ['a piece of lacy red moss speckled with black'] = 'moss',
    ['a ridged brilliant red mushroom cap'] = 'cap',
    ['a slender yellow stem'] = 'stem',
    ['a yellow fruit with a thick peel'] = 'fruit',
    ['a straight brown thorn that is very hard'] = 'thorn',
    ['a deep blue flower with white edges'] = 'flower',
    ['a thin multitiered white flower'] = 'flower',
    ['a tangle of thin white roots'] = 'root',
    ['a long multi-pronged leaf'] = 'multi-prong',
    ['a heavy dark green frond'] = 'frond',

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
    if herb_name ~= 'no_usable' and not H.herb_keywords[herb_name] then
        notify('Unknown herb', herb_name)
    end
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
    if not room or gather_mode == 'none' or room.attempts == 0 then return {} end
    local herbs = {}
    for name, count in pairs(room.herbs) do
        if name ~= 'no_usable' then
            if gather_mode == 'all' then
                herbs[#herbs + 1] = name
            elseif gather_mode == 'rare' then
                local pct = (count / room.attempts) * 100
                if pct < H.RARE_THRESHOLD then
                    herbs[#herbs + 1] = name
                end
            end
        end
    end
    return herbs
end

return H
