# praetor-scripts
Repository of Lua scripts for use with praetor

## Expected Macros

These scripts assume certain in-game macros are configured on your character. Combat modes will not work without them.

**All combat modes** (macro, chain_macro, falx_macro, lizard_macro):
- `at1`-`at6` -- Attack rotation slots (chain_macro also uses `at7`)
- `app1` -- Approach first target ('app 1 <target>' or your weapon's approach move)
- `adv1` -- Advance toward first target (Melee advance, 'advance 1 <target>')
- `k1` -- Kill first target ('kill 1 <target>', 'fslash 1 <target>' for falx)
- `r` -- Rewield weapon ('wield <weapon>')
- `doStance` -- Uses your weapon's stance move (Should only be necessary before you perfect stance)

**Falx macro only:**
- `st1` -- Stun first target ('bash 1 <target> head')
- `dr` -- Drag target ('ankle <target>')
- `ev` -- Eviscerate target ('evisc <target>')

**Chain macro only:**
- `nm` -- No-mind attack

## Other Modes

**Locksmithing:**
- `board` -- Rotates locksmithing skills on the board, optionally accepts and completes jobs. Pass `no_jobs` to just train.
- `lock_job` -- Accepts a locksmithing job from an NPC. `/mode lock_job citizen|trader|sailor`
- `wire_to_picks` -- Forges broken wires from lockpick fashioning into functional lockpicks.

**Training:**
- `courses_three` / `courses_four` -- Runs 3- or 4-obstacle courses automatically.
- `learn_languages` -- Repeats language lesson phrases from man/woman teachers.

**Utility:**
- `loot` -- Loops through corpses, taking pipe-delimited items. `/mode loot bronze|alanti|retalq`
- `wagon` -- Sells wagon contents to a vendor. Supports aliases in `lib_wagon.lua`.
- `empty_containers` -- Empties all containers of a type between containers. `/mode empty_containers sack wagon wagon`
- `remove_bandages` -- Iterates through removing all bandages.
- `repeat` -- Sends a command every time you're no longer busy.
- `idle` -- Waits for fatigue to recover, then chains onward (see Mode Chaining).
- `disable` -- Stops all automation.

**Navigation:**
- `east_to_romulus` / `fran_to_ne` / `fran_ne_to_bath` -- Automated travel routes.

## Mode Chaining (`after:`)

Any mode that runs to completion can hand off to another mode with an
`after:<mode>` argument. When the mode finishes, it switches to `<mode>`
instead of stopping. Without an `after:` argument the mode stops (switches
to `disable`) as before.

```
/mode loot bronze|alanti after:wagon      # loot corpses, then sell to a vendor
/mode wagon romulus after:idle            # sell, then rest until fatigue recovers
/mode idle after:macro                    # rest, then start fighting
```

Chains nest: each mode carries its own `after:`, so
`/mode east_to_romulus after:wagon` can lead to a `wagon` run that itself
carries `after:idle`, and so on.

The `after:` token may appear in any argument position, so it never
collides with a mode's own positional arguments (item names, directions,
`key:value` options, etc.).

Modes gain this behavior by importing `lib_after.lua`: call
`after.parse(args)` in `on_start` to strip the token, and `after.finish()`
in place of `set_mode('disable')` at each completion point. Some modes pass
a fallback (e.g. `after.finish('idle')`) to chain somewhere other than
`disable` by default. Combat macros (`macro`, `chain_macro`, `falx_macro`,
`lizard_macro`, `priority_macro`) run indefinitely and have no completion
point, so they do not support `after:` (except `lizard_macro`, which chains
when it runs out of fatigue).

## Route Legs (`lib_route`)

Long wagon hauls are built from `lib_route.lua` rather than written out by
hand. A route file declares an ordered list of `pull wagon ...` / `open ...`
commands and a completion callback, and `lib_route` turns that into a full
mode:

```lua
local route = require('lib_route')
local after = require('lib_after')

return route.mode(
    { 'pull wagon ne 3 e 8 n 5', 'open gate', 'pull wagon e 3 s 1' },
    function() after.finish('next_leg') end
)
```

`lib_route` handles the advance timing, which differs by command type: an
`open` advances as soon as the game confirms it, while a `pull` waits for the
movement to finish. Pulls that cover more than one room in a direction emit a
`You stop pulling` marker and advance on the unbusy line following it; pulls
made only of single-room legs never emit that marker, so those advance by
counting one unbusy per room instead.

Split a haul into one mode per leg. Because each leg is its own mode, a run
broken by a disconnect or an interruption resumes by re-running just that leg
instead of the whole route. Legs honor `after:` like any other completing
mode, so a leg's tail can be overridden at the command line
(`/mode <leg> after:disable`) or chained onward into a `wagon` sell that
carries its own `after:`.

