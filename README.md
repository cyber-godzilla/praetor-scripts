# praetor-scripts
Repository of Lua scripts for use with praetor

The current scripts require Praetor v0.5.2 or newer. Reaction patterns may use
`^` and `$` to anchor matches to the start or end of a game-text line.

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
- `locksmith` -- Unjams and unlocks containers in bulk, with configurable source, disposition, open/empty behavior, and difficulty skipping. `/mode locksmith cont:chest from:wagon to:n open:true`
- `unlock_all` -- Unlocks, opens, and drops containers from a source while moving irrecoverably difficult or repeatedly worsened jams to a reject container. A single-word source needs no quotes (`/mode unlock_all sack`); quote grouped sources (`/mode unlock_all "2 sack"`). Named options remain available: `/mode unlock_all from:"2 sack" reject:"worn large sack" targets:chest|coffer|trunk`

**Herbalism:**
- `herbmap` -- Surveys rooms for herb spawn rates, persisting per-room data, optionally gathering. `/mode herbmap boulder dir:n gather:rare`

**Training:**
- `courses_three` / `courses_four` -- Runs 3- or 4-obstacle courses automatically.
- `learn_languages` -- Repeats language lesson phrases from man/woman teachers.

**Utility:**
- `loot` -- Loops through corpses taking pipe-delimited items, with optional rotating stowage. Pass `drop:<item|list>` to discard matching items, `from:<noun>` to loot another source, or `stow:<container> stow_start:<n>` to rotate containers as they fill. `/mode loot hand stow:pack stow_start:3 drop:rawhide|hide`
- `wagon` -- Sells wagon contents to a vendor. Supports aliases in `lib_wagon.lua`.
- `empty_containers` -- Empties all containers of a type between containers. `/mode empty_containers sack wagon wagon`
- `drag_paces` -- Drags an item along a path one room at a time, for loads that cannot be pulled like a wagon. `/mode drag_paces sled n:3 e:8 s`
- `toss_sacks` -- Gets and tosses every item of a type in a direction. `/mode toss_sacks north what:pouch`. Pass `from:<container>` to get out of a container and `try_drag:true` to drag it along after each toss.
- `remove_bandages` -- Iterates through removing all bandages.
- `repeat` -- Sends `.` (a repeat-last-command macro) every time you're no longer busy.
- `idle` -- Waits for fatigue to recover, then runs a completion handoff.
- `disable` -- Stops all automation.

**Navigation:**
- `east_to_romulus` / `fran_to_ne` / `fran_ne_to_bath` -- Automated travel routes.

## Completion Handoffs (`after_mode:`, `after_do:`, `after_ps:`)

Any mode that runs to completion can hand off to a mode, send one game command,
or run a PraetorScript expression. Without an `after_*:` argument, the mode
stops (switches to `disable`) as before.

```
/mode loot bronze|alanti after_mode:wagon romulus
/mode wagon romulus after_do:look in wagon
/mode idle after_ps:stand&&climb wall;;look
```

The first `after_mode:`, `after_do:`, or `after_ps:` token begins the handoff
payload. It and everything after it belong to the handoff, so put the suffix
after the current mode's arguments. `after_mode:` treats the first payload
token as the mode and passes all remaining tokens to that mode's `on_start`.
`after_do:` joins the payload as one game command. `after_ps:` joins it as one
PraetorScript expression and runs it through the normal typed-input parser.

Mode chains nest naturally because later handoff tokens are passed as arguments
to the next mode:

```
/mode loot hand after_mode:wagon romulus after_mode:idle
```

The legacy `after:<mode>` spelling remains supported for compatibility, but it
can pass only the mode name and consumes only its own token.

Modes gain this behavior by importing `lib_after.lua`: call
`after.parse(args)` in `on_start` to strip the token, and `after.finish()`
in place of `set_mode('disable')` at each completion point. Some modes pass
a fallback (e.g. `after.finish('idle')`) to chain somewhere other than
`disable` by default. Combat macros (`macro`, `chain_macro`, `falx_macro`,
`lizard_macro`) run indefinitely and have no completion
point, so they do not support completion suffixes (except `lizard_macro`, which ends
when fatigue runs out, chaining to `idle` by default).

## Route Legs (`lib_route`)

Long wagon hauls are built from `lib_route.lua` rather than written out by
hand (`east_to_romulus` predates the library and remains hand-written). A
route file declares an ordered list of `pull wagon ...` / `open ...`
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
instead of the whole route. Legs honor completion suffixes like any other
completing mode, so a leg's tail can be overridden at the command line
(`/mode <leg> after_mode:disable`) or handed onward into a `wagon` sell.

## Walking Legs (`lib_walk`)

On-foot travel legs are built from `lib_walk.lua`, the walking analog of
`lib_route`. A leg declares an ordered step list — `walk to <place>`
path-walks, multi-direction `walk <spec>` commands, and explicit-marker
steps for everything else — and `walk.mode()` turns it into a full mode:

```lua
local walk = require('lib_walk')
local after = require('lib_after')

return walk.mode(
    { 'walk to market', 'walk e 2 s 1', {cmd = 'u', match = 'You climb'} },
    function() after.finish('next_leg') end,
    { desc = 'Walk to the market stall', chains = true }
)
```

A `walk to` step advances on the pathing completion line ("having reached
your destination"), a `walk <spec>` step on `You stop walking.`, and any
other command on its explicit `match`. A step whose command incurs a
roundtime (unlocking a door, say) takes `unbusy = true`: the next command
is held until the unbusy line that follows the step's match. Single-pace
moves should be bare directions with an arrival match — a one-room `walk`
command is not trusted to emit a stop line. Legs honor completion suffixes and
resume like route legs: re-run the leg.

## Mode Metadata (`usage` / `desc` / `chains` / `hidden`)

Every mode declares what it is and what arguments it takes, so the client can
show that information as you type instead of making you open the file. Praetor
reads these optional fields off the mode table when it loads a script:

```lua
local M = {}

M.usage = '<item|alias> [start:<corpse#>] [from:<noun>] [stow:<container>] [stow_start:<n>] [drop:<item|list>]'
M.desc = 'Take a pipe-delimited item list from every corpse, rotating stowage containers'
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

**`chains`** — set to `true` only when the mode genuinely honors completion handoffs, which
means both that `on_start` calls `after.parse(args)` and that a completion point
calls `after.finish()`. When set, the client appends the generic
`after_<mode|do|ps>:<mode|command|praetorscript>` suffix to the displayed
signature, so declaring it on a mode that ignores the token advertises
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
This is useful for internal route legs and other modes intended to be reached
through chaining rather than selected from the command hint.

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
