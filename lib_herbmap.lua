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

return H
