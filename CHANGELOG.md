# Changelog

All notable changes to praetor-scripts are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/): major for
changes that break how existing modes are invoked, minor for new modes or
new arguments, patch for fixes.

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
