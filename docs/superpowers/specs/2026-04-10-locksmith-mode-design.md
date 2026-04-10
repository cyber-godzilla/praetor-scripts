# Locksmith Mode Design

## Overview

A new Praetor mode (`locksmith.lua`) for batch-processing locked/jammed containers using locksmithing skills. The mode unjams and unlocks a series of containers, with configurable source, disposition, open/empty behavior, and difficulty skipping.

## Invocation

```
/mode locksmith [options...]
```

All options use `key:value` format and are order-independent. All have defaults, so bare `/mode locksmith` is a valid invocation.

## Configuration

| Param | Default | Description |
|-------|---------|-------------|
| `cont:` | `chest\|coffer\|trunk` | Pipe-delimited container types (game resolves which to target) |
| `from:` | `here` | Source: where to get containers (`here` = ground, or a container name like `wagon`) |
| `to:` | `here` | Disposition: where finished containers go (see Disposition Logic) |
| `stow:` | `my neckpouch\|sack\|backpack\|satchel` | Where to temporarily put lockpick when hands must be empty |
| `open:` | `false` | Whether to open containers after unlocking |
| `empty:` | *(none)* | Empty contents into this target after opening (implies `open:true`) |
| `unjam_first:` | `false` | Two-pass mode: unjam all containers first, then unlock all |
| `skip:` | `60` | Skip unjam attempts where the `[Success: N` value exceeds this threshold |

### Disposition Logic

The `to:` value determines what command is issued for a finished container:

- `"here"` — in in-place mode: no action (containers stay on the ground). In pick-up mode: `drop <cont>`
- A compass direction (`n`, `s`, `e`, `w`, `ne`, `nw`, `se`, `sw`) — `toss <cont> <direction>`
- Any other string — `put <cont> in <place>`

### Example Invocations

```
/mode locksmith
-- chests/coffers/trunks on ground, work in-place, skip unjams > 60

/mode locksmith cont:chest from:wagon to:n open:true
-- chests from wagon, toss north after opening

/mode locksmith skip:75 unjam_first:true empty:sack to:wagon
-- unjam all first, then unlock all, open & empty into sack, store in wagon

/mode locksmith cont:coffer from:here to:wagon
-- coffers on ground, store in wagon when done
```

## Operating Modes

The combination of `from:` and `to:` determines one of two operating modes:

### In-Place Mode (`from:here`, `to:here`)

Containers stay on the ground and are addressed by numeric index:

```
unjam 1 chest|coffer|trunk with lockpick
unlock 1 chest|coffer|trunk with lockpick
-- index increments to 2, 3, etc.
```

No `get` or `drop` commands needed. The index (`container_index` state) increments after each container is fully processed.

### Pick-Up Mode (any other `from:`/`to:` combination)

Containers are retrieved from the source, worked on, then disposed:

```
get chest|coffer|trunk from wagon    -- (or just "get chest|coffer|trunk" if from:here)
unjam chest|coffer|trunk with lockpick
unlock chest|coffer|trunk with lockpick
put chest|coffer|trunk in wagon      -- (or toss/drop based on disposition)
```

The next `get` always grabs the next available container.

When `from:here` but `to:` is not `here`, the flow is:
```
get chest|coffer|trunk               -- pick up from ground
-- work on it --
toss chest|coffer|trunk n            -- (or put, based on disposition)
```

## Phases

### Sequential Mode (`unjam_first:false`, default)

Each container is fully processed before moving to the next:

1. Unjam (if jammed)
2. Unlock
3. Open (if `open:true` or `empty:` set)
4. Empty (if `empty:` set)
5. Disposition
6. Next container

### Two-Pass Mode (`unjam_first:true`)

**Pass 1 — Unjam:** Work through all containers, only unjamming. In pick-up mode, containers go back to source after unjamming. In in-place mode, just increment the index.

**Pass 2 — Unlock:** Reset index to 1 (in-place mode) or start getting containers again (pick-up mode). Unlock each container, then open/empty/dispose.

Phase is tracked via `phase` state variable: `"unjam"` or `"unlock"`.

## State Variables

| State Key | Type | Description |
|-----------|------|-------------|
| `phase` | string | Current phase: `"unjam"` or `"unlock"` |
| `container_index` | number | Numeric index for in-place mode |
| `holding` | boolean | Whether a container is currently in hand |
| `is_jammed` | boolean | Whether current container is jammed |
| `skipped` | boolean | Whether current container was skipped due to difficulty |
| `in_place` | boolean | Whether operating in in-place mode |
| Config values | various | `cont`, `from`, `to`, `stow`, `open`, `empty`, `unjam_first`, `skip` |

## Reactions

### Difficulty Check

| Match | Action |
|-------|--------|
| `[Success:` | Parse `Success` integer from `[Success: N, Roll: M]`. If phase is `"unjam"` and N > `skip` threshold, mark `skipped=true` and advance to next container. |

### Unjam/Unlock Results

| Match | Action |
|-------|--------|
| `You feel an obstruction release` | Unjam succeeded. If `unjam_first`: next container. Else: proceed to unlock. |
| `This lock is jammed` | Discovered jam during unlock attempt. Set `is_jammed=true`, send unjam command. |
| `You hear a click as the tumbler mechanism releases` | Unlock succeeded. Proceed to open/empty/disposition. |
| `It is already` | Already unjammed/unlocked. Skip to next step. |

### Lockpick Management

| Match | Action |
|-------|--------|
| `You must be holding` / `You don't see any` | Send `get my lockpick`. |
| `You take * lockpick` / `You are already carrying * lockpick` | Resume current action. |

### Empty Hands (for opening/emptying)

| Match | Action |
|-------|--------|
| `Your hands must be empty` | Send `put lockpick in <stow>`. |
| `You put * lockpick` | Perform the pending open/empty action. |

### Open/Empty

| Match | Action |
|-------|--------|
| `You open` | If `empty` is set, send `empty <cont> into <empty target>`. Otherwise proceed to disposition. |
| `You empty` | Proceed to disposition. |

### End of Containers

| Match | Action |
|-------|--------|
| `You don't see` / `There aren't that many` | If `unjam_first` and phase is `"unjam"`: switch to `"unlock"` phase, reset index. Otherwise: done — notify and `set_mode('disable')`. |

### Unbusy

| Match | Action |
|-------|--------|
| `strings.unbusy` | Main dispatch. Examines phase, `holding`, `is_jammed`, and config to determine next command. |

## Unbusy Dispatch Logic

The `unbusy` handler is the main driver. Pseudocode:

```
if in pick-up mode and not holding:
    get container from source

if phase == "unjam":
    send unjam command
elif phase == "unlock":
    if is_jammed:
        send unjam command
    else:
        send unlock command
```

## Advancing to Next Container

After a container is fully processed (or skipped):

**In-place mode:** Increment `container_index`.

**Pick-up mode:** Process disposition (toss/put/drop), then get next container.

Reset `is_jammed`, `skipped` state for the new container.

## Completion

When no more containers are available:
- `notify('Completed', 'Locksmith finished')`
- `set_mode('disable')`

## Dependencies

- `lib_strings.lua` — for `unbusy` patterns
- `lib_locksmithing.lua` — not needed directly (no NPC job handling), but available if needed later

## Known Limitations

- Arguments containing spaces (e.g., `stow:my sack`) will break due to arg splitting. This is a known cross-project issue to be solved later.
- Pipe-delimited container types rely on the game's built-in resolution.
