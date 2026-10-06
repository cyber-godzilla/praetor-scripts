# Changelog

All notable changes to praetor-scripts are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/): major for
changes that break how existing modes are invoked, minor for new modes or
new arguments, patch for fixes.

## [Unreleased]

### Added

- `lib_after` now supports `after_mode:<mode> [args...]`,
  `after_do:<command...>`, and `after_ps:<script...>` completion handoffs.
  The legacy `after:<mode>` spelling remains supported.
- Chaining mode hints now summarize those forms as
  `after_<mode|do|ps>:<mode|command|praetorscript>`.

### Removed

- Removed the unreliable experimental `priority_macro` mode.

### Changed

- `loot` now uses the rotating-stowage implementation previously exposed as
  `loot_stow`. The old `loot` implementation and the `loot_stow` mode name
  have been removed.

### Fixed

- Combat macros now pause after explicit no-target responses, avoid duplicate
  recovery attacks when watchdog and unbusy events overlap, and recognize
  wildcard kill strings consistently.
- `locksmith` now handles unlock/unjam success before generic success rolls,
  distinguishes missing lockpicks from exhausted container lists, and indexes
  in-place containers when opening or emptying them.
- `wire_to_picks` now runs its deferred failed-pick recovery command and
  recognizes the correctly spelled already-carrying-tongs response.
- `toss_sacks` waits for drag roundtime before trying to get the next item.
- `lizard_macro nokill` no longer sends `nokill` as a movement direction.
- `wagon` now rejects a non-alias invocation that omits its vendor.
- Combat macros now increment `Crits` for critical hits in player attack lines.

## [0.1.1] - 2026-09-13

### Added

- Release workflow: every push to `main` is tagged with the next patch
  version and published as a GitHub release with a zip of the tracked
  files. Minor and major versions are still tagged by hand; pushing such a
  tag publishes its release the same way.

- `lib_walk` — shared library for building on-foot travel modes from an
  ordered step list, the walking analog of `lib_route`.

- `loot` and `loot_stow` accept `from:<noun>` in any argument position to
  loot something other than corpses, e.g. `/mode loot bronze from:pile`.
  Omitted, both modes loot corpses as before.

## [0.1.0] - 2026-08-25

First versioned release, cut after a full repository audit.

### Added

- 26 modes: combat macros (`macro`, `chain_macro`, `falx_macro`,
  `lizard_macro`, `priority_macro`), locksmithing (`board`, `lock_job`,
  `locksmith`, `wire_to_picks`), herbalism (`herbmap`), training
  (`courses_three`, `courses_four`, `learn_languages`), utility (`loot`,
  `loot_stow`, `wagon`, `empty_containers`, `toss_sacks`, `drag_paces`,
  `remove_bandages`, `repeat`, `idle`, `disable`), and navigation routes.
- 14 shared libraries, including `lib_after` (mode chaining via `after:`)
  and `lib_route` (wagon-route leg builder).
- Mode metadata conventions (`usage`/`desc`/`chains`/`hidden`) driving the
  client's command hint and `/list`.
- Offline test harness for replaying game lines through mode reaction
  tables without the client.

### Fixed

- `wagon` crashed on `/mode wagon after:<mode>` with no other arguments;
  it now aborts cleanly without chaining.
- Documentation drift found by the audit: phantom absorption-tracking API,
  undocumented `locksmith`/`herbmap`/`priority_macro`, wrong `lock_job`
  and `priority_macro` usage strings, and `lizard_macro`'s chain trigger.
