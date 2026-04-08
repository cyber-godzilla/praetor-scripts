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
- `idle` -- Waits for fatigue to recover, then switches to the next mode.
- `disable` -- Stops all automation.

**Navigation:**
- `east_to_romulus` / `fran_to_ne` / `fran_ne_to_bath` -- Automated travel routes.

