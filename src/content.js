// Exact R2 content. Generated from content.json; no numerical edits.
export const DATA = {
  "schema_version": 1,
  "design_version": "R2.0-G1",
  "note": "All numbers are local prototype design hypotheses, not market observations.",
  "slots": [
    "weapon",
    "armor",
    "gloves",
    "boots",
    "charm",
    "ring"
  ],
  "base_stats": {
    "hp": 900,
    "attack": 60,
    "armor": 40,
    "crit_bp": 500,
    "crit_multiplier_bp": 17500,
    "haste_bp": 0,
    "block_bp": 500,
    "counter_bp": 0,
    "poison_damage": 0,
    "poison_duration_ms": 6000
  },
  "combat": {
    "time_limit_ms": 90000,
    "poison_stack_cap": 6,
    "block_reduction_bp": 5500
  },
  "items": {
    "weapon_c": {
      "slot": "weapon",
      "name": "燐火の剣",
      "family": "c",
      "cost": 120,
      "tier": 1,
      "stats": {
        "attack": 38,
        "crit_bp": 1500
      }
    },
    "weapon_p": {
      "slot": "weapon",
      "name": "胞子の短剣",
      "family": "p",
      "cost": 120,
      "tier": 1,
      "stats": {
        "attack": 20,
        "poison_damage": 8
      }
    },
    "weapon_g": {
      "slot": "weapon",
      "name": "番人の戦槌",
      "family": "g",
      "cost": 120,
      "tier": 1,
      "stats": {
        "attack": 20,
        "block_bp": 2000,
        "counter_bp": 7000
      }
    },
    "armor_c": {
      "slot": "armor",
      "name": "狩人の軽鎧",
      "family": "c",
      "cost": 120,
      "tier": 1,
      "stats": {
        "hp": 180,
        "armor": 10,
        "attack": 12
      }
    },
    "armor_p": {
      "slot": "armor",
      "name": "薬師の外套",
      "family": "p",
      "cost": 120,
      "tier": 1,
      "stats": {
        "hp": 260,
        "armor": 25,
        "poison_damage": 2
      }
    },
    "armor_g": {
      "slot": "armor",
      "name": "城壁の重鎧",
      "family": "g",
      "cost": 120,
      "tier": 1,
      "stats": {
        "hp": 420,
        "armor": 65
      }
    },
    "gloves_c": {
      "slot": "gloves",
      "name": "狙撃の手甲",
      "family": "c",
      "cost": 120,
      "tier": 1,
      "stats": {
        "attack": 12,
        "crit_bp": 2000
      }
    },
    "gloves_p": {
      "slot": "gloves",
      "name": "調合の手袋",
      "family": "p",
      "cost": 120,
      "tier": 1,
      "stats": {
        "haste_bp": 2200,
        "poison_damage": 4
      }
    },
    "gloves_g": {
      "slot": "gloves",
      "name": "受流しの手甲",
      "family": "g",
      "cost": 120,
      "tier": 1,
      "stats": {
        "block_bp": 2500
      }
    },
    "boots_c": {
      "slot": "boots",
      "name": "瞬歩の靴",
      "family": "c",
      "cost": 120,
      "tier": 1,
      "stats": {
        "haste_bp": 1800
      }
    },
    "boots_p": {
      "slot": "boots",
      "name": "湿原歩きの靴",
      "family": "p",
      "cost": 120,
      "tier": 1,
      "stats": {
        "hp": 140,
        "haste_bp": 1200
      }
    },
    "boots_g": {
      "slot": "boots",
      "name": "鉄根の脛当て",
      "family": "g",
      "cost": 120,
      "tier": 1,
      "stats": {
        "armor": 45,
        "hp": 160
      }
    },
    "charm_c": {
      "slot": "charm",
      "name": "燐光の護符",
      "family": "c",
      "cost": 120,
      "tier": 1,
      "stats": {
        "crit_multiplier_bp": 6000
      }
    },
    "charm_p": {
      "slot": "charm",
      "name": "発酵の護符",
      "family": "p",
      "cost": 120,
      "tier": 1,
      "stats": {
        "poison_damage": 4,
        "poison_duration_ms": 2000
      }
    },
    "charm_g": {
      "slot": "charm",
      "name": "棘鏡の護符",
      "family": "g",
      "cost": 120,
      "tier": 1,
      "stats": {
        "counter_bp": 9000,
        "block_bp": 1000
      }
    },
    "ring_c": {
      "slot": "ring",
      "name": "鋭眼の指輪",
      "family": "c",
      "cost": 120,
      "tier": 1,
      "stats": {
        "crit_bp": 1000,
        "attack": 18
      }
    },
    "ring_p": {
      "slot": "ring",
      "name": "腐葉の指輪",
      "family": "p",
      "cost": 120,
      "tier": 1,
      "stats": {
        "poison_damage": 2,
        "attack": 8
      }
    },
    "ring_g": {
      "slot": "ring",
      "name": "不退の指輪",
      "family": "g",
      "cost": 120,
      "tier": 1,
      "stats": {
        "block_bp": 1800,
        "armor": 30
      }
    }
  },
  "presets": {
    "critical": [
      "weapon_c",
      "armor_c",
      "gloves_c",
      "boots_c",
      "charm_c",
      "ring_c"
    ],
    "poison": [
      "weapon_p",
      "armor_p",
      "gloves_p",
      "boots_p",
      "charm_p",
      "ring_p"
    ],
    "counter": [
      "weapon_g",
      "armor_g",
      "gloves_g",
      "boots_g",
      "charm_g",
      "ring_g"
    ]
  },
  "bosses": {
    "gatekeeper": {
      "name": "崩門の番人",
      "hp": 3600,
      "armor": 30,
      "cycle_ms": 2500,
      "hit_offsets_ms": [
        2500
      ],
      "hit_damage": 190,
      "enrage_start_ms": 24000,
      "enrage_bp_per_second": 2500
    },
    "stonebeast": {
      "name": "苔殻の巨獣",
      "hp": 4800,
      "armor": 160,
      "cycle_ms": 3000,
      "hit_offsets_ms": [
        3000
      ],
      "hit_damage": 150,
      "enrage_start_ms": 55000,
      "enrage_bp_per_second": 1600
    },
    "sentinels": {
      "name": "群刃の衛兵",
      "hp": 6500,
      "armor": 40,
      "cycle_ms": 4000,
      "hit_offsets_ms": [
        1600,
        2200,
        2800,
        3400
      ],
      "hit_damage": 90,
      "enrage_start_ms": 55000,
      "enrage_bp_per_second": 1200
    }
  },
  "offline": {
    "step_ms": 900000,
    "cap_ms": 86400000,
    "essence_per_step": 5,
    "craft_cost": 120,
    "inventory_capacity": 72,
    "rollback_policy": "no_reward_explicit_rebase",
    "route_families": {
      "ash": "c",
      "fen": "p",
      "ruins": "g"
    },
    "safety_first_copy": true
  }
};
