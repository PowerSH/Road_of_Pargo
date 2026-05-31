"""
Tier1_sheet.xlsx → UnitData/SynergyRule .tres 일괄 생성기.

실행: python generate_tres.py

- units_player 시트 → resource/units/{id}.tres (24개)
- synergies_player 시트 → resource/synergies/{id}.tres (14개)

ID/display_name 자동 부여 (시트 비어있을 때).
한국어 nation/class/type → SynergyTypes 상수 매핑.
"""

import sys, io, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

from openpyxl import load_workbook

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET_PATH = os.path.join(REPO, "sheet", "Tier1_sheet.xlsx")
UNITS_DIR = os.path.join(REPO, "resource", "units")
SYN_DIR = os.path.join(REPO, "resource", "synergies")
UNIT_SCRIPT_PATH = "res://scripts/data/unit_data.gd"
UNIT_SCRIPT_UID = "uid://bu6bc1s06t1ly"
SYN_SCRIPT_PATH = "res://scripts/data/synergy_rule.gd"
SYN_SCRIPT_UID = "uid://dh14thnp7fdr8"

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


def main():
    wb = load_workbook(SHEET_PATH, data_only=True)
    os.makedirs(UNITS_DIR, exist_ok=True)
    os.makedirs(SYN_DIR, exist_ok=True)

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


if __name__ == "__main__":
    main()
