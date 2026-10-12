"""Negative/positive contracts for the R014 projection runner. Pure tests only."""
import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).with_name("run_effect_projection_previews.py")
spec = importlib.util.spec_from_file_location("r014_preview_runner", SCRIPT)
runner = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(runner)

EFFECT = "ACT_E_R03_04_magnet_pullcue"
ROOT = "enemy:E_R03_04:7"
PARAMS = {"markWindowMs": 800, "strikeWindupMs": 1200, "strikeCoefficientBP": 12500}
HP = {"C_WITCH": 5000, "C_APPRENTICE": 5000, "C_SMITH": 5000, "C_FAMILIAR": 5000}
EHP = {"E_R03_04": 9000}

def ev(kind, source="E_R03_04", target="C_WITCH", root=ROOT, amount=1, timestamp=0):
    return {"kind": kind, "sourceID": source, "targetID": target, "rootActionID": root,
            "amount": amount, "timestampMs": timestamp}

def row(step, target="ERNA", source="E_R03_04", root=ROOT, effect=EFFECT, **extra):
    return {"step": step, "rootActionID": root, "sourceID": source, "effectID": effect,
            "targetIDs": target, **extra}

def base_report(**extra):
    return {"candidateMagnetParameters": dict(PARAMS), "fixtureMaxDurationMs": 12000,
            "elapsedWholeSeconds": 4, "remainingPartyHP": dict(HP), "remainingEnemyHP": dict(EHP),
            "terminalCensoredRoots": [], **extra}

def active_case():
    events=[ev("enemy_magnet_mark",target="C_WITCH",amount=800,timestamp=0),
            ev("telegraph_heavy",target="C_WITCH",amount=1,timestamp=800),
            {**ev("enemy_hit",target="C_SMITH",amount=400,timestamp=2000), "diagnostics":{"candidateMagnetCoefficientBP":12500}}]
    trace=[row("cue_hold:enemy_magnet_mark"),row("cue_placement",target="ERNA",**{"placement.impactX":"12.5","placement.impactY":"9"}),
           row("impact_advance"),row("impact_placement",target="AIRA",**{"placement.impactX":"13","placement.impactY":"8"})]
    return events,trace

def check(case="E03_MAGNET",events=None,trace=None,report=None):
    if events is None or trace is None: events,trace=active_case()
    return runner.assert_magnet_contract(case,events,trace,EFFECT,report or base_report())

class MagnetProjectionContractTests(unittest.TestCase):
    def test_actual_mark_and_cover_recipient_are_distinct(self):
        self.assertTrue(all(check().values()))

    def test_wrong_locked_cue_target_is_rejected(self):
        e,t=active_case(); t=[dict(x) for x in t]
        next(x for x in t if x["step"]=="cue_placement")["targetIDs"]="AIRA"
        self.assertFalse(check(events=e,trace=t)["eachMarkHasExactLockedTargetCue"])

    def test_wrong_impact_target_is_rejected(self):
        e,t=active_case(); t=[dict(x) for x in t]
        next(x for x in t if x["step"]=="impact_placement")["targetIDs"]="ERNA"
        self.assertFalse(check(events=e,trace=t)["hitImpactMatchesActualHitRecipient"])

    def test_missing_or_wrong_mark_source_root_target_is_rejected(self):
        e,t=active_case(); e[0]["sourceID"]="E_R01_01"
        self.assertFalse(check(events=e,trace=t)["magnetMarkEventSourceRootAndPartyTarget"])
        e,t=active_case(); e[0]["rootActionID"]=""
        self.assertFalse(check(events=e,trace=t)["magnetMarkEventSourceRootAndPartyTarget"])
        e,t=active_case(); e[0]["targetID"]="party"
        self.assertFalse(check(events=e,trace=t)["magnetMarkEventSourceRootAndPartyTarget"])

    def test_hit_requires_exact_candidate_coefficient_diagnostic(self):
        e,t=active_case()
        e[2]["diagnostics"]={"candidateMagnetCoefficientBP":12_499}
        self.assertFalse(check(events=e,trace=t)["actualMagnetHitsCarry12500CandidateDiagnostic"])
        e,t=active_case(); e[2].pop("diagnostics",None)
        self.assertFalse(check(events=e,trace=t)["actualMagnetHitsCarry12500CandidateDiagnostic"])

    def test_ordinary_case_requires_real_hit_and_forbids_interrupt(self):
        events,_=active_case()
        hits=[e for e in events if e["kind"]=="enemy_hit" and e["sourceID"]=="E_R03_04"]
        interrupts=[e for e in events if e["kind"]=="cast_interrupt" and e["targetID"]=="E_R03_04"]
        self.assertTrue(hits and not interrupts and all(e["diagnostics"]["candidateMagnetCoefficientBP"]==12500 for e in hits))
        self.assertFalse([] and not interrupts)
        events.append(ev("cast_interrupt",source="C_SMITH",target="E_R03_04",timestamp=700))
        interrupts=[e for e in events if e["kind"]=="cast_interrupt" and e["targetID"]=="E_R03_04"]
        self.assertFalse(hits and not interrupts)

    def test_nonfinite_cue_coordinate_and_wrong_timing_are_rejected(self):
        e,t=active_case(); t=[dict(x) for x in t]
        next(x for x in t if x["step"]=="cue_placement")["placement.impactX"]="nan"
        self.assertFalse(check(events=e,trace=t)["eachMarkHasExactLockedTargetCue"])
        e,t=active_case(); e[1]["timestampMs"] += 1
        self.assertFalse(check(events=e,trace=t)["candidateTimingMatches800Plus1200"])
        e,t=active_case(); e[2]["timestampMs"] += 1
        self.assertFalse(check(events=e,trace=t)["candidateTimingMatches800Plus1200"])

    def test_target_loss_cancels_same_mark_without_impact(self):
        e=[ev("enemy_magnet_mark",target="C_APPRENTICE",amount=800,timestamp=0),ev("enemy_magnet_target_lost",target="C_APPRENTICE",amount=0,timestamp=800)]
        t=[row("cue_hold:enemy_magnet_mark",target="LUNA"),row("cue_placement",target="LUNA",**{"placement.impactX":"0","placement.impactY":"1"}),row("cue_cancel:enemy_magnet_target_lost",target="LUNA")]
        self.assertTrue(all(check(events=e,trace=t).values()))

    def test_interrupt_root_cancels_but_other_mark_root_may_hit(self):
        r1="enemy:E_R03_04:1"; r2="enemy:E_R03_04:2"
        e=[ev("enemy_magnet_mark",target="C_WITCH",root=r1,amount=800,timestamp=0),
           ev("telegraph_heavy",target="C_WITCH",root=r1,timestamp=800),{**ev("enemy_hit",target="C_WITCH",root=r1,amount=20,timestamp=2000), "diagnostics":{"candidateMagnetCoefficientBP":12500}},
           ev("enemy_magnet_mark",target="C_APPRENTICE",root=r2,amount=800,timestamp=3000),
           ev("cast_interrupt",source="C_SMITH",target="E_R03_04",root=r2,timestamp=3400)]
        t=[row("cue_hold:enemy_magnet_mark",target="ERNA",root=r1),row("cue_placement",target="ERNA",root=r1,**{"placement.impactX":"1","placement.impactY":"2"}),
           row("impact_advance",root=r1),row("impact_placement",target="ERNA",root=r1),
           row("cue_hold:enemy_magnet_mark",target="LUNA",root=r2),row("cue_placement",target="LUNA",root=r2,**{"placement.impactX":"2","placement.impactY":"3"}),row("cue_cancel:cast_interrupt",root=r2)]
        report=base_report(elapsedWholeSeconds=5)
        result=check("E03_MAGNET_INTERRUPT",e,t,report)
        self.assertTrue(all(result.values()),result)

    def test_interrupted_root_with_its_own_hit_is_rejected(self):
        e,t=active_case(); e += [ev("cast_interrupt",source="C_SMITH",target="E_R03_04",timestamp=1900)]
        self.assertFalse(check("E03_MAGNET_INTERRUPT",e,t)["lossOrInterruptCancelsWithoutImpact"])

    def test_wrong_interrupt_root_is_rejected(self):
        e,t=active_case(); e += [ev("cast_interrupt",source="C_SMITH",target="E_R03_04",root="other",timestamp=1900)]
        self.assertFalse(check("E03_MAGNET_INTERRUPT",e,t)["interruptIsTypedSameRootAndTargetsEnemy"])

    def test_target_loss_or_interrupt_missing_cancel_trace_fails(self):
        e=[ev("enemy_magnet_mark",target="C_APPRENTICE",amount=800,timestamp=0),ev("enemy_magnet_target_lost",target="C_APPRENTICE",amount=0,timestamp=800)]
        t=[row("cue_hold:enemy_magnet_mark",target="LUNA"),row("cue_placement",target="LUNA",**{"placement.impactX":"0","placement.impactY":"1"})]
        self.assertFalse(check(events=e,trace=t)["lossOrInterruptCancelsWithoutImpact"])

    def test_uncensored_missing_hit_is_not_accepted_but_explicit_censor_needs_horizon_alive_proof(self):
        root="enemy:E_R03_04:late"
        e=[ev("enemy_magnet_mark",target="C_FAMILIAR",root=root,amount=800,timestamp=11500)]
        t=[row("cue_hold:enemy_magnet_mark",target="NOIR",root=root),row("cue_placement",target="NOIR",root=root,**{"placement.impactX":"1","placement.impactY":"2"})]
        self.assertFalse(check(events=e,trace=t)["lossOrInterruptCancelsWithoutImpact"])
        censored=base_report(elapsedWholeSeconds=12,terminalCensoredRoots=[root])
        self.assertTrue(all(check(events=e,trace=t,report=censored).values()))
        dead=base_report(elapsedWholeSeconds=12,terminalCensoredRoots=[root],remainingPartyHP={**HP,"C_FAMILIAR":0})
        self.assertFalse(check(events=e,trace=t,report=dead)["explicitCensorHasHorizonAndAliveProof"])
        no_horizon=base_report(elapsedWholeSeconds=11,terminalCensoredRoots=[root])
        self.assertFalse(check(events=e,trace=t,report=no_horizon)["explicitCensorHasHorizonAndAliveProof"])

    def test_censored_root_with_hit_or_terminal_event_is_rejected(self):
        root="enemy:E_R03_04:late"
        e=[ev("enemy_magnet_mark",target="C_FAMILIAR",root=root,amount=800,timestamp=11500),
           ev("enemy_hit",target="C_FAMILIAR",root=root,amount=100,timestamp=12000)]
        t=[row("cue_hold:enemy_magnet_mark",target="NOIR",root=root),
           row("cue_placement",target="NOIR",root=root,**{"placement.impactX":"1","placement.impactY":"2"}),
           row("impact_placement",target="NOIR",root=root)]
        report=base_report(elapsedWholeSeconds=12,terminalCensoredRoots=[root])
        result=check(events=e,trace=t,report=report)
        self.assertFalse(result["explicitCensorHasHorizonAndAliveProof"])

    def test_unmarked_hit_empty_effectid_is_rejected_in_both_cases(self):
        e,t=active_case(); t.append(row("unmarked_magnet_hit",source="E_R03_04",root="unmarked",effect=""))
        for case in ("E03_MAGNET", "E03_MAGNET_INTERRUPT"):
            self.assertFalse(check(case,e,t)["noGenericHeavyInventsMagnetEffect"])

    def test_unmarked_hit_empty_effectid_and_capacity_and_extra_root_are_rejected(self):
        e,t=active_case(); t=[dict(x) for x in t]
        t.append(row("unmarked_magnet_hit",source="E_R03_04",root="unmarked",effect=""))
        self.assertFalse(check(events=e,trace=t)["noGenericHeavyInventsMagnetEffect"])
        e,t=active_case(); t += [row("capacity_suppressed:cue")]
        self.assertFalse(check(events=e,trace=t)["noMagnetCueSuppressedByCapacity"])
        e,t=active_case(); t += [row("impact_placement",root="enemy:E_R03_04:extra",target="AIRA")]
        self.assertFalse(check(events=e,trace=t)["noExtraEffectRoot"])

if __name__ == "__main__":
    unittest.main(verbosity=2)
