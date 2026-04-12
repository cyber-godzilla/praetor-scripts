# Herbalism Mapping Mode (`herbmap`)

## Overview

A mode for systematically surveying rooms to map herb spawn rates. Walks a linear path from a known landmark, running `find herbs` a configurable number of times per room, recording what's found, and optionally gathering rare or all herbs before moving on.

## Invocation

```
/mode herbmap <room-key> dir:<direction> [gather:all|rare|none] [stow:<container>] [wagon:true|false]
```

- `args[1]` — starting room key (required, positional). Encodes a path from a known landmark, e.g. `boulder-nw-1-n-1`.
- `dir:<direction>` — direction to travel between rooms (required). e.g. `dir:n`, `dir:sw`.
- `gather:all|rare|none` — which herbs to pick up after surveying a room (default: `none`).
- `stow:<container>` — where to put gathered herbs (default: `my backpack`).
- `wagon:true|false` — use `pull wagon <dir>` instead of `go <dir>` for movement (default: `false`).

## Files

### `herbmap.lua` (mode)

Owns the state machine, reactions, and `on_start` argument parsing.

### `lib_herbmap.lua` (library)

Owns room key logic, data access, pattern tables, and configurable thresholds.

## Configurable Globals (`lib_herbmap.lua`)

```lua
RARE_THRESHOLD = 25      -- gather herbs under this % occurrence
ATTEMPT_TARGET = 1000    -- attempts per room before moving on
```

## Room Key Logic

Room keys encode a path from a known landmark as alternating direction-count segments:

```
boulder-nw-1-n-1
```

**Key advancement** given a current key and a travel direction:

- Parse the last segment (last direction + last count).
- If the travel direction matches the last direction, increment the count: `boulder-nw-1-n-1` + `n` = `boulder-nw-1-n-2`.
- If the travel direction differs, append a new segment: `boulder-nw-1-n-1` + `e` = `boulder-nw-1-n-1-e-1`.

### Data Access Functions

- `get_room(map, key)` — returns the room table or nil.
- `init_room(map, key)` — creates `{ attempts = 0, herbs = {}, skip = false }` if key does not exist.
- `record_herb(map, key, herb_name)` — increments `herbs[herb_name]` by 1 and `attempts` by 1.
- `record_miss(map, key)` — increments `attempts` by 1 (searched but found nothing).
- `mark_skip(map, key)` — sets `skip = true` on the room.
- `is_complete(map, key)` — returns true if `attempts >= ATTEMPT_TARGET` or `skip == true`.
- `advance_key(key, direction)` — returns the next room key per the advancement rules above.

### Pattern Tables

```lua
success_pattern = 'You search the area carefully and come across *.'
miss_patterns = {}        -- user-populated: searched but found nothing
no_herbs_patterns = {     -- room doesn't support herbs at all
    'You search the area carefully and come to the conclusion there are no usable herbs here.',
}
edge_patterns = {         -- user-extensible
    "You can't go that direction",
    "The water is too deep",
}
```

## Persisted Data Structure

A single persisted table keyed by room label:

```lua
{
    ["boulder-nw-1-n-2"] = { attempts = 1000, herbs = { ["a sprig of wild garlic"] = 47, ["some comfrey"] = 112 }, skip = false },
    ["boulder-nw-1-n-3"] = { attempts = 450, herbs = { ... }, skip = false },   -- interrupted, will resume
    ["boulder-nw-1-n-4"] = { attempts = 0, herbs = {}, skip = true },           -- no herbs here
}
```

Persisted via `state.persist()` and updated after every attempt for crash resilience.

## State Machine

### Phase: `surveying`

1. On entering a room (or `on_start`), compute the current room key.
2. If `is_complete(key)`, skip to movement phase.
3. Send `find herbs`.
4. On match for `success_pattern`: extract herb name from wildcard, call `record_herb(map, key, herb_name)`. Wait for unbusy, send next `find herbs`.
5. On match for "found nothing" patterns: call `record_miss(map, key)`. Wait for unbusy, send next `find herbs`.
6. On match for `no_herbs_patterns`: call `mark_skip(map, key)`, transition to movement phase.
7. Persist map data after each attempt.
8. When `attempts >= ATTEMPT_TARGET`, transition to gathering phase (if `gather` is not `none`) or movement phase.

### Phase: `gathering`

Runs once per room after surveying completes. Only entered if `gather` is `all` or `rare`.

1. Build a list of herbs to gather:
   - `gather:all` — all herbs found in this room.
   - `gather:rare` — only herbs where `(count / attempts * 100) < RARE_THRESHOLD`.
2. Send `stow <stow>`.
3. For each herb in the list:
   - Send `get <herb> from here`.
   - On `'You take'` — send `get <herb> from here` again (loop until exhausted).
   - On `'You are already'` (no more of that herb on the ground) — move to next herb in the list.
4. After all herbs gathered, send `put . in <stow>` twice (two puts to handle full hands).
5. Wait for unbusy after the second put, then transition to movement phase.

### Phase: `moving`

1. If `wagon:true`: send `pull wagon <dir>`. If `wagon:false`: send `go <dir>`.
2. On match `'You arrive at'`: call `advance_key(current_key, direction)`, set new current key, transition to surveying phase.
3. On match for `edge_patterns`: notify user ("Reached edge: <matched text>"), disable mode.

## Error Handling

- Missing required args (`args[1]` or `dir`): log error, disable mode.
- Session interruption: map data persists after each attempt, so restarting the mode with the same room key resumes where it left off. Rooms with fewer than `ATTEMPT_TARGET` attempts continue surveying.
- Edge of map: notification + mode disable so user can re-invoke with a different direction.
