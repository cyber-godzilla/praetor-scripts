"""Behavior tests for the four locksmithing workflows."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from lupa import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]


def wildcard_match(pattern: str, text: str) -> bool:
    anchored_start = pattern.startswith("^")
    anchored_end = pattern.endswith("$")
    if anchored_start:
        pattern = pattern[1:]
    if anchored_end:
        pattern = pattern[:-1]
    regex = re.escape(pattern).replace(r"\*", ".*").replace(r"\?", ".")
    if anchored_start:
        regex = "^" + regex
    if anchored_end:
        regex += "$"
    return re.search(regex, text) is not None


class LocksmithHarness:
    def __init__(self, mode_name: str, *args: str):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.commands: list[str] = []
        self.logs: list[str] = []
        self.notifications: list[tuple[str, str]] = []
        self.mode_changes: list[str] = []
        self.state_values = {}

        state = self.lua.table()
        state.get = lambda key: self.state_values.get(key)
        state.set = lambda key, value: self.state_values.__setitem__(key, value)

        globals_ = self.lua.globals()
        globals_.state = state
        globals_.send = lambda command, _delay=None: self.commands.append(command)
        globals_.log = self.logs.append
        globals_.notify = lambda title, message: self.notifications.append((title, message))
        globals_.set_mode = lambda mode, *_args: self.mode_changes.append(mode)
        globals_.praetor_script = lambda *_args: None
        globals_.package.path = f"{ROOT}/?.lua;" + globals_.package.path

        self.mode = self.lua.eval(f"require('{mode_name}')")[0]
        self.mode.on_start(self.lua.table_from(args))

    def process(self, text: str) -> bool:
        for reaction in self.mode.reactions.values():
            patterns = reaction.match
            if isinstance(patterns, str):
                matched = wildcard_match(patterns, text)
            else:
                matched = any(wildcard_match(pattern, text) for pattern in patterns.values())
            if not matched:
                continue
            condition = reaction.condition
            if condition is not None and not condition():
                continue
            reaction.action(text)
            return True
        return False


class LocksmithTests(unittest.TestCase):
    def acquire_pick(self, harness: LocksmithHarness):
        self.assertEqual(harness.commands, ["get my lockpick"])
        self.assertTrue(harness.process("You take a silver lockpick."))

    def test_carry_opens_and_routes_without_hard_coded_containers(self):
        h = LocksmithHarness(
            "unlock_all",
            "targets:box",
            "from:cart",
            "done:finished bin",
            "reject:problem bin",
            "open:true",
            "stow:belt pouch",
        )
        self.acquire_pick(h)
        self.assertEqual(h.commands[-1], "get box from cart")
        h.process("You take a wooden box from a cart.")
        self.assertEqual(h.commands[-1], "unlock box with lockpick")
        h.process("You hear a click as the tumbler mechanism releases. [Success: 42]")
        h.process("You are no longer busy.")
        self.assertEqual(h.commands[-1], "open box")
        h.process("Your hands must be empty to do that.")
        self.assertEqual(h.commands[-1], "put lockpick in belt pouch")
        h.process("You put a silver lockpick in a belt pouch.")
        h.process("You open a wooden box.")
        self.assertEqual(h.commands[-1], "put box in finished bin")
        h.process("You put a wooden box in a finished bin.")
        self.assertEqual(h.commands[-1], "get my lockpick")

    def test_toss_routes_success_and_difficulty_100_to_different_rooms(self):
        h = LocksmithHarness(
            "unlock_toss",
            "targets:coffer",
            "from:here",
            "done:n",
            "reject:s",
            "open:false",
        )
        self.acquire_pick(h)
        h.process("You take a bronze coffer.")
        h.process("You hear a click as a tumbler mechanism releases. [Success: 55]")
        h.process("You are no longer busy.")
        self.assertEqual(h.commands[-1], "toss coffer n")
        h.process("You toss a bronze coffer north.")
        h.process("You take a bronze coffer.")
        h.process("You are unable to get a tumbler mechanism to release. [Success: 100]")
        h.process("You are no longer busy.")
        self.assertEqual(h.commands[-1], "toss coffer s")

    def test_carry_resumes_if_someone_else_clears_discovered_jam(self):
        h = LocksmithHarness(
            "unlock_all",
            "targets:chest",
            "from:pile",
            "done:here",
            "reject:reject pile",
            "open:false",
        )
        self.acquire_pick(h)
        h.process("You take a chest from a pile.")
        h.process("This lock is jammed.")
        self.assertEqual(h.commands[-1], "unjam chest with lockpick")
        h.process("There is nothing jammed open.")
        self.assertEqual(h.commands[-1], "unlock chest with lockpick")

    def test_floor_pass_unjams_all_before_restarting_at_first_unlock(self):
        h = LocksmithHarness("unlock_floor_pass", "targets:chest|trunk")
        self.acquire_pick(h)
        self.assertEqual(h.commands[-1], "unjam 1 chest with lockpick")
        h.process("There is nothing jammed open.")
        self.assertEqual(h.commands[-1], "unjam 2 chest with lockpick")
        h.process("There aren't that many chests here.")
        self.assertEqual(h.commands[-1], "unjam 1 trunk with lockpick")
        h.process("There aren't that many trunks here.")
        self.assertEqual(h.commands[-1], "unlock 1 chest with lockpick")

    def test_floor_each_unlocks_each_item_before_advancing(self):
        h = LocksmithHarness("unlock_floor_each", "targets:chest")
        self.acquire_pick(h)
        self.assertEqual(h.commands[-1], "unjam 1 chest with lockpick")
        h.process("There is nothing jammed open.")
        self.assertEqual(h.commands[-1], "unlock 1 chest with lockpick")
        h.process("You hear a click as the tumbler mechanism releases. [Success: 35]")
        h.process("You are no longer busy.")
        self.assertEqual(h.commands[-1], "unjam 2 chest with lockpick")

    def test_missing_pick_during_floor_work_is_recovered_not_treated_as_exhaustion(self):
        h = LocksmithHarness("unlock_floor_each", "targets:chest|trunk")
        self.acquire_pick(h)
        h.process("You don't see any lockpick here.")
        self.assertEqual(h.commands[-1], "get my lockpick")
        self.assertEqual(h.state_values["target_index"], 1)
        h.process("You take an iron lockpick.")
        self.assertEqual(h.commands[-1], "unjam 1 chest with lockpick")

    def test_required_arguments_replace_old_prefilled_values(self):
        h = LocksmithHarness("unlock_all", "targets:chest")
        self.assertEqual(h.commands, [])
        self.assertEqual(h.mode_changes, ["disable"])
        self.assertIn("from: is required", h.logs[-1])

    def test_positional_arguments_are_rejected(self):
        h = LocksmithHarness("unlock_floor_each", "chest")
        self.assertEqual(h.commands, [])
        self.assertEqual(h.mode_changes, ["disable"])
        self.assertIn("expected a named argument", h.logs[-1])


if __name__ == "__main__":
    unittest.main()
