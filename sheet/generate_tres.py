"""
Tier1_sheet.xlsx → 게임 데이터 일괄 생성기.

실행: python generate_tres.py

플레이어:
- units_player        → resource/units/{id}.tres            (UnitData)
- synergies_player    → resource/synergies/{id}.tres        (SynergyRule)

적군:
- units_enemy         → resource/enemies/{id}.tres          (EnemyUnitData)
- synergies_enemy     → resource/enemy_synergies/{id}.tres  (EnemySynergyRule)
- encounters_meta + encounters_slots
                      → resource/encounters/{id}.tres       (EncounterTemplate)

ID/display_name 자동 부여 (시트 비어있을 때).
한국어 nation/class/type → SynergyTypes 상수 매핑.
적 진영 / effect_type / kind 는 영문 그대로 사용.
"""

import sys, io, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

from openpyxl import load_workbook

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET_PATH = os.path.join(REPO, "sheet", "Tier1_sheet.xlsx")
UNITS_DIR = os.path.join(REPO, "resource", "units")
SYN_DIR = os.path.join(REPO, "resource", "synergies")
ENEMY_UNITS_DIR = os.path.join(REPO, "resource", "enemies")
ENEMY_SYN_DIR = os.path.join(REPO, "resource", "enemy_synergies")
ENC_DIR = os.path.join(REPO, "resource", "encounters")

UNIT_SCRIPT_PATH = "res://scripts/data/unit_data.gd"
UNIT_SCRIPT_UID = "uid://bu6bc1s06t1ly"
SYN_SCRIPT_PATH = "res://scripts/data/synergy_rule.gd"
SYN_SCRIPT_UID = "uid://dh14thnp7fdr8"

ENEMY_UNIT_SCRIPT_PATH = "res://scripts/data/enemy_unit_data.gd"
ENEMY_UNIT_SCRIPT_UID = "uid://r738wnf22nyt"
ENEMY_SYN_SCRIPT_PATH = "res://scripts/data/enemy_synergy_rule.gd"
ENEMY_SYN_SCRIPT_UID = "uid://dlramilp7tvl"
ENC_SCRIPT_PATH = "res://scripts/data/encounter_template.gd"
ENC_SCRIPT_UID = "uid://dbypymtf71qf8"
ENC_SLOT_SCRIPT_PATH = "res://scripts/data/encounter_slot.gd"
ENC_SLOT_SCRIPT_UID = "uid://nisd8sfxcxx1"

# EnemySynergyRule.EffectType enum (effect_type 문자열 → 정수)
ENEMY_EFFECT_TYPE = {
    "GLOBAL_TRAIT":      0,
    "BOSS_AURA":         1,
    "DEATH_TRIGGER":     2,
    "HP_THRESHOLD":      3,
    "NUMBER_ADVANTAGE":  4,
}

# MapNode.Kind enum (kind 문자열 → 정수). EncounterTemplate은 enum 안 쓰지만 검증용.
MAP_KIND = {
    "BATTLE": 0, "ELITE": 1, "SHOP": 2, "REST": 3,
    "EVENT": 4, "TREASURE": 5, "BOSS": 6,
}

# 한국어 → 상수 매핑
NATION = {
    "벤": ("nation_ven", "ven"),
    "크렘": ("nation_krem", "krem"),
    "아르덴": ("nation_arden", "arden"),
    "넬름": ("nation_nelm", "nelm"),
}
CLS = {
    "보병": ("class_infantry", "infantry"),
    "창병": ("class_spearman", "spearman"),
    "궁병": ("class_archer", "archer"),
    "석궁병": ("class_crossbowman", "crossbowman"),
}
TYP = {
    "군인": ("type_soldier", "soldier"),
    "모험가": ("type_adventurer", "adventurer"),
    "용병": ("type_mercenary", "mercenary"),
}


def unit_tres(uid: str, display: str, max_hp, atk, atk_spd, atk_rng, mv_spd,
              types_consts, cost, tier) -> str:
    types_lit = "Array[StringName]([" + ", ".join(f'&"{t}"' for t in types_consts) + "])"
    return f"""[gd_resource type="Resource" script_class="UnitData" load_steps=2 format=3]

[ext_resource type="Script" uid="{UNIT_SCRIPT_UID}" path="{UNIT_SCRIPT_PATH}" id="1_unit"]

[resource]
script = ExtResource("1_unit")
id = &"{uid}"
display_name = "{display}"
max_hp = {float(max_hp)}
attack = {float(atk)}
attack_speed = {float(atk_spd)}
attack_range = {float(atk_rng)}
move_speed = {float(mv_spd)}
types = {types_lit}
cost = {int(cost) if cost is not None else 1}
tier = {int(tier) if tier is not None else 1}
"""


def syn_tres(uid, display, description, applies_to, requires_adj, min_adj,
             atk_pct, hp_pct, atkspd_pct, mvspd_pct, rng_pct) -> str:
    return f"""[gd_resource type="Resource" script_class="SynergyRule" load_steps=2 format=3]

[ext_resource type="Script" uid="{SYN_SCRIPT_UID}" path="{SYN_SCRIPT_PATH}" id="1_syn"]

[resource]
script = ExtResource("1_syn")
id = &"{uid}"
display_name = "{display}"
description = "{description}"
applies_to_type = &"{applies_to}"
requires_adjacent_type = &"{requires_adj}"
min_adjacent = {int(min_adj)}
attack_bonus_pct = {float(atk_pct or 0.0)}
hp_bonus_pct = {float(hp_pct or 0.0)}
attack_speed_bonus_pct = {float(atkspd_pct or 0.0)}
move_speed_bonus_pct = {float(mvspd_pct or 0.0)}
range_bonus_pct = {float(rng_pct or 0.0)}
"""


def enemy_unit_tres(uid, display, max_hp, atk, atk_spd, atk_rng, mv_spd,
                    faction_tags, is_boss) -> str:
    factions = [t.strip() for t in str(faction_tags or "").split(",") if t.strip()]
    factions_lit = "Array[StringName]([" + ", ".join(f'&"{t}"' for t in factions) + "])"
    return f"""[gd_resource type="Resource" script_class="EnemyUnitData" load_steps=2 format=3]

[ext_resource type="Script" uid="{ENEMY_UNIT_SCRIPT_UID}" path="{ENEMY_UNIT_SCRIPT_PATH}" id="1_eu"]

[resource]
script = ExtResource("1_eu")
id = &"{uid}"
display_name = "{display}"
max_hp = {float(max_hp)}
attack = {float(atk)}
attack_speed = {float(atk_spd)}
attack_range = {float(atk_rng)}
move_speed = {float(mv_spd)}
faction_tags = {factions_lit}
is_boss = {"true" if bool(is_boss) else "false"}
"""


def enemy_syn_tres(uid, display, description, effect_type_int, trigger_faction,
                   trigger_count, hp_threshold,
                   atk_pct, hp_pct, atkspd_pct, mvspd_pct, rng_pct) -> str:
    return f"""[gd_resource type="Resource" script_class="EnemySynergyRule" load_steps=2 format=3]

[ext_resource type="Script" uid="{ENEMY_SYN_SCRIPT_UID}" path="{ENEMY_SYN_SCRIPT_PATH}" id="1_es"]

[resource]
script = ExtResource("1_es")
id = &"{uid}"
display_name = "{display}"
description = "{description}"
effect_type = {int(effect_type_int)}
trigger_faction = &"{trigger_faction or ''}"
trigger_count = {int(trigger_count or 1)}
hp_threshold = {float(hp_threshold or 0.0)}
attack_bonus_pct = {float(atk_pct or 0.0)}
hp_bonus_pct = {float(hp_pct or 0.0)}
attack_speed_bonus_pct = {float(atkspd_pct or 0.0)}
move_speed_bonus_pct = {float(mvspd_pct or 0.0)}
range_bonus_pct = {float(rng_pct or 0.0)}
"""


def encounter_tres(uid, display, power_target_override, slot_specs, rule_paths) -> str:
    """
    slot_specs: list of dicts { row, col, fixed_unit_path?, variation_pool_paths: list,
                                optional: bool, skip_chance: float }
    rule_paths: list of res:// paths to EnemySynergyRule .tres
    """
    # ExtResource 등록 — 슬롯이 참조하는 EnemyUnitData + 룰들 + EncounterSlot script
    ext_lines = []
    next_id = 1
    ext_id_for_path = {}

    def reg(path, uid_str, type_):
        nonlocal next_id
        if path in ext_id_for_path:
            return ext_id_for_path[path]
        ext_id = f"{next_id}_{type_}"
        next_id += 1
        ext_id_for_path[path] = ext_id
        if uid_str:
            ext_lines.append(f'[ext_resource type="Resource" uid="{uid_str}" path="{path}" id="{ext_id}"]')
        else:
            ext_lines.append(f'[ext_resource type="Resource" path="{path}" id="{ext_id}"]')
        return ext_id

    # EncounterSlot script (먼저)
    slot_script_id = f"{next_id}_sl_script"
    ext_lines.append(f'[ext_resource type="Script" uid="{ENC_SLOT_SCRIPT_UID}" path="{ENC_SLOT_SCRIPT_PATH}" id="{slot_script_id}"]')
    next_id += 1
    # EncounterTemplate script
    enc_script_id = f"{next_id}_et_script"
    ext_lines.append(f'[ext_resource type="Script" uid="{ENC_SCRIPT_UID}" path="{ENC_SCRIPT_PATH}" id="{enc_script_id}"]')
    next_id += 1

    # 슬롯별 fixed_unit / variation_pool 의 ExtResource 등록
    for spec in slot_specs:
        if spec.get("fixed_unit_path"):
            reg(spec["fixed_unit_path"], spec.get("fixed_unit_uid", ""), "u")
        for pp, pu in spec.get("variation_pool", []):
            reg(pp, pu, "u")

    # 룰들의 ExtResource 등록
    for rp, ru in rule_paths:
        reg(rp, ru, "r")

    # sub_resource (인라인 EncounterSlot 들)
    sub_resources = []
    slot_subres_ids = []
    for i, spec in enumerate(slot_specs):
        sid = f"Resource_slot_{i}"
        slot_subres_ids.append(sid)
        fixed_lit = "null"
        if spec.get("fixed_unit_path"):
            fid = ext_id_for_path[spec["fixed_unit_path"]]
            fixed_lit = f'ExtResource("{fid}")'
        pool_items = []
        for pp, pu in spec.get("variation_pool", []):
            pid = ext_id_for_path[pp]
            pool_items.append(f'ExtResource("{pid}")')
        pool_lit = "Array[Resource]([" + ", ".join(pool_items) + "])"
        sub_resources.append(f'''[sub_resource type="Resource" id="{sid}"]
script = ExtResource("{slot_script_id}")
row = {int(spec["row"])}
col = {int(spec["col"])}
fixed_unit = {fixed_lit}
variation_pool = {pool_lit}
optional = {"true" if spec.get("optional") else "false"}
skip_chance = {float(spec.get("skip_chance", 0.0))}
''')

    slots_lit = "Array[Resource]([" + ", ".join(f'SubResource("{sid}")' for sid in slot_subres_ids) + "])"
    rules_lit_items = []
    for rp, ru in rule_paths:
        rid = ext_id_for_path[rp]
        rules_lit_items.append(f'ExtResource("{rid}")')
    rules_lit = "Array[Resource]([" + ", ".join(rules_lit_items) + "])"

    load_steps = 1 + len(ext_lines) + len(sub_resources)

    body = f'[gd_resource type="Resource" script_class="EncounterTemplate" load_steps={load_steps} format=3]\n\n'
    body += "\n".join(ext_lines) + "\n\n"
    body += "\n".join(sub_resources) + "\n"
    body += f'''[resource]
script = ExtResource("{enc_script_id}")
id = &"{uid}"
display_name = "{display}"
power_target_override = {float(power_target_override) if power_target_override is not None else -1.0}
slots = {slots_lit}
rules = {rules_lit}
'''
    return body


def main():
    wb = load_workbook(SHEET_PATH, data_only=True)
    os.makedirs(UNITS_DIR, exist_ok=True)
    os.makedirs(SYN_DIR, exist_ok=True)
    os.makedirs(ENEMY_UNITS_DIR, exist_ok=True)
    os.makedirs(ENEMY_SYN_DIR, exist_ok=True)
    os.makedirs(ENC_DIR, exist_ok=True)

    # ─── UNITS ───
    ws = wb["units_player"]
    headers = [ws.cell(1, c).value for c in range(1, ws.max_column + 1)]
    h = {name: idx for idx, name in enumerate(headers) if name}
    print(f"units_player headers: {headers}")

    unit_count = 0
    for r in range(2, ws.max_row + 1):
        row = [ws.cell(r, c + 1).value for c in range(ws.max_column)]
        nation_ko = row[h["nation"]]
        class_ko = row[h["class"]]
        type_ko = row[h["type"]]
        if not (nation_ko and class_ko and type_ko):
            continue
        nation_const, nation_short = NATION[nation_ko]
        class_const, class_short = CLS[class_ko]
        type_const, type_short = TYP[type_ko]

        # ID 자동: ven_infantry_soldier 패턴
        sheet_id = row[h["id"]]
        uid = sheet_id if sheet_id else f"{nation_short}_{class_short}_{type_short}"
        # display_name 자동: "벤 군인 보병" 패턴
        sheet_dn = row[h["display_name"]]
        display = sheet_dn if sheet_dn else f"{nation_ko} {type_ko} {class_ko}"

        tres = unit_tres(
            uid=uid,
            display=display,
            max_hp=row[h["max_hp"]],
            atk=row[h["attack"]],
            atk_spd=row[h["attack_speed"]],
            atk_rng=row[h["attack_range"]],
            mv_spd=row[h["move_speed"]],
            types_consts=[nation_const, class_const, type_const],
            cost=row[h["cost"]],
            tier=row[h["tier"]],
        )
        out_path = os.path.join(UNITS_DIR, f"{uid}.tres")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(tres)
        unit_count += 1
    print(f"✅ Generated {unit_count} unit .tres → {UNITS_DIR}")

    # ─── SYNERGIES ───
    ws = wb["synergies_player"]
    headers = [ws.cell(1, c).value for c in range(1, ws.max_column + 1)]
    h = {name: idx for idx, name in enumerate(headers) if name}
    print(f"\nsynergies_player headers: {headers}")

    syn_count = 0
    for r in range(2, ws.max_row + 1):
        row = [ws.cell(r, c + 1).value for c in range(ws.max_column)]
        applies_ko = row[h["applies_to_type"]]
        requires_ko = row[h["requires_adjacent_type"]]
        min_adj = row[h["min_adjacent"]]
        if not (applies_ko and requires_ko and min_adj is not None):
            continue

        # applies_to_type 은 시트엔 한국어 ("벤"), 상수로 변환
        if applies_ko in NATION:
            applies_const, applies_short = NATION[applies_ko]
        elif applies_ko in CLS:
            applies_const, applies_short = CLS[applies_ko]
        elif applies_ko in TYP:
            applies_const, applies_short = TYP[applies_ko]
        else:
            print(f"  ⚠ row {r}: unknown applies_to_type '{applies_ko}', skipping")
            continue

        if requires_ko in NATION:
            requires_const, requires_short = NATION[requires_ko]
        elif requires_ko in CLS:
            requires_const, requires_short = CLS[requires_ko]
        elif requires_ko in TYP:
            requires_const, requires_short = TYP[requires_ko]
        else:
            print(f"  ⚠ row {r}: unknown requires_adjacent_type '{requires_ko}', skipping")
            continue

        sheet_id = row[h["id"]]
        uid = sheet_id if sheet_id else f"syn_{applies_short}_{requires_short}_t{int(min_adj)}"
        sheet_dn = row[h["display_name"]]
        display = sheet_dn if sheet_dn else f"{applies_ko}+{requires_ko} T{int(min_adj)}"
        description = row[h["description"]] or ""

        # 시트 컬럼: attack_bonus_pct, hp_bonus_pct, attack_speed_bonus_pct, range_bonus_pct
        # move_speed_bonus_pct 컬럼 없음 → 0
        tres = syn_tres(
            uid=uid,
            display=display,
            description=description,
            applies_to=applies_const,
            requires_adj=requires_const,
            min_adj=min_adj,
            atk_pct=row[h["attack_bonus_pct"]],
            hp_pct=row[h["hp_bonus_pct"]],
            atkspd_pct=row[h["attack_speed_bonus_pct"]],
            mvspd_pct=0.0,  # 시트에 컬럼 없음
            rng_pct=row[h["range_bonus_pct"]],
        )
        out_path = os.path.join(SYN_DIR, f"{uid}.tres")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(tres)
        syn_count += 1
    print(f"✅ Generated {syn_count} synergy .tres → {SYN_DIR}")

    # ─── ENEMY UNITS ───
    ws = wb["units_enemy"]
    headers = [ws.cell(1, c).value for c in range(1, ws.max_column + 1)]
    h = {name: idx for idx, name in enumerate(headers) if name}
    enemy_unit_count = 0
    enemy_unit_paths = {}  # id → (res:// path, uid_str (빈 문자열로 둠))
    for r in range(2, ws.max_row + 1):
        row = [ws.cell(r, c + 1).value for c in range(ws.max_column)]
        eid = row[h["id"]]
        if not eid:
            continue
        tres = enemy_unit_tres(
            uid=eid,
            display=row[h["display_name"]] or eid,
            max_hp=row[h["max_hp"]],
            atk=row[h["attack"]],
            atk_spd=row[h["attack_speed"]],
            atk_rng=row[h["attack_range"]],
            mv_spd=row[h["move_speed"]],
            faction_tags=row[h["faction_tags"]],
            is_boss=row[h["is_boss"]],
        )
        out_path = os.path.join(ENEMY_UNITS_DIR, f"{eid}.tres")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(tres)
        # res:// 경로는 ResourceLoader가 처리. UID는 비워둠 (Godot이 import 시 자동 부여).
        enemy_unit_paths[eid] = (f"res://resource/enemies/{eid}.tres", "")
        enemy_unit_count += 1
    print(f"✅ Generated {enemy_unit_count} enemy unit .tres → {ENEMY_UNITS_DIR}")

    # ─── ENEMY SYNERGIES ───
    ws = wb["synergies_enemy"]
    headers = [ws.cell(1, c).value for c in range(1, ws.max_column + 1)]
    h = {name: idx for idx, name in enumerate(headers) if name}
    enemy_syn_count = 0
    enemy_syn_paths = {}  # id → (res:// path, "")
    for r in range(2, ws.max_row + 1):
        row = [ws.cell(r, c + 1).value for c in range(ws.max_column)]
        sid = row[h["id"]]
        if not sid:
            continue
        etype = row[h["effect_type"]]
        if etype not in ENEMY_EFFECT_TYPE:
            print(f"  ⚠ row {r}: unknown effect_type '{etype}', skipping")
            continue
        tres = enemy_syn_tres(
            uid=sid,
            display=row[h["display_name"]] or sid,
            description=row[h["notes"]] or "",
            effect_type_int=ENEMY_EFFECT_TYPE[etype],
            trigger_faction=row[h["trigger_faction"]] or "",
            trigger_count=row[h["trigger_count"]] or 1,
            hp_threshold=row[h["hp_threshold"]] or 0.0,
            atk_pct=row[h["attack_bonus_pct"]],
            hp_pct=row[h["hp_bonus_pct"]],
            atkspd_pct=row[h["attack_speed_bonus_pct"]],
            mvspd_pct=row[h["move_speed_bonus_pct"]],
            rng_pct=row[h["range_bonus_pct"]],
        )
        out_path = os.path.join(ENEMY_SYN_DIR, f"{sid}.tres")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(tres)
        enemy_syn_paths[sid] = (f"res://resource/enemy_synergies/{sid}.tres", "")
        enemy_syn_count += 1
    print(f"✅ Generated {enemy_syn_count} enemy synergy .tres → {ENEMY_SYN_DIR}")

    # ─── ENCOUNTERS (meta + slots 조인) ───
    ws_meta = wb["encounters_meta"]
    meta_headers = [ws_meta.cell(1, c).value for c in range(1, ws_meta.max_column + 1)]
    hm = {name: idx for idx, name in enumerate(meta_headers) if name}

    ws_slots = wb["encounters_slots"]
    slot_headers = [ws_slots.cell(1, c).value for c in range(1, ws_slots.max_column + 1)]
    hs = {name: idx for idx, name in enumerate(slot_headers) if name}

    # 인카운터 ID → 슬롯 리스트 매핑
    slots_by_enc = {}
    for r in range(2, ws_slots.max_row + 1):
        row = [ws_slots.cell(r, c + 1).value for c in range(ws_slots.max_column)]
        encid = row[hs["encounter_id"]]
        if not encid:
            continue
        fixed_id = row[hs["fixed_unit_id"]]
        pool_raw = row[hs["variation_pool_ids"]]
        pool_ids = [p.strip() for p in str(pool_raw or "").split(",") if p.strip()]
        spec = {
            "row": row[hs["row"]] or 0,
            "col": row[hs["col"]] or 0,
            "optional": bool(row[hs["optional"]]),
            "skip_chance": row[hs["skip_chance"]] or 0.0,
        }
        if fixed_id and fixed_id in enemy_unit_paths:
            path, uid_str = enemy_unit_paths[fixed_id]
            spec["fixed_unit_path"] = path
            spec["fixed_unit_uid"] = uid_str
        spec["variation_pool"] = [enemy_unit_paths[pid] for pid in pool_ids if pid in enemy_unit_paths]
        slots_by_enc.setdefault(encid, []).append(spec)

    enc_count = 0
    for r in range(2, ws_meta.max_row + 1):
        row = [ws_meta.cell(r, c + 1).value for c in range(ws_meta.max_column)]
        encid = row[hm["id"]]
        if not encid:
            continue
        rule_raw = row[hm["rule_ids"]]
        rule_ids = [s.strip() for s in str(rule_raw or "").split(",") if s.strip()]
        rule_paths = [enemy_syn_paths[rid] for rid in rule_ids if rid in enemy_syn_paths]
        power_override = row[hm["power_target_override"]]

        tres = encounter_tres(
            uid=encid,
            display=row[hm["display_name"]] or encid,
            power_target_override=power_override,
            slot_specs=slots_by_enc.get(encid, []),
            rule_paths=rule_paths,
        )
        out_path = os.path.join(ENC_DIR, f"{encid}.tres")
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(tres)
        enc_count += 1
    print(f"✅ Generated {enc_count} encounter .tres → {ENC_DIR}")


if __name__ == "__main__":
    main()
