"""Behavior tests for loot routing and final hand cleanup.

Run with:
    python -m unittest tests.test_loot
"""

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


class LootHarness:
    def __init__(self, *args: str):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.commands: list[str] = []
        self.logs: list[str] = []
        self.notifications: list[tuple[str, str]] = []
        self.mode_changes: list[str] = []
        self.state_values = {}

        state = self.lua.table()
        state.get = lambda key: self.state_values.get(key)
        state.set = lambda key, value: self.state_values.__setitem__(key, value)
        state.persist = lambda _key: None
        state.unpersist = lambda _key: None
        state.display = lambda *_args: None

        globals_ = self.lua.globals()
        globals_.state = state
        globals_.send = lambda command, _delay=None: self.commands.append(command)
        globals_.log = self.logs.append
        globals_.notify = lambda title, message: self.notifications.append((title, message))
        globals_.set_mode = lambda mode, *_args: self.mode_changes.append(mode)
        globals_.praetor_script = lambda *_args: None
        globals_.package.path = f"{ROOT}/?.lua;" + globals_.package.path

        self.mode = self.lua.eval("require('loot')")[0]
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


ARGS = (
    ".",
    "stow:sack",
    "stow_start:2",
    "special:pouch|armband",
    "special_dest:1 sack",
    "drop:sack|junk|garbage",
)


class LootTests(unittest.TestCase):
    def test_bandit_complex_alias_covers_observed_loot_families(self):
        h = LootHarness("bandit_complex")

        self.assertEqual(
            h.commands,
            ["get sack|legging|boot|armor|bronze|iron|boison|retalq from 1 corpse"],
        )

    def started(self, *args: str) -> LootHarness:
        h = LootHarness(*(args or ARGS))
        self.assertEqual(h.commands, ["stow 2 sack"])
        h.process("A patched large sack will be used for stowage.")
        self.assertEqual(h.commands[-1], "get . from 1 corpse")
        return h

    def test_drop_has_priority_over_special(self):
        h = self.started(
            ".",
            "special:sack|pouch",
            "special_dest:1 sack",
            "drop:sack",
            "stow:sack",
            "stow_start:2",
        )

        h.process("You take a grimy leather sack from the corpse of a bandit.")
        self.assertEqual(h.commands[-1], "drop sack")
        h.process("You drop a grimy leather sack.")
        self.assertEqual(h.commands[-1], "get . from 1 corpse")

    def test_drop_cleanup_uses_the_matching_drop_substring(self):
        h = self.started()
        item = h.lua.table()
        item.name = "some foul-smelling garbage"
        item.route = "drop"
        item.route_target = "garbage"
        items = h.lua.table()
        items[1] = item
        h.state_values["held_items"] = items
        h.state_values["awaiting"] = "get"

        h.process('You don\'t see a "2 corpse" anywhere.')
        h.process(
            "You are holding some foul-smelling garbage in your right hand "
            "and nothing in your left hand."
        )

        self.assertEqual(h.commands[-1], "drop garbage")

    def test_special_items_go_to_fixed_destination(self):
        h = self.started()

        h.process("You take a mud-caked leather pouch from the corpse of a bandit.")
        self.assertEqual(h.commands[-1], "put pouch in 1 sack")
        h.process("You put a mud-caked leather pouch in a large sack.")
        self.assertEqual(h.commands[-1], "get . from 1 corpse")

    def test_fixed_special_destination_stops_when_full(self):
        h = self.started()
        h.process("You take a cotton armband from the corpse of a bandit.")

        h.process("There is not enough room to put the cotton armband in the large sack.")

        self.assertEqual(h.mode_changes[-1], "disable")
        self.assertEqual(h.notifications[-1], ("Cannot proceed", "loot stopped: special destination is full"))

    def test_bare_special_destination_rotates_when_full(self):
        h = self.started(
            ".",
            "stow:sack",
            "stow_start:2",
            "special:armband",
            "special_dest:sack",
        )
        h.process("You take a red cotton armband from the corpse of a bandit.")
        self.assertEqual(h.commands[-1], "put armband in 1 sack")

        h.process("There is not enough room to put the red cotton armband in the large sack.")

        self.assertEqual(h.commands[-1], "put armband in 2 sack")

    def test_special_cleanup_uses_the_matching_special_substring(self):
        h = self.started()
        item = h.lua.table()
        item.name = "a mud-caked leather pouch"
        item.route = "special"
        item.route_target = "pouch"
        items = h.lua.table()
        items[1] = item
        h.state_values["held_items"] = items
        h.state_values["awaiting"] = "get"

        h.process('You don\'t see a "2 corpse" anywhere.')
        h.process(
            "You are holding a mud-caked leather pouch in your right hand "
            "and nothing in your left hand."
        )

        self.assertEqual(h.commands[-1], "put pouch in 1 sack")

    def test_main_stow_rotates_on_explicit_full_message(self):
        h = self.started()
        h.process("You take some dirty leather boots from the corpse of a bandit.")
        self.assertEqual(h.commands[-1], "get . from 1 corpse")

        h.process("There is not enough room to put the dirty leather boots in the patched large sack.")
        self.assertEqual(h.commands[-1], "stow 3 sack")
        h.process("A tattered large sack will be used for stowage.")
        self.assertEqual(h.commands[-1], "get . from 1 corpse")

    def test_stow_without_start_rotates_to_first_container(self):
        h = LootHarness(".", "stow:sack")
        self.assertEqual(h.commands, ["get . from 1 corpse"])

        h.process("You don't have enough free hands to get some leather boots.")

        self.assertEqual(h.commands[-1], "stow 1 sack")

    def test_cleanup_selects_first_container_when_stow_start_was_omitted(self):
        h = LootHarness(".", "stow:sack")
        h.process("You take some leather boots from the corpse of a bandit.")
        h.process('You don\'t see a "2 corpse" anywhere.')
        h.process(
            "You are holding some leather boots in your right hand "
            "and nothing in your left hand."
        )
        self.assertEqual(h.commands[-1], "stow 1 sack")

        h.process("A patched large sack will be used for stowage.")

        self.assertEqual(h.commands[-1], "put leather boots in 1 sack")

    def test_completion_uses_inhand_and_rotates_while_clearing_both_items(self):
        h = self.started()
        h.process("You take some dirty leather boots from the corpse of a bandit.")
        h.process("You take some leather pteryges from the corpse of a bandit.")

        h.process('You don\'t see a "3 corpse" anywhere.')
        self.assertEqual(h.commands[-1], "inhand")
        h.process(
            "You are holding some dirty leather boots in your right hand "
            "and some leather pteryges in your left hand."
        )
        self.assertEqual(h.commands[-1], "put dirty leather boots in 2 sack")

        h.process("There is not enough room to put the dirty leather boots in the patched large sack.")
        self.assertEqual(h.commands[-1], "stow 3 sack")
        h.process("A tattered large sack will be used for stowage.")
        self.assertEqual(h.commands[-1], "put dirty leather boots in 3 sack")
        h.process("You put some dirty leather boots in a tattered large sack.")
        self.assertEqual(h.commands[-1], "put leather pteryges in 3 sack")
        h.process("You put some leather pteryges in a tattered large sack.")

        self.assertEqual(h.mode_changes[-1], "disable")
        self.assertEqual(h.notifications[-1], ("Completed", "Loot collection finished"))

    def test_inhand_cleanup_leaves_unrelated_held_item_alone(self):
        h = self.started()
        h.process("You take some dirty leather boots from the corpse of a bandit.")
        h.process('You don\'t see a "2 corpse" anywhere.')
        h.process(
            "You are holding a silver lockpick in your right hand "
            "and some dirty leather boots in your left hand."
        )

        self.assertEqual(h.commands[-1], "put dirty leather boots in 2 sack")
        self.assertNotIn("silver lockpick", h.commands[-1])

    def test_special_requires_destination(self):
        h = LootHarness(".", "special:pouch")

        self.assertEqual(h.mode_changes, ["disable"])
        self.assertEqual(h.logs, ["loot mode special: needs a special_dest:<destination>"])
        self.assertEqual(h.commands, [])


if __name__ == "__main__":
    unittest.main()
