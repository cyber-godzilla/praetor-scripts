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

## Mode Metadata (`usage` / `desc` / `chains` / `hidden`)

Every mode declares what it is and what arguments it takes, so the client can
show that information as you type instead of making you open the file. Praetor
reads these optional fields off the mode table when it loads a script:

```lua
local M = {}

M.usage = '<item|alias> [corpse#]'
M.desc = 'Take a pipe-delimited item list from every corpse in the room'
M.chains = true
M.hidden = false   -- true keeps it out of the hint; it still runs
```

Typing `/mode loot ` in the client then surfaces the signature and the
description, and `/list` shows each mode with its own line rather than a bare
name.

**`usage`** — the mode's arguments, without the mode name (the client already
shows that). Omit the field entirely when a mode takes no arguments. The
notation follows what the scripts already used in their header comments:

| Notation | Meaning |
|---|---|
| `<item>` | required argument |
| `[corpse#]` | optional argument |
| `[nokill]` | literal flag word, passed verbatim |
| `a\|b\|c` | pick one of these values |
| `key:<value>` | named option in colon syntax |
| `[target...]` | repeatable argument |

**`desc`** — one line, sentence case, no trailing period. Describe what the
mode does, not how it works.

**`chains`** — set to `true` only when the mode genuinely honors `after:`, which
means both that `on_start` calls `after.parse(args)` and that a completion point
calls `after.finish()`. When set, the client appends `[after:<mode>]` to the
displayed signature, so declaring it on a mode that ignores the token advertises
something that will not happen. Combat macros never set it (they have no
completion point), and a route leg whose completion callback hardcodes its own
`set_mode` must leave it unset even though `lib_route` parses the token.

**`hidden`** — set to `true` to keep the mode out of the command hint. For
helpers that are real modes but noise while typing: an internal route leg, or a
mode that exists to be chained into rather than started by hand. It hides the
mode from the hint *only* — the mode stays loaded, the mode picker still lists
it with its description, and `/mode <name>` still runs it normally. A hidden
mode is invisible to the hint even when its name is typed in full, at which
point the hint shows its generic `/mode` signature exactly as it does for a name
that does not exist, so a hidden mode cannot be told apart from an absent one.

Note that clearing `usage` and `desc` does **not** hide a mode; it still appears
in the hint as a bare name with nothing beside it. Only `hidden` removes it.
The worked example is `private/farm_rps.lua` — a keepalive mode kept out of the
hint because it is started deliberately and rarely, never browsed for. (That
directory is gitignored, so the file itself is local-only; the declaration is
all there is to it:)

```lua
M.usage = '[minutes]'
M.desc = 'Send randomized keepalives for a set duration (default 60 minutes)'
M.hidden = true
```

Route legs have no `M` table of their own, so they pass the same metadata as an
optional third argument to `route.mode`:

```lua
return route.mode(
    { 'pull wagon ne 3 e 8 n 5' },
    function() after.finish('next_leg') end,
    {
        desc = 'Pull the wagon from the gate to the intersection',
        chains = true,
        hidden = true,
    }
)
```

Interior legs are the main users of `hidden`. A circuit's middle legs are
started by the leg before them rather than browsed for, so offering each one in
the hint is noise — but they stay loaded, so `/mode <leg>` still resumes a run
that broke partway through, which is the whole reason a haul is split into legs.

All three fields are optional and purely descriptive — nothing validates
arguments against `usage`, and a mode that declares none behaves exactly as it
always has. They exist so the client can describe the corpus accurately, which
means keeping them true is the whole point: update them in the same commit that
changes a mode's arguments.

