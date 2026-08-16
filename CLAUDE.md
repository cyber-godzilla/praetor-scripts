# CLAUDE.md

## Project Overview

This is **praetor-scripts**, a collection of Lua automation scripts for the [Praetor](https://github.com/cyber-godzilla/praetor) game client for The Eternal City (TEC).

Scripts are loaded by Praetor from configurable directories. Each `.lua` file that returns a table with `reactions` and/or `on_start` is registered as a mode. Other `.lua` files are available via `require()`.

## Script Structure

A mode file returns a table:

```lua
local M = {}

function M.on_start(args)
    -- Called when mode is activated via /mode <name> [args]
end

function M.on_stop()
    -- Called when mode is deactivated (optional)
end

M.reactions = {
    {
        match = 'pattern',           -- string or table of strings, supports * and ? wildcards
        action = function(text) end, -- called when pattern matches game text
        condition = function() end,  -- optional: only fire if returns true
        delay = 500,                 -- optional: delay in ms before action
    },
}

return M
```

A library file is loaded via `require()`:

```lua
local S = {}
S.patterns = {'pattern1', 'pattern2'}
return S
```

## Lua API (provided by Praetor)

```lua
send(command [, delay_ms])           -- queue game command
set_mode(name [, {args}])           -- switch mode
notify(title, message)               -- desktop notification
log(message)
random_item(table)
time.now() / time.since(ms)
state.get(key) / state.set(key, val) -- per-mode state
state.persist(key)                   -- mark key for disk persistence
state.display(key, label)            -- declare state item for sidebar display
state.mode                           -- read-only: current mode name
status.health / status.fatigue / status.encumbrance / status.satiation
metrics.track(key, label)            -- declare a metric for current session
metrics.inc(key) / metrics.dec(key)  -- increment/decrement a metric
metrics.set(key, value) / metrics.get(key)
set_timeout(fn, ms) / set_interval(fn, ms) / clear_timer(id)
```

## Macro Mode Architecture

All combat macros (macro, chain_macro, falx_macro, lizard_macro) share a common pattern:
- `[Success:]` handler uses `combat.handle_success(text, attack_fn)` which dispatches kills, KOs, and rotation in one place
- Attack rotation only happens on player attack rolls (50+ patterns in `strings.attack_roll`), not stun/drag/ev successes
- Anti-idle recovery: if 5+ seconds since last command, next `[Success:]` triggers an attack
- Combat macros run indefinitely and have no completion point, so they do not chain (except `lizard_macro`, which chains when it runs out of targets)
- Armor absorption tracked automatically within `handle_success` via `combat.track_absorb(text)`

## Shared Libraries

- **lib_strings.lua** — Pattern string tables shared across modes (unbusy, must_stand, etc.)
- **lib_combat.lua** — Shared combat functions: attack rotation, kill/KO handling, approach, absorption tracking
- **lib_chain_macro.lua** — Chain macro–specific patterns (chainblade windup)
- **lib_falx_macro.lua** — Falx macro–specific patterns (stun roll, stun, drag, eviscerate)
- **lib_lizard_macro.lua** — Lizard macro–specific patterns (aralex dead)
- **lib_courses.lua** — Obstacle course patterns
- **lib_learn_languages.lua** — Language lesson patterns (man/woman teacher)
- **lib_locksmithing.lua** — Locksmithing patterns (customer arrivals, greetings)
- **lib_herbmap.lua** — Herbalism mapping: room key logic, data access, pattern tables, thresholds
- **lib_loot.lua** — Loot shorthand aliases for corpse types
- **lib_wagon.lua** — Wagon sell-list aliases for vendors
- **lib_after.lua** — Mode chaining: `after.parse(args)` strips the `after:<mode>` token in `on_start`, `after.finish([fallback])` chains onward at completion instead of `set_mode('disable')`
- **lib_route.lua** — Wagon-route legs: `route.mode(steps, on_done)` builds a whole mode from an ordered list of `pull wagon ...` / `open ...` commands, handling the differing advance timing of each (see Route Legs)

## Route Legs (`lib_route`)

Long wagon hauls are built with `lib_route.lua` instead of hand-written reaction tables. A leg file declares its command list and a completion callback, and `route.mode()` returns the mode table:

```lua
local route = require('lib_route')
local after = require('lib_after')

return route.mode(
    { 'pull wagon ne 3 e 8 n 5', 'open gate', 'pull wagon e 3 s 1' },
    function() after.finish('next_leg') end
)
```

Advance timing differs by command type and is handled inside the library: `open` advances on confirmation; a pull covering more than one room in a direction emits `You stop pulling` and advances on the following unbusy; an all-single-room pull emits no stop marker and advances by counting one unbusy per room.

Split a haul into one mode per leg — a run broken mid-haul then resumes by re-running that leg alone. Legs call `after.parse(args)` in `on_start`, so they honor `after:` like any other completing mode.

## Mode Chaining (`after:`)

Any mode that runs to completion supports an `after:<mode>` argument that switches to `<mode>` on finish instead of stopping. Implemented via `lib_after.lua`: call `after.parse(args)` at the top of `on_start` (it strips the token, in any position, and returns the remaining args), and replace each successful-completion `set_mode('disable')` with `after.finish()` (or `after.finish('idle')` etc. to chain elsewhere by default). Arg-validation aborts keep bare `set_mode('disable')` so a failed run does not chain. Chains nest — each mode carries its own `after:`.

## File Naming

- Mode files are named after their mode: `macro.lua` → `/mode macro`
- Library files use `lib_` prefix: `lib_strings.lua`, `lib_combat.lua`
- All files are in a flat directory structure
