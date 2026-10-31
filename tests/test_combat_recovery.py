"""Behavior tests for shared combat recovery.

These tests execute the real Lua modes with mocked Praetor globals. Run with:
    python -m unittest tests.test_combat_recovery
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


class ModeHarness:
    def __init__(self, mode_name: str, *args: str):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.now = 10_000
        self.commands: list[str] = []
        self.logs: list[str] = []
        self.timers = []
        self.state_values = {}
        self.metric_values = {}

        state = self.lua.table()
        state.get = lambda key: self.state_values.get(key)
        state.set = lambda key, value: self.state_values.__setitem__(key, value)
        state.persist = lambda _key: None
        state.unpersist = lambda _key: None
        state.display = lambda *_args: None

        metrics = self.lua.table()
        metrics.track = lambda *_args: None
        metrics.inc = self._metric_inc
        metrics.dec = lambda key: self._metric_inc(key, -1)
        metrics.set = lambda key, value: self.metric_values.__setitem__(key, value)
        metrics.get = lambda key: self.metric_values.get(key)

        time = self.lua.table()
        time.now = lambda: self.now
        time.since = lambda then: self.now - then

        status = self.lua.table()
        status.health = 100
        status.fatigue = 100
        status.encumbrance = 0
        status.satiation = 100

        variables = self.lua.table()
        variables.get = lambda _key: None
        variables.set = lambda *_args: None

        globals_ = self.lua.globals()
        globals_.state = state
        globals_.metrics = metrics
        globals_.time = time
        globals_.status = status
        globals_.variables = variables
        globals_.send = self._send
        globals_.log = self.logs.append
        globals_.notify = lambda *_args: None
        globals_.set_mode = lambda *_args: None
        globals_.praetor_script = lambda *_args: None
        globals_.random_item = lambda values: values[1]
        globals_.set_interval = self._set_interval
        globals_.set_timeout = self._set_interval
        globals_.clear_timer = lambda *_args: None
        globals_.package.path = f"{ROOT}/?.lua;" + globals_.package.path

        self.mode = self.lua.eval(f"require('{mode_name}')")[0]
        self.mode.on_start(self.lua.table_from(args))

    def _send(self, command, _delay=None):
        self.commands.append(command)

    def _set_interval(self, callback, _milliseconds):
        self.timers.append(callback)
        return len(self.timers)

    def _metric_inc(self, key, amount=1):
        self.metric_values[key] = self.metric_values.get(key, 0) + amount

    def clear_commands(self):
        self.commands.clear()

    def advance_time(self, milliseconds: int):
        self.now += milliseconds

    def fire_watchdog(self):
        self.timers[0]()

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


INTERPOSE = (
    "[Success: 38, Roll: 63] You move toward a harsh-looking bandit, "
    "but are interposed by a mud-covered bandit."
)


class CombatRecoveryTests(unittest.TestCase):
    def finish_target_switch(self, harness: ModeHarness):
        harness.process("Your macro target is raider|guard.")
        harness.process("Your new macro target is mud-covered.")

    def test_bare_weapon_requirement_rewields_in_every_combat_mode(self):
        for mode_name in ("macro", "chain_macro", "falx_macro", "lizard_macro"):
            with self.subTest(mode=mode_name):
                h = ModeHarness(mode_name)
                h.clear_commands()

                self.assertTrue(h.process("You must be wielding a weapon."))
                self.assertEqual(h.commands, ["r"])
                self.assertEqual(h.state_values["deferred_cmd"], "r")

    def test_normal_advance_waits_for_confirmation_and_unbusy(self):
        h = ModeHarness("macro")
        h.clear_commands()

        h.process("A protected raider arrives.")
        self.assertEqual(h.commands, ["app1"])
        self.assertFalse(h.state_values["approached"])

        h.process("[Success: 1, Roll: 60] You advance toward a protected raider.")
        self.assertEqual(h.commands, ["app1"])
        self.assertTrue(h.state_values["approached"])

        h.process("You are no longer busy.")
        self.assertEqual(h.commands, ["app1", "at1"])

    def test_every_combat_mode_uses_shared_interpose_recovery(self):
        for mode_name in ("macro", "chain_macro", "falx_macro", "lizard_macro"):
            with self.subTest(mode=mode_name):
                h = ModeHarness(mode_name)
                h.clear_commands()
                h.process(INTERPOSE)
                self.assertEqual(h.commands, ["@mtarg"])
                h.process("Your macro target is raider|guard.")
                self.assertEqual(h.commands[-1], "@mtarg mud-covered")
                h.process("Your new macro target is mud-covered.")
                self.assertIn(h.commands[-1], {"at1", "st1"})

    def test_blocker_selector_uses_word_distinct_from_protected_target(self):
        cases = (
            (
                "[Success: 1, Roll: 13] You move toward a bandit with a leathery face, "
                "but are interposed by a bandit with hairy arms.",
                "@mtarg hairy",
            ),
            (
                "[Success: 1, Roll: 13] You move toward a bandit covered with scars, "
                "but are interposed by a bandit with a leathery face.",
                "@mtarg leathery",
            ),
            (INTERPOSE, "@mtarg mud-covered"),
        )
        for interpose, expected in cases:
            with self.subTest(expected=expected):
                h = ModeHarness("macro")
                h.clear_commands()
                h.process(interpose)
                h.process("Your macro target is raider|guard.")
                self.assertEqual(h.commands[-1], expected)

    def test_identical_descriptions_use_unindexed_descriptive_match(self):
        cases = (
            (
                "[Success: 4, Roll: 89] You move toward a bandit with a leathery face, "
                "but are interposed by a bandit with a leathery face.",
                "leathery",
            ),
            (
                "[Success: 12, Roll: 83] You move toward a mud-covered bandit, "
                "but are interposed by a mud-covered bandit.",
                "mud-covered",
            ),
        )
        for interpose, selector in cases:
            with self.subTest(selector=selector):
                h = ModeHarness("macro")
                h.clear_commands()
                h.process(interpose)
                h.process("Your macro target is raider|guard.")
                self.assertEqual(h.commands[-1], f"@mtarg {selector}")
                h.process(f"Your new macro target is {selector}.")
                self.assertIn(h.commands[-1], {"at1", "st1"})

    def test_repeated_interpose_retargets_once_and_ignores_stale_work(self):
        h = ModeHarness("macro")
        h.clear_commands()

        h.process("A harsh-looking bandit is not close enough.")
        h.process(INTERPOSE)
        h.process(INTERPOSE)
        h.process('You don\'t see any "1" here.')
        h.process("You are no longer busy.")
        h.advance_time(9_000)
        h.fire_watchdog()
        self.assertEqual(h.commands, ["adv1", "@mtarg"])
        self.assertFalse(h.state_values["combat_no_targets"])

        self.finish_target_switch(h)
        self.assertEqual(h.commands[-2:], ["@mtarg mud-covered", "at1"])
        h.process("A grizzled old bandit falls unconscious.")
        self.assertFalse(h.state_values["target_ko"])
        h.process("A mud-covered bandit falls unconscious.")
        self.assertTrue(h.state_values["target_ko"])

    def test_repeated_interpose_after_switch_reasserts_blocker_selector(self):
        h = ModeHarness("macro")
        h.clear_commands()
        interpose = (
            "[Success: 1, Roll: 13] You move toward a bandit with a leathery face, "
            "but are interposed by a bandit with hairy arms."
        )
        h.process(interpose)
        h.process("Your macro target is raider|guard.")
        h.process("Your new macro target is hairy.")
        h.process(interpose)
        self.assertEqual(h.commands[-1], "@mtarg hairy")

    def test_nested_interpose_replaces_blocker_then_one_kill_restores_original(self):
        h = ModeHarness("macro")
        h.clear_commands()
        h.process(INTERPOSE)
        self.finish_target_switch(h)

        nested = (
            "[Success: 1, Roll: 52] You move toward a mud-covered bandit, "
            "but are interposed by a second defender."
        )
        h.process(nested)
        h.process("Your new macro target is second.")
        self.assertEqual(h.commands[-2:], ["@mtarg second", "at1"])

        h.process("[Success: 5, Roll: 80] You thrust your blade through a second defender's heart.")
        self.assertEqual(h.commands[-1], "@mtarg raider|guard")
        h.process("Your new macro target is raider|guard.")
        self.assertEqual(h.commands[-1], "app1")
        self.assertFalse(h.state_values["interpose_target"])

    def test_nokill_knockout_restores_original_target(self):
        h = ModeHarness("macro", "nokill")
        h.clear_commands()
        h.process(INTERPOSE)
        self.finish_target_switch(h)

        h.process("[Success: 30, Roll: 90] A mud-covered bandit falls unconscious.")
        self.assertEqual(h.commands[-1], "@mtarg raider|guard")
        self.assertFalse(h.state_values["target_ko"])

    def test_nokill_knockout_before_target_query_response_is_deferred(self):
        h = ModeHarness("macro", "nokill")
        h.clear_commands()
        h.process(INTERPOSE)
        h.process("A mud-covered bandit falls unconscious.")
        self.assertEqual(h.commands, ["@mtarg"])
        h.process("Your macro target is raider|guard.")
        self.assertEqual(h.commands[-1], "@mtarg raider|guard")

    def test_stopping_mode_restores_original_target_during_recovery(self):
        h = ModeHarness("macro")
        h.clear_commands()
        h.process(INTERPOSE)
        self.finish_target_switch(h)
        h.mode.on_stop()
        self.assertEqual(h.commands[-1], "@mtarg raider|guard")

    def test_original_multiword_target_is_restored_verbatim(self):
        h = ModeHarness("macro")
        h.clear_commands()
        h.process(INTERPOSE)
        h.process("Your macro target is 2 relaxed.")
        self.assertEqual(h.commands[-1], "@mtarg mud-covered")
        h.process("Your new macro target is mud-covered.")

        h.process("[Success: 5, Roll: 80] You thrust your blade through a mud-covered bandit's heart.")
        self.assertEqual(h.commands[-1], "@mtarg 2 relaxed")

    def test_falx_interpose_cancels_submode_before_attacking_blocker(self):
        h = ModeHarness("falx_macro")
        h.process("You are no longer busy.")
        self.assertEqual(h.commands[-1], "st1")
        self.assertEqual(h.state_values["falx_submode"], "stunSent")

        h.process(INTERPOSE)
        self.assertIsNone(h.state_values["falx_submode"])
        self.finish_target_switch(h)
        self.assertEqual(h.commands[-1], "at1")

    def test_genuine_missing_target_suppresses_watchdog(self):
        h = ModeHarness("macro")
        h.clear_commands()
        h.process('You don\'t see any "1" here.')
        h.advance_time(9_000)
        h.fire_watchdog()
        self.assertTrue(h.state_values["combat_no_targets"])
        self.assertEqual(h.commands, [])

    def test_invalid_maneuver_target_suppresses_watchdog_until_arrival(self):
        responses = (
            "You can't offchop a rough wooden club.",
            "You can't offpivot a wool armband bearing a decayed red emblem.",
            "You can't rotchop some deep black leathery elbow-length gloves.",
            "You can't sweepcleave a rough wooden club.",
            "You can't onslaught a rough wooden club.",
            "You can't offcrush a rough wooden club.",
            "You can't pollsmash a rough wooden club.",
            "You can't advance some deep black leathery elbow-length gloves.",
        )
        for response in responses:
            with self.subTest(response=response):
                h = ModeHarness("macro")
                h.clear_commands()

                self.assertTrue(h.process(response))
                self.assertTrue(h.state_values["combat_no_targets"])
                h.advance_time(9_000)
                h.fire_watchdog()
                self.assertEqual(h.commands, [])

                h.process("A grizzled old bandit arrives.")
                self.assertFalse(h.state_values["combat_no_targets"])
                self.assertEqual(h.commands, ["app1"])

    def test_unrelated_cant_and_other_players_interpose_are_ignored(self):
        h = ModeHarness("macro")
        h.clear_commands()
        h.process("You can't tell what time of day it is from here.")
        h.process(
            "[Success: 1, Roll: 42] An ally moves toward a raider, "
            "but is interposed by a guard."
        )
        self.assertFalse(h.state_values["combat_no_targets"])
        self.assertEqual(h.commands, [])

    def test_advance_retries_are_debounced(self):
        h = ModeHarness("macro")
        h.clear_commands()
        h.process("A protected raider is not close enough.")
        h.process("A protected raider is not close enough.")
        self.assertEqual(h.commands, ["adv1"])
        h.advance_time(3_001)
        h.process("A protected raider is not close enough.")
        self.assertEqual(h.commands, ["adv1", "adv1"])

    def test_direct_falx_death_counts_once(self):
        line = (
            "[Success: 5, Roll: 20] You dip the blade of your falx behind you "
            "before twisting into a heavy slash at a scarred bandit! Your blade "
            "cuts cleanly through a scarred bandit, nearly cleaving him in two! "
            "His body slowly slides apart as he dies."
        )
        for mode_name in ("macro", "chain_macro", "falx_macro", "lizard_macro"):
            with self.subTest(mode=mode_name):
                h = ModeHarness(mode_name)
                h.process(line)
                self.assertEqual(h.metric_values["kills"], 1)

    def test_undead_drop_disappearance_and_fatal_result_are_one_death(self):
        h = ModeHarness("macro")
        lines = (
            "A faded linen armband falls from the corpse of a rotting foot soldier.",
            "The corpse of a rotting foot soldier falls back among the piles of "
            "the dead with a flash, leaving behind a small stone.",
            "[Success: 5, Roll: 85] You sweep your falx around you! Critical Hit! "
            "a rotting foot soldier drops dead after an ally opens a deep cleft "
            "in his skull!",
        )
        for line in lines:
            self.assertTrue(h.process(line))
        self.assertEqual(h.metric_values["kills"], 1)

    def test_normal_undead_drop_and_disappearance_are_one_death(self):
        h = ModeHarness("macro")
        h.process("A wide linen armband falls from a decayed auxiliary.")
        h.process(
            "As a decayed auxiliary falls, a brilliant flash of light fills the "
            "area, leaving behind a small stone."
        )
        self.assertEqual(h.metric_values["kills"], 1)

    def test_identically_named_deaths_are_not_collapsed(self):
        h = ModeHarness("macro")
        for _ in range(2):
            h.process("A wide linen armband falls from a reeking auxiliary.")
            h.process(
                "As a reeking auxiliary falls, a brilliant flash of light fills "
                "the area, leaving behind a small stone."
            )
        self.assertEqual(h.metric_values["kills"], 2)

    def test_one_multi_target_result_can_count_multiple_deaths(self):
        h = ModeHarness("macro")
        h.process(
            "[Success: 5, 5, Roll: 80] You sweep your falx around you! "
            "Critical Hit! A rotting soldier drops dead after an ally opens his skull! "
            "You find an opening and crush a reeking auxiliary's sternum with "
            "your falx, puncturing his heart!"
        )
        self.assertEqual(h.metric_values["kills"], 2)

    def test_each_validated_fatal_result_variant_counts(self):
        variants = (
            "Critical Hit! Savage blow to a walking corpse's head!",
            "Critical Hit! a reeking auxiliary's skull is parted by your falx.",
            "Critical Hit! Violent strike across the top of an undead soldier's "
            "head relieves him of much of it before he falls in a heap, dead.",
            "Critical Hit! You find an opening and crush a rotting auxiliary's "
            "sternum with your falx, puncturing his heart!",
            "Critical Hit! With a surge of strength, your falx crushes through "
            "muscle, arteries and bone, until the head of a rotting soldier "
            "rises a bit before suddenly crashing to the ground at your feet.",
        )
        for variant in variants:
            with self.subTest(variant=variant):
                h = ModeHarness("macro")
                h.process(f"[Success: 5, Roll: 80] You sweep your falx! {variant}")
                self.assertEqual(h.metric_values["kills"], 1)

    def test_nonfatal_critical_prose_does_not_count_as_death(self):
        h = ModeHarness("macro")
        nonfatal = (
            "[Success: 5, Roll: 70] You swing your falx at an auxiliary! "
            "An otherwise fatal jab to the neck gets caught in his collar bone.",
            "[Success: 5, Roll: 71] You swing your falx at an auxiliary! "
            "He barely avoids a deadly slash to the neck.",
            "[Success: 5, Roll: 72] You swing your falx at an auxiliary! "
            "He collapses in shock, blood spurting from his neck!",
            "[Success: 5, Roll: 73] You swing your falx at an auxiliary! "
            "Your blade cuts cleanly through his leather armor.",
        )
        for line in nonfatal:
            h.process(line)
        self.assertNotIn("kills", h.metric_values)


if __name__ == "__main__":
    unittest.main()
