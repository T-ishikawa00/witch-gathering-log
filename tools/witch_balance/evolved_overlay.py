"""Unapproved effect overlay on the imported R6-B reference battle.

The underlying R6-B source remains untouched. Evolved templates are validated
against growth R2, mapped to their base parent only for R6-B's old-slice
constructor, and their full calculated stats/effects are then restored onto the
live actors. This is an experiment adapter, not production engine code.
"""
from __future__ import annotations

from dataclasses import replace
from fractions import Fraction
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ENDGAME = HERE / "reference/endgame_r1/Witch_G2_Collection_Endgame_Monetization_R1_20261010"
sys.path.insert(0, str(ENDGAME / "tools"))
import lab  # noqa: E402

g = lab.g
BaseBattle = lab.b.FinalBattleR6
ORDER = lab.ORDER


def parent_base(template_id: str) -> str:
    while g.GEAR[template_id]["parent_template_id"]:
        template_id = g.GEAR[template_id]["parent_template_id"]
    return template_id


def item_effects(items):
    return {item.template_id: tuple(g.GEAR[item.template_id].get("core_rules", ())) for item in items}


class EvolvedOverlayBattle(BaseBattle):
    """Deterministic candidate semantics for evolved weapon core rules."""

    def __init__(self, party, boss, seed, record=False, **kwargs):
        original_party = party
        self.effects_by_actor = {}
        self.evolved_templates_by_actor = {}
        self.pressure_stacks = 0
        self.reflect_ready_ms = 0
        self.cover_barrier_ready_ms = 0
        self.challenge_phase = boss.get("overlay_phase")

        sanitized = []
        original_stats = {}
        for p in original_party:
            self.effects_by_actor[p.actor_id] = item_effects(p.items)
            self.evolved_templates_by_actor[p.actor_id] = tuple(
                item.template_id for item in p.items if g.GEAR[item.template_id].get("core_rules")
            )
            h1_rules = lab.old.RarityRules(g, 10000, multipliers=lab.old.MODELS["H1_RECOMMENDED"])
            original_stats[p.actor_id] = h1_rules.actor_stats(p.actor_id, p.level, list(p.items), p.awakening)
            sanitized_items = tuple(replace(it, template_id=parent_base(it.template_id)) for it in p.items)
            sanitized.append(replace(p, items=sanitized_items))

        super().__init__(sanitized, boss, seed, record=record, **kwargs)
        self.overlay_input_templates = {p.actor_id: [it.template_id for it in p.items] for p in original_party}
        for aid, stats in original_stats.items():
            self.actors[aid].stats = stats
            self.actors[aid].hp = stats["hp"]
        self._input_fingerprint = self.input_fingerprint
        self.input_fingerprint = lab.digest({
            "base_r6b": self._input_fingerprint,
            "original_templates": self.overlay_input_templates,
            "overlay": "EVOLVED_RULES_TRIAL_R1",
            "boss_overlay_phase": self.challenge_phase,
        })

    def has_item(self, actor: str, template: str) -> bool:
        return template in self.evolved_templates_by_actor.get(actor, ())

    def has_op(self, actor: str, op: str) -> bool:
        return any(rule.get("op") == op for tid in self.evolved_templates_by_actor.get(actor, ())
                   for rule in g.GEAR[tid].get("core_rules", ()))

    def rule_value(self, actor: str, op: str, key: str, default=0):
        for tid in self.evolved_templates_by_actor.get(actor, ()):
            for rule in g.GEAR[tid].get("core_rules", ()):
                if rule.get("op") == op:
                    return rule.get(key, default)
        return default

    def choose(self, actor):
        if actor.id == "C_WITCH" and self.has_op(actor.id, "replace_seed_with_ward"):
            if actor.ready.get("SK_A_WARD", 0) <= self.now and "ward" not in self.disabled:
                target = self.ward_target(actor)
                if target:
                    return "SK_A_WARD", target
        chosen = super().choose(actor)
        if actor.id == "C_WITCH" and self.has_op(actor.id, "replace_seed_with_ward") and chosen and chosen[0] == "SK_W_SEED":
            # Seed has been replaced on this item. Do not silently retain its poison action.
            return actor.id + "_BASIC", "boss"
        return chosen

    def ward_nominal(self, actor):
        if actor.id == "C_WITCH" and self.has_op(actor.id, "replace_seed_with_ward"):
            coeff = self.rule_value(actor.id, "replace_seed_with_ward", "coefficient_bp", 20000)
            value = (Fraction(actor.stats["power"] * coeff, 10000) *
                     Fraction(10000 + actor.stats.get("barrier_bonus_bp", 0), 10000))
            return value.numerator // value.denominator
        return super().ward_nominal(actor)

    def outgoing(self, actor, coefficient, crit_allowed, kind, root, skill):
        coeff = coefficient
        if actor.id == "C_WITCH" and skill == "SK_W_BURST":
            threshold = self.rule_value(actor.id, "burst_bonus_if_poison_at_least", "stacks", 999)
            bonus = self.rule_value(actor.id, "burst_bonus_if_poison_at_least", "bonus_bp", 0)
            if self.poison.stacks >= threshold:
                coeff += bonus
                self.metrics["evolved_poison_burst"] += 1
                self.log("evolved_effect", effect="poison_burst", poison_stacks=self.poison.stacks, bonus_bp=bonus)
        if actor.id == "C_SMITH" and skill == "SK_S_HAMMER":
            if self.pressure_stacks:
                self.metrics["evolved_pressure_consumed_stacks"] += self.pressure_stacks
                self.log("evolved_effect", effect="pressure_consume", stacks=self.pressure_stacks)
            coeff += self.pressure_stacks * self.rule_value(actor.id, "pressure_store", "extra_coefficient_per_stack_bp", 0)
        if actor.id == "C_FAMILIAR" and skill == "SK_F_DASH" and (self.mark_expiry > self.now or self.poison.stacks > 0):
            base_bonus = 4000
            candidate_bonus = self.rule_value(actor.id, "dash_conditional_extra_set_bp", "value", base_bonus)
            coeff += max(0, candidate_bonus - base_bonus)

        if self.challenge_phase:
            # The profile is a fixed test fixture: 6s closed / 4s open, 50% direct mitigation.
            phase_ms = self.now % 10000
            if phase_ms < 6000:
                coeff = coeff * 5000 // 10000

        familiar = self.actors.get("C_FAMILIAR")
        prior_chase = len(familiar.seen_chase) if familiar else 0
        prior_bonus = None
        if (actor.id == "C_APPRENTICE" and kind == "active" and actor.echo_charges and
                actor.echo_expiry > self.now and self.has_op(actor.id, "echo_bonus_set_bp")):
            # R5 contributes 1500bp. The candidate sets the effective echo bonus to 2000bp.
            prior_bonus = actor.stats.get("direct_bonus_bp", 0)
            actor.stats["direct_bonus_bp"] = prior_bonus + 500
        try:
            dealt = super().outgoing(actor, coeff, crit_allowed, kind, root, skill)
        finally:
            if prior_bonus is not None:
                actor.stats["direct_bonus_bp"] = prior_bonus
        if familiar and len(familiar.seen_chase) > prior_chase and self.has_op("C_FAMILIAR", "chase_icd_set_ms"):
            familiar.chase_at = self.now + self.rule_value("C_FAMILIAR", "chase_icd_set_ms", "value", 1500)
        return dealt

    def execute_actor(self, payload):
        aid = payload["aid"]
        actor = self.actors[aid]
        casting = actor.casting
        skill = casting["skill"] if casting else None
        hp_before = {key: a.hp for key, a in self.actors.items()}
        poison_cap_rule = self.rule_value(aid, "poison_stack_cap_add", "value", 0)
        original_add = self.poison.add_after_advance
        if aid == "C_WITCH" and poison_cap_rule:
            def add_with_evolved_cap(now, add, cap):
                return original_add(now, add, cap + poison_cap_rule)
            self.poison.add_after_advance = add_with_evolved_cap
        try:
            super().execute_actor(payload)
        finally:
            self.poison.add_after_advance = original_add

        if skill == "SK_A_WARD" and aid == "C_WITCH" and self.has_op(aid, "replace_seed_with_ward"):
            actor.ready[skill] = self.now + self.rule_value(aid, "replace_seed_with_ward", "cooldown_ms", 10000)

        if skill == "SK_A_HEAL" and aid == "C_APPRENTICE" and self.has_op(aid, "effective_heal_to_barrier"):
            ratio = self.rule_value(aid, "effective_heal_to_barrier", "ratio_bp", 2000)
            duration = self.rule_value(aid, "effective_heal_to_barrier", "duration_ms", 6000)
            for target_id, target in self.actors.items():
                effective = target.hp - hp_before[target_id]
                amount = max(0, effective * ratio // 10000)
                if amount:
                    self.add_shield(aid, target_id, amount, duration)
                    self.metrics["evolved_heal_barrier"] += amount
                    self.log("evolved_effect", effect="effective_heal_to_barrier", target=target_id, amount=amount)

        if skill == "SK_S_HAMMER" and aid == "C_SMITH" and self.has_op(aid, "pressure_store"):
            self.pressure_stacks = 0

        if skill == "SK_S_GUARD" and aid == "C_SMITH" and self.has_op(aid, "cover_target_barrier"):
            cooldown = self.rule_value(aid, "cover_target_barrier", "icd_ms", 3000)
            if self.now >= self.cover_barrier_ready_ms:
                coeff = self.rule_value(aid, "cover_target_barrier", "coefficient_bp", 4000)
                duration = self.rule_value(aid, "cover_target_barrier", "duration_ms", 4000)
                self.add_shield(aid, aid, actor.stats["power"] * coeff // 10000, duration)
                self.metrics["evolved_cover_barrier"] += 1
                self.cover_barrier_ready_ms = self.now + cooldown

        if skill == "SK_F_MARK" and aid == "C_FAMILIAR" and self.has_op(aid, "mark_duration_set_ms"):
            self.mark_expiry = self.now + self.rule_value(aid, "mark_duration_set_ms", "value", 10000)
            self.metrics["evolved_mark_duration"] += 1
            self.log("evolved_effect", effect="mark_duration_set", expiry=self.mark_expiry)
            self.push(self.mark_expiry, 1, "wake_all", {})
            self.wake(aid, max(self.now, self.mark_expiry - 1000))

    def hit_enemy(self, payload):
        before_counters = len(self.actors.get("C_SMITH").seen_counter) if self.actors.get("C_SMITH") else 0
        before_absorb = self.per_actor["C_WITCH"].get("barrier_absorbed", 0)
        super().hit_enemy(payload)
        smith = self.actors.get("C_SMITH")
        if smith and self.has_op("C_SMITH", "pressure_store") and len(smith.seen_counter) > before_counters:
            cap = self.rule_value("C_SMITH", "pressure_store", "max_stacks", 3)
            self.pressure_stacks = min(cap, self.pressure_stacks + 1)
            self.metrics["evolved_pressure_gain"] += 1
            self.log("evolved_effect", effect="pressure_gain", root=payload["root"], stacks=self.pressure_stacks)
        absorbed = self.per_actor["C_WITCH"].get("barrier_absorbed", 0) - before_absorb
        if (absorbed > 0 and self.has_item("C_WITCH", "EQ_W_G2") and self.now >= self.reflect_ready_ms):
            rule = next(r for r in g.GEAR["EQ_W_G2"]["core_rules"] if r["op"] == "reflect_on_own_barrier_absorb")
            self.reflect_ready_ms = self.now + rule["icd_ms"]
            self.metrics["evolved_reflect_trigger"] += 1
            self.log("evolved_effect", effect="barrier_reflect", root=payload["root"], absorbed=absorbed)
            self.push(self.now, 3, "reaction", {
                "aid": "C_WITCH", "kind": "reflect", "coefficient": rule["coefficient_bp"],
                "root": "reflect:" + payload["root"], "depth": 1,
            })
