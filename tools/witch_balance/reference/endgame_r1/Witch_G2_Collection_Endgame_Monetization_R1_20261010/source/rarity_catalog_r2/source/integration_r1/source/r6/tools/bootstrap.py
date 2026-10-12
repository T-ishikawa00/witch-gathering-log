"""Load immutable R5 and its R4/R2/R3 inputs from this package, not a Mac path."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
R5_ROOT = ROOT / 'vendor' / 'r5'
sys.path.insert(0, str(R5_ROOT / 'tools'))
from compare_candidates import prepared_at, boss_variant, intro_state, post_miniboss, LOCAL, g
from battle_r5 import BattleR5, PartyInput, Shield, SKILLS, ORDER, sha, canonical
from precision_rules import Profile
