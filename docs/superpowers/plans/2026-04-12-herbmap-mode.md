# Herbmap Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a mode that systematically surveys rooms for herb spawn rates, persists per-room data, optionally gathers rare/all herbs, and auto-advances along a directional path.

**Architecture:** Two files — `lib_herbmap.lua` (data layer: room key logic, data access, pattern tables, thresholds) and `herbmap.lua` (mode: arg parsing, state machine with surveying/gathering/moving phases, reactions). Persisted map data survives interruptions and skips already-completed rooms on re-run.

**Tech Stack:** Lua, Praetor game client API (`state`, `send`, `notify`, `log`, `set_mode`, `metrics`)

**Spec:** `docs/superpowers/specs/2026-04-12-herbmap-mode-design.md`

---

### Task 1: Library — Thresholds and Pattern Tables

**Files:**
- Create: `lib_herbmap.lua`

- [ ] **Step 1: Create `lib_herbmap.lua` with globals and pattern tables**

```lua
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
```

- [ ] **Step 2: Commit**

```bash
git add lib_herbmap.lua
git commit -m "feat(herbmap): add lib with thresholds and pattern tables"
```

---

### Task 2: Library — Room Key Logic

**Files:**
- Modify: `lib_herbmap.lua`

- [ ] **Step 1: Add `advance_key` function**

Append before the `return H` line:

```lua
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
```

- [ ] **Step 2: Verify logic mentally or via quick log test**

Key advancement rules:
- `boulder-nw-1-n-1` + `n` → `boulder-nw-1-n-2` (same dir, increment)
- `boulder-nw-1-n-1` + `e` → `boulder-nw-1-n-1-e-1` (new dir, append)
- `boulder` + `n` → `boulder-n-1` (base landmark, no prior segments)

- [ ] **Step 3: Commit**

```bash
git add lib_herbmap.lua
git commit -m "feat(herbmap): add room key advancement logic"
```

---

### Task 3: Library — Data Access Functions

**Files:**
- Modify: `lib_herbmap.lua`

- [ ] **Step 1: Add data access functions**

Append before the `return H` line:

```lua
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
```

- [ ] **Step 2: Commit**

```bash
git add lib_herbmap.lua
git commit -m "feat(herbmap): add data access and gather-list functions"
```

---

### Task 4: Mode — Argument Parsing and on_start

**Files:**
- Create: `herbmap.lua`

- [ ] **Step 1: Create `herbmap.lua` with arg parsing and on_start**

```lua
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
```

- [ ] **Step 2: Commit**

```bash
git add herbmap.lua
git commit -m "feat(herbmap): add mode scaffold with arg parsing and on_start"
```

---

### Task 5: Mode — Surveying Phase Reactions

**Files:**
- Modify: `herbmap.lua`

- [ ] **Step 1: Add surveying reactions to `M.reactions`**

Replace `M.reactions = {}` with:

```lua
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

}
```

- [ ] **Step 2: Add the `start_gathering_or_move` helper**

Add above `M.reactions`, after the `parse_args` function:

```lua
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
```

- [ ] **Step 3: Add unbusy reaction for surveying**

Append to `M.reactions`:

```lua
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
```

- [ ] **Step 4: Commit**

```bash
git add herbmap.lua
git commit -m "feat(herbmap): add surveying phase reactions and unbusy driver"
```

---

### Task 6: Mode — Gathering Phase Reactions

**Files:**
- Modify: `herbmap.lua`

- [ ] **Step 1: Add gathering helper function**

Add after `start_gathering_or_move`:

```lua
local function gather_next_herb()
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
```

- [ ] **Step 2: Add gathering reactions**

Append to `M.reactions`:

```lua
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
        match = 'You are already',
        action = function()
            if state.get('phase') ~= 'gathering' then return end
            state.set('gather_index', state.get('gather_index') + 1)
            gather_next_herb()
        end,
    },

    -- Gathering: stow command completed, start picking up herbs
    {
        match = 'You put',
        action = function()
            local phase = state.get('phase')
            if phase == 'gathering' then
                gather_next_herb()
            elseif phase == 'putting_away' then
                local count = state.get('put_count') + 1
                state.set('put_count', count)
                if count < 2 then
                    send('put . in ' .. state.get('stow'))
                else
                    -- Done putting away, move to next room
                    state.set('phase', 'moving')
                    metrics.inc('rooms')
                    local dir = state.get('dir')
                    send(state.get('wagon') and ('pull wagon ' .. dir) or ('go ' .. dir))
                end
            end
        end,
    },
```

- [ ] **Step 3: Commit**

```bash
git add herbmap.lua
git commit -m "feat(herbmap): add gathering phase reactions"
```

---

### Task 7: Mode — Moving Phase and Edge Detection

**Files:**
- Modify: `herbmap.lua`

- [ ] **Step 1: Add movement and edge reactions**

Append to `M.reactions`:

```lua
    -- Arrived in new room
    {
        match = 'You arrive at',
        action = function()
            if state.get('phase') ~= 'moving' then return end
            local key = state.get('current_key')
            local dir = state.get('dir')
            local new_key = herbmap.advance_key(key, dir)
            state.set('current_key', new_key)
            state.set('phase', 'surveying')

            local map = state.get('herb_map')
            herbmap.init_room(map, new_key)

            if herbmap.is_complete(map, new_key) then
                -- Already mapped, keep moving
                state.set('phase', 'moving')
                send(state.get('wagon') and ('pull wagon ' .. dir) or ('go ' .. dir))
            else
                send('find herbs')
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
```

- [ ] **Step 2: Add the closing `}` for reactions and `return M`**

Make sure `M.reactions` is properly closed and the file ends with `return M`.

- [ ] **Step 3: Commit**

```bash
git add herbmap.lua
git commit -m "feat(herbmap): add movement and edge detection reactions"
```

---

### Task 8: Final Review and Cleanup

**Files:**
- Review: `lib_herbmap.lua`
- Review: `herbmap.lua`

- [ ] **Step 1: Read both files end-to-end**

Verify:
- `lib_herbmap.lua` has: thresholds, pattern tables, `advance_key`, all data access functions, `get_herbs_to_gather`.
- `herbmap.lua` has: `parse_args`, `on_start`, `start_gathering_or_move`, `gather_next_herb`, and all reactions (success, no_herbs, unbusy, You take, You are already, You put, You arrive at, edge patterns).
- All `M.reactions` entries have proper commas between them and the table is properly closed.
- `return M` is at the end of `herbmap.lua`.

- [ ] **Step 2: Verify `state.persist('herb_map')` is called in `on_start`**

This ensures the map survives mode restarts.

- [ ] **Step 3: Check that the `stow` reaction path is correct**

The `'You put'` reaction fires for both the initial `stow` command in gathering and the `put . in <stow>` at the end. Verify the phase guards correctly distinguish these:
- `phase == 'gathering'` + `'You put'` → stow completed, start picking herbs
- `phase == 'putting_away'` + `'You put'` → count puts, after 2 move on

- [ ] **Step 4: Commit any fixes**

```bash
git add herbmap.lua lib_herbmap.lua
git commit -m "chore(herbmap): final review cleanup"
```

---

### Task 9: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add herbmap entries to Shared Libraries section**

Add to the shared libraries list:

```markdown
- **lib_herbmap.lua** — Herbalism mapping: room key logic, data access, pattern tables, thresholds
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add herbmap library to CLAUDE.md shared libraries"
```
