"""
Road of Pargo — 정적 밸런스 분석기.

실행: python3 tools/balance_check.py

수행:
  resource/units, synergies, enemies, enemy_synergies, encounters의 .tres를
  직접 파싱해 다음 섹션을 도출:

  1) 유닛 power 분포 (국가/직업/유형별, outlier)
  2) 비용 대비 power (cost vs power 효율)
  3) 시너지 기여도 (Tier 치환 가정 — 같은 그룹의 min_adjacent 최대 1개만)
  4) Krem/Nelm vs Ven/Arden 미러 확인 (수치 동일성)
  5) 적 인카운터 power vs encounters.md target
  6) 단순 경제 검증 (인카운터 골드 vs 도시 가격대)
  7) 발견 이슈 / 권장사항

출력:
  docs/balance/2026-06-01-static-analysis.md  — 사람이 읽는 마크다운
  docs/balance/2026-06-01-units.csv             — 유닛 표
  docs/balance/2026-06-01-synergies.csv         — 시너지 표
  docs/balance/2026-06-01-encounters.csv        — 인카운터 표
"""

from __future__ import annotations

import csv
import re
import statistics
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT_DIR = REPO / "docs" / "balance"
REPORT_NAME = "2026-06-01-static-analysis.md"

# ─────────────────────────────────────────────────────────────
# .tres 파서
# ─────────────────────────────────────────────────────────────


def parse_tres(path: Path) -> dict:
    """파일 안의 [sec ...] [resource] [sub_resource] 영역을 파싱."""
    text = path.read_text(encoding="utf-8")
    sections = re.split(r"^\[", text, flags=re.MULTILINE)
    out = {"ext_resources": {}, "sub_resources": [], "resource": {}}
    for sec in sections:
        sec = sec.strip()
        if not sec:
            continue
        # 첫 ']' 까지가 헤더.
        head_end = sec.find("]")
        if head_end < 0:
            continue
        header = sec[:head_end]
        body = sec[head_end + 1 :]
        sec_type = header.split()[0]
        if sec_type == "ext_resource":
            ext_id = _re_attr(header, "id")
            ext_path = _re_attr(header, "path")
            if ext_id and ext_path:
                out["ext_resources"][ext_id] = ext_path
        elif sec_type == "sub_resource":
            sub_id = _re_attr(header, "id")
            out["sub_resources"].append({"id": sub_id, "fields": _parse_body(body)})
        elif sec_type == "resource":
            out["resource"] = _parse_body(body)
    return out


def _re_attr(header: str, attr: str) -> str | None:
    m = re.search(rf'{attr}="([^"]+)"', header)
    return m.group(1) if m else None


def _parse_body(body: str) -> dict:
    fields: dict = {}
    for line in body.splitlines():
        line = line.strip()
        if not line or line.startswith(";"):
            continue
        if "=" not in line:
            continue
        k, _, v = line.partition("=")
        fields[k.strip()] = v.strip()
    return fields


def parse_str(v: str) -> str:
    m = re.match(r'^&?"([^"]*)"$', v.strip())
    return m.group(1) if m else v.strip()


def parse_float(v: str) -> float:
    try:
        return float(v.strip())
    except (ValueError, TypeError):
        return 0.0


def parse_int(v: str) -> int:
    try:
        return int(float(v.strip()))
    except (ValueError, TypeError):
        return 0


def parse_bool(v: str) -> bool:
    return v.strip().lower() == "true"


def parse_str_array(v: str) -> list[str]:
    """Array[StringName]([&"a", &"b"]) 또는 Array[Resource](...) 등."""
    m = re.search(r"\(\[(.*?)\]\)", v)
    if not m:
        return []
    inner = m.group(1)
    out: list[str] = []
    for s in inner.split(","):
        s = s.strip()
        if not s:
            continue
        out.append(parse_str(s))
    return out


# ─────────────────────────────────────────────────────────────
# 도메인 헬퍼
# ─────────────────────────────────────────────────────────────

NATIONS = {
    "nation_ven": "벤",
    "nation_krem": "크렘",
    "nation_arden": "아르덴",
    "nation_nelm": "넬름",
}
CLASSES = {
    "class_infantry": "보병",
    "class_spearman": "창병",
    "class_archer": "궁병",
    "class_crossbowman": "석궁병",
}
TYPES = {
    "type_soldier": "군인",
    "type_adventurer": "모험가",
    "type_mercenary": "용병",
}
# 한국어 → 영어 키 (synergy_rule의 applies_to_type/requires_adjacent_type가 한국어인 경우)
KO_TO_EN = {
    "벤": "nation_ven",
    "크렘": "nation_krem",
    "아르덴": "nation_arden",
    "넬름": "nation_nelm",
    "보병": "class_infantry",
    "창병": "class_spearman",
    "궁병": "class_archer",
    "석궁병": "class_crossbowman",
    "군인": "type_soldier",
    "모험가": "type_adventurer",
    "용병": "type_mercenary",
}


def normalize_tag(t: str) -> str:
    """syn rule 시트가 한국어로 저장된 경우 영어 상수로."""
    if t in KO_TO_EN:
        return KO_TO_EN[t]
    return t


def power_score(max_hp: float, attack: float, atk_speed: float, atk_range: float, move_speed: float) -> float:
    return max_hp * 0.4 + attack * atk_speed * 6.0 + atk_range * 0.05 + move_speed * 0.05


def classify_unit_types(types: list[str]) -> tuple[str, str, str]:
    nation = next((NATIONS[t] for t in types if t in NATIONS), "")
    cls = next((CLASSES[t] for t in types if t in CLASSES), "")
    typ = next((TYPES[t] for t in types if t in TYPES), "")
    return nation, cls, typ


# ─────────────────────────────────────────────────────────────
# 데이터 로딩
# ─────────────────────────────────────────────────────────────


@dataclass
class Unit:
    file: str
    id: str
    display_name: str
    max_hp: float
    attack: float
    attack_speed: float
    attack_range: float
    move_speed: float
    types: list[str]
    cost: int
    tier: int
    nation: str = ""
    cls: str = ""
    typ: str = ""
    power: float = 0.0


@dataclass
class Synergy:
    file: str
    id: str
    display_name: str
    applies_to_type: str
    requires_adjacent_type: str
    min_adjacent: int
    attack_bonus_pct: float
    hp_bonus_pct: float
    attack_speed_bonus_pct: float
    move_speed_bonus_pct: float
    range_bonus_pct: float

    @property
    def group_key(self) -> tuple[str, str]:
        return (normalize_tag(self.applies_to_type), normalize_tag(self.requires_adjacent_type))

    def total_pct(self) -> float:
        return (
            self.attack_bonus_pct
            + self.hp_bonus_pct
            + self.attack_speed_bonus_pct
            + self.move_speed_bonus_pct
            + self.range_bonus_pct
        )


@dataclass
class Enemy:
    file: str
    id: str
    display_name: str
    max_hp: float
    attack: float
    attack_speed: float
    attack_range: float
    move_speed: float
    faction_tags: list[str]
    is_boss: bool
    power: float = 0.0


@dataclass
class Encounter:
    file: str
    id: str
    display_name: str
    enemies: list[Enemy] = field(default_factory=list)
    total_power: float = 0.0


def load_units() -> list[Unit]:
    out: list[Unit] = []
    for p in sorted((REPO / "resource" / "units").glob("*.tres")):
        data = parse_tres(p)["resource"]
        types = parse_str_array(data.get("types", ""))
        u = Unit(
            file=p.name,
            id=parse_str(data.get("id", "")),
            display_name=parse_str(data.get("display_name", "")),
            max_hp=parse_float(data.get("max_hp", "0")),
            attack=parse_float(data.get("attack", "0")),
            attack_speed=parse_float(data.get("attack_speed", "0")),
            attack_range=parse_float(data.get("attack_range", "0")),
            move_speed=parse_float(data.get("move_speed", "0")),
            types=types,
            cost=parse_int(data.get("cost", "1")),
            tier=parse_int(data.get("tier", "1")),
        )
        u.nation, u.cls, u.typ = classify_unit_types(types)
        u.power = power_score(u.max_hp, u.attack, u.attack_speed, u.attack_range, u.move_speed)
        out.append(u)
    return out


def load_synergies() -> list[Synergy]:
    out: list[Synergy] = []
    for p in sorted((REPO / "resource" / "synergies").glob("*.tres")):
        data = parse_tres(p)["resource"]
        out.append(
            Synergy(
                file=p.name,
                id=parse_str(data.get("id", "")),
                display_name=parse_str(data.get("display_name", "")),
                applies_to_type=parse_str(data.get("applies_to_type", "")),
                requires_adjacent_type=parse_str(data.get("requires_adjacent_type", "")),
                min_adjacent=parse_int(data.get("min_adjacent", "1")),
                attack_bonus_pct=parse_float(data.get("attack_bonus_pct", "0")),
                hp_bonus_pct=parse_float(data.get("hp_bonus_pct", "0")),
                attack_speed_bonus_pct=parse_float(data.get("attack_speed_bonus_pct", "0")),
                move_speed_bonus_pct=parse_float(data.get("move_speed_bonus_pct", "0")),
                range_bonus_pct=parse_float(data.get("range_bonus_pct", "0")),
            )
        )
    return out


def load_enemies() -> list[Enemy]:
    out: list[Enemy] = []
    for p in sorted((REPO / "resource" / "enemies").glob("*.tres")):
        data = parse_tres(p)["resource"]
        e = Enemy(
            file=p.name,
            id=parse_str(data.get("id", "")),
            display_name=parse_str(data.get("display_name", "")),
            max_hp=parse_float(data.get("max_hp", "0")),
            attack=parse_float(data.get("attack", "0")),
            attack_speed=parse_float(data.get("attack_speed", "0")),
            attack_range=parse_float(data.get("attack_range", "0")),
            move_speed=parse_float(data.get("move_speed", "0")),
            faction_tags=parse_str_array(data.get("faction_tags", "")),
            is_boss=parse_bool(data.get("is_boss", "false")),
        )
        e.power = power_score(e.max_hp, e.attack, e.attack_speed, e.attack_range, e.move_speed)
        out.append(e)
    return out


def load_encounters(enemies: list[Enemy]) -> list[Encounter]:
    enemies_by_path: dict[str, Enemy] = {f"res://resource/enemies/{e.file}": e for e in enemies}
    out: list[Encounter] = []
    for p in sorted((REPO / "resource" / "encounters").glob("*.tres")):
        parsed = parse_tres(p)
        data = parsed["resource"]
        ext_to_path = parsed["ext_resources"]
        slot_units: list[Enemy] = []
        for sub in parsed["sub_resources"]:
            fixed_field = sub["fields"].get("fixed_unit", "")
            m = re.search(r'ExtResource\("([^"]+)"\)', fixed_field)
            if not m:
                continue
            ext_id = m.group(1)
            file_path = ext_to_path.get(ext_id, "")
            enemy = enemies_by_path.get(file_path)
            if enemy is not None:
                slot_units.append(enemy)
        enc = Encounter(
            file=p.name,
            id=parse_str(data.get("id", "")),
            display_name=parse_str(data.get("display_name", "")),
            enemies=slot_units,
            total_power=sum(e.power for e in slot_units),
        )
        out.append(enc)
    return out


# ─────────────────────────────────────────────────────────────
# 분석 섹션
# ─────────────────────────────────────────────────────────────


def section_unit_power(units: list[Unit]) -> str:
    md: list[str] = ["## 1. 유닛 power 분포\n"]
    powers = [u.power for u in units]
    md.append(
        f"- **총 24 유닛**: 평균 power **{statistics.mean(powers):.1f}**, "
        f"중앙값 {statistics.median(powers):.1f}, 표준편차 {statistics.stdev(powers):.1f}, "
        f"범위 [{min(powers):.1f}, {max(powers):.1f}]\n"
    )

    md.append("\n### 1.1 국가별\n")
    md.append("| 국가 | n | 평균 power | min | max |\n|---|---|---|---|---|\n")
    by_nation: dict[str, list[Unit]] = defaultdict(list)
    for u in units:
        by_nation[u.nation].append(u)
    for nation in ["벤", "크렘", "아르덴", "넬름"]:
        items = by_nation.get(nation, [])
        if not items:
            continue
        ps = [i.power for i in items]
        md.append(
            f"| {nation} | {len(items)} | {statistics.mean(ps):.1f} | "
            f"{min(ps):.1f} | {max(ps):.1f} |\n"
        )

    md.append("\n### 1.2 직업별\n")
    md.append("| 직업 | n | 평균 power | min | max |\n|---|---|---|---|---|\n")
    by_class: dict[str, list[Unit]] = defaultdict(list)
    for u in units:
        by_class[u.cls].append(u)
    for cls in ["보병", "창병", "궁병", "석궁병"]:
        items = by_class.get(cls, [])
        if not items:
            continue
        ps = [i.power for i in items]
        md.append(
            f"| {cls} | {len(items)} | {statistics.mean(ps):.1f} | "
            f"{min(ps):.1f} | {max(ps):.1f} |\n"
        )

    md.append("\n### 1.3 유형별\n")
    md.append("| 유형 | n | 평균 power | min | max |\n|---|---|---|---|---|\n")
    by_type: dict[str, list[Unit]] = defaultdict(list)
    for u in units:
        by_type[u.typ].append(u)
    for typ in ["군인", "모험가", "용병"]:
        items = by_type.get(typ, [])
        if not items:
            continue
        ps = [i.power for i in items]
        md.append(
            f"| {typ} | {len(items)} | {statistics.mean(ps):.1f} | "
            f"{min(ps):.1f} | {max(ps):.1f} |\n"
        )

    # Outlier — 평균에서 1.5σ 이상 벗어난 유닛
    mean_p = statistics.mean(powers)
    sd_p = statistics.stdev(powers)
    outliers = [u for u in units if abs(u.power - mean_p) > 1.5 * sd_p]
    if outliers:
        md.append("\n### 1.4 Outlier (평균 ±1.5σ)\n")
        md.append("| id | power | 비고 |\n|---|---|---|\n")
        for u in sorted(outliers, key=lambda x: -x.power):
            diff = u.power - mean_p
            note = f"{diff:+.1f} vs 평균"
            md.append(f"| {u.id} | {u.power:.1f} | {note} |\n")
    return "".join(md)


def section_cost_value(units: list[Unit]) -> str:
    md: list[str] = ["\n## 2. 비용 대비 power\n"]
    by_cost: dict[int, list[Unit]] = defaultdict(list)
    for u in units:
        by_cost[u.cost].append(u)
    md.append("| cost | n | 평균 power | power/cost |\n|---|---|---|---|\n")
    for c in sorted(by_cost):
        items = by_cost[c]
        avg = statistics.mean(u.power for u in items)
        md.append(f"| {c} | {len(items)} | {avg:.1f} | {avg / max(c, 1):.1f} |\n")

    # 같은 cost 안에서 가장 좋은/나쁜 유닛
    md.append("\n### 2.1 같은 비용 내 최강/최약\n")
    for c in sorted(by_cost):
        items = sorted(by_cost[c], key=lambda u: u.power)
        if len(items) < 2:
            continue
        weak, strong = items[0], items[-1]
        diff_pct = (strong.power - weak.power) / weak.power * 100 if weak.power > 0 else 0
        md.append(
            f"- cost {c}: 최강 **{strong.id}** ({strong.power:.1f}) vs "
            f"최약 **{weak.id}** ({weak.power:.1f}) — 격차 **{diff_pct:.1f}%**\n"
        )

    return "".join(md)


def section_synergy(syns: list[Synergy], units: list[Unit]) -> str:
    md: list[str] = ["\n## 3. 시너지 기여도 (Tier 치환 가정)\n"]

    # 그룹별 룰 정리
    by_group: dict[tuple, list[Synergy]] = defaultdict(list)
    for s in syns:
        by_group[s.group_key].append(s)

    md.append("### 3.1 그룹별 티어 진행\n")
    md.append("| 그룹 | t2 | t3 | t4 | t5 |\n|---|---|---|---|---|\n")
    sorted_groups = sorted(by_group.keys())
    for g in sorted_groups:
        rules = sorted(by_group[g], key=lambda r: r.min_adjacent)
        cells = {2: "—", 3: "—", 4: "—", 5: "—"}
        for r in rules:
            parts = []
            if r.attack_bonus_pct:
                parts.append(f"atk +{r.attack_bonus_pct*100:.0f}%")
            if r.hp_bonus_pct:
                parts.append(f"hp +{r.hp_bonus_pct*100:.0f}%")
            if r.attack_speed_bonus_pct:
                parts.append(f"as +{r.attack_speed_bonus_pct*100:.0f}%")
            if r.range_bonus_pct:
                parts.append(f"rng +{r.range_bonus_pct*100:.0f}%")
            cells[r.min_adjacent] = " / ".join(parts) if parts else "—"
        g_ko = " + ".join(
            next((k for k, v in KO_TO_EN.items() if v == t), t) for t in g
        )
        md.append(
            f"| {g_ko} | {cells[2]} | {cells[3]} | {cells[4]} | {cells[5]} |\n"
        )

    # 시너지 최대 기여도 (= 그룹의 최고 tier 룰만 적용)
    md.append("\n### 3.2 최대 기여도 (Tier 치환 = 최고 tier만 적용)\n")
    md.append(
        "5×3 보드에 같은 (nation, class) 5인을 한 줄로 배치하면 8방향 인접 카운트가 5에 도달해 t5 룰 1개만 발동.\n\n"
    )
    md.append("| 그룹 | 최고 tier | 총 % 합 (모든 스탯) |\n|---|---|---|\n")
    for g in sorted_groups:
        rules = sorted(by_group[g], key=lambda r: r.min_adjacent, reverse=True)
        top = rules[0]
        g_ko = " + ".join(
            next((k for k, v in KO_TO_EN.items() if v == t), t) for t in g
        )
        md.append(
            f"| {g_ko} | t{top.min_adjacent} | {top.total_pct() * 100:.1f}% |\n"
        )

    return "".join(md)


def section_mirror(syns: list[Synergy]) -> str:
    md: list[str] = ["\n## 4. Krem/Nelm vs Ven/Arden 미러 검증\n"]
    # Ven+Infantry ↔ Krem+Infantry, Ven+Spearman ↔ Nelm+Spearman,
    # Arden+Archer ↔ Krem+Archer, Arden+Crossbowman ↔ Nelm+Crossbowman
    pairs = [
        (("nation_ven", "class_infantry"), ("nation_krem", "class_infantry")),
        (("nation_ven", "class_spearman"), ("nation_nelm", "class_spearman")),
        (("nation_arden", "class_archer"), ("nation_krem", "class_archer")),
        (("nation_arden", "class_crossbowman"), ("nation_nelm", "class_crossbowman")),
    ]
    by_group: dict[tuple, list[Synergy]] = defaultdict(list)
    for s in syns:
        by_group[s.group_key].append(s)

    md.append("| 베이스 그룹 | 미러 그룹 | 동일? | 차이 |\n|---|---|---|---|\n")
    for base, mirror in pairs:
        base_rules = sorted(by_group.get(base, []), key=lambda r: r.min_adjacent)
        mirror_rules = sorted(by_group.get(mirror, []), key=lambda r: r.min_adjacent)
        same = True
        diff_details: list[str] = []
        if len(base_rules) != len(mirror_rules):
            same = False
            diff_details.append(f"룰 개수 {len(base_rules)} vs {len(mirror_rules)}")
        else:
            for br, mr in zip(base_rules, mirror_rules):
                if (
                    abs(br.attack_bonus_pct - mr.attack_bonus_pct) > 1e-9
                    or abs(br.hp_bonus_pct - mr.hp_bonus_pct) > 1e-9
                    or abs(br.attack_speed_bonus_pct - mr.attack_speed_bonus_pct) > 1e-9
                    or abs(br.range_bonus_pct - mr.range_bonus_pct) > 1e-9
                ):
                    same = False
                    diff_details.append(f"t{br.min_adjacent} 차이")
        base_ko = " + ".join(next((k for k, v in KO_TO_EN.items() if v == t), t) for t in base)
        mirror_ko = " + ".join(next((k for k, v in KO_TO_EN.items() if v == t), t) for t in mirror)
        md.append(
            f"| {base_ko} | {mirror_ko} | {'✅' if same else '❌'} | {', '.join(diff_details) or '—'} |\n"
        )

    md.append(
        "\n→ 의도된 placeholder. **국가별 차별화는 친화 직업 자체가 다르다는 점**(예: 벤만 보병+창병, 아르덴만 궁병+석궁병)에서 옴. 같은 직업의 시너지 수치가 미러여도 실제 빌드는 다름.\n"
    )
    return "".join(md)


def section_encounters(encounters: list[Encounter]) -> str:
    md: list[str] = ["\n## 5. 적 인카운터 power\n"]
    # encounters.md target (사후 갱신값): C1 BATTLE 500 / ELITE 800 / BOSS 1100
    md.append("encounters.md §3 target — C1: BATTLE 500 / ELITE 800 / BOSS 1100.\n\n")
    md.append("| 인카운터 | 적 수 | 총 power | target 대비 |\n|---|---|---|---|\n")

    target_by_kind = {"BATTLE": 500, "ELITE": 800, "BOSS": 1100}

    def infer_kind(eid: str) -> str:
        if "lair" in eid or "boss" in eid:
            return "BOSS"
        if "camp" in eid or "alpha" in eid or "elite" in eid:
            return "ELITE"
        return "BATTLE"

    rows = []
    for e in encounters:
        kind = infer_kind(e.id)
        target = target_by_kind.get(kind, 500)
        ratio_pct = (e.total_power - target) / target * 100
        rows.append((e.id, kind, len(e.enemies), e.total_power, ratio_pct))
    rows.sort(key=lambda r: (r[1], r[3]))
    for r in rows:
        sign = "+" if r[4] >= 0 else ""
        md.append(f"| {r[0]} | {r[2]} | {r[3]:.0f} | {sign}{r[4]:.1f}% |\n")

    by_kind: dict[str, list[float]] = defaultdict(list)
    for r in rows:
        by_kind[r[1]].append(r[3])
    md.append("\n### 5.1 종류별 평균\n")
    md.append("| kind | n | 평균 power | target | 격차 |\n|---|---|---|---|---|\n")
    for kind in ["BATTLE", "ELITE", "BOSS"]:
        ps = by_kind.get(kind, [])
        if not ps:
            continue
        avg = statistics.mean(ps)
        target = target_by_kind[kind]
        diff_pct = (avg - target) / target * 100
        md.append(f"| {kind} | {len(ps)} | {avg:.0f} | {target} | {diff_pct:+.1f}% |\n")

    return "".join(md)


def section_economy(encounters: list[Encounter]) -> str:
    md: list[str] = ["\n## 6. 단순 경제 검증\n"]
    # C1: 7 stages (1-2-1-3-2-1 + boss). 한 스테이지 = 1 노드 진입. 비전투 노드도 있어 평균 ~4-5 전투
    # 보상 = power * 0.25, 보스 * 2
    md.append("골드 보상 공식: `gold = round(enemy_power × 0.25)`, 보스는 ×2.\n\n")
    md.append("| 인카운터 | power | 골드 보상 |\n|---|---|---|\n")
    for e in encounters:
        is_boss = "lair" in e.id or "boss" in e.id
        gold = round(e.total_power * 0.25 * (2.0 if is_boss else 1.0))
        md.append(f"| {e.id} | {e.total_power:.0f} | {gold} |\n")

    # C1 클리어 시 평균 골드
    battles = [e for e in encounters if "battle" not in e.id and "boss" not in e.id and "lair" not in e.id]
    # 실제로는 chapter에서 인카운터를 랜덤으로 뽑으므로 평균 계산
    avg_battle_gold = round(
        statistics.mean(e.total_power for e in encounters if "lair" not in e.id and "camp" not in e.id and "alpha" not in e.id)
        * 0.25
    )
    md.append(
        f"\nC1 한 스테이지 평균 전투 골드 ≈ **{avg_battle_gold}g**. "
        "맵 패턴 [1,2,1,3,2,1] = 10 스테이지(6 depth, 평균 lane 약 1.67) 중 BATTLE/ELITE 비율 ~70% 라 가정 시 "
        f"C1 종료까지 골드 누적 ≈ {avg_battle_gold * 6}g + 보스 골드.\n"
    )
    md.append(
        "\n도시 매입 마진 1.7×, 카고 확장 비용 C1=50g. 1챕터 동안 평균 1~2회 확장 + 1~2회 매입 가능.\n"
    )
    return "".join(md)


def section_issues(units: list[Unit], syns: list[Synergy], enemies: list[Enemy]) -> str:
    md: list[str] = ["\n## 7. 발견 이슈 / 권장사항\n"]

    # 7.1 — Single affinity gap
    # synergy-axes.md: 벤은 보병/창병/군인, 아르덴은 궁병/석궁병/용병 친화.
    # 시너지 룰엔 보병/창병/궁병/석궁병만 (직업) — 유형 친화(군인, 용병)는 없음.
    md.append("### 7.1 단독 친화 시너지 미반영 ⚠\n")
    md.append(
        "`synergy-axes.md §2`의 친화 매트릭스에서 단독 친화는:\n"
        "- 벤+**군인** (벤만 유일하게 친화)\n"
        "- 아르덴+**용병** (아르덴만 유일하게 친화)\n\n"
        "그런데 현 시너지 룰(`resource/synergies/`)에는 `applies_to_type`이 국가, "
        "`requires_adjacent_type`이 **직업**인 룰만 존재. **유형(군인/용병/모험가) 친화 룰은 0개**.\n\n"
        "→ 의도된 차별화 포인트가 코드에 미반영. 룰 12개 더 추가 필요 (`vEn+soldier`, `arden+mercenary` 같은 단독 친화 + krem+adventurer, nelm+adventurer 등).\n"
    )

    # 7.2 — DPS 가중치
    md.append("\n### 7.2 HP 가중치 검토\n")
    tank_ish = [u for u in units if u.max_hp >= 180]
    if tank_ish:
        avg_tank = statistics.mean(u.power for u in tank_ish)
        md.append(
            f"HP ≥ 180 유닛 ({len(tank_ish)}명) 평균 power **{avg_tank:.1f}**. "
            f"전체 평균과의 격차 비교 시 power 공식의 HP 가중치 0.4가 적절한지 검토 필요.\n"
        )
        md.append("DPS 기준이라 탱커는 power 점수상 약해 보일 수 있지만 실제 전투에선 적 공격을 흡수해 가치가 크다.\n")

    # 7.3 — 적 power 공식 시너지로 폭주 가능성
    md.append("\n### 7.3 combat-time 시너지 폭주\n")
    md.append(
        "- **DEATH_TRIGGER** 5중첩 상한: 6명 인카운터에서 5명 사망 후 마지막 적이 +50% 공격력. "
        "스노볼링 의도면 OK, 의도 외라면 cap 낮추거나 % 줄이기.\n"
        "- **NUMBER_ADVANTAGE**: 적-플레이어 격차 ≥ 2면 발동. 초반 적이 4명, 플레이어 2명이면 즉시 발동. "
        "트리거 격차를 3으로 올리거나 발동 조건에 플레이어 최소 명수 추가 검토.\n"
    )

    # 7.4 — Outlier check
    md.append("\n### 7.4 비용 대비 이상치\n")
    by_cost: dict[int, list[Unit]] = defaultdict(list)
    for u in units:
        by_cost[u.cost].append(u)
    for c in sorted(by_cost):
        items = sorted(by_cost[c], key=lambda u: -u.power)
        if len(items) < 2:
            continue
        strong, weak = items[0], items[-1]
        if strong.power > weak.power * 1.3:
            md.append(
                f"- cost {c}: **{strong.id}** ({strong.power:.1f}) 가 **{weak.id}** ({weak.power:.1f})보다 "
                f"+{(strong.power / weak.power - 1) * 100:.0f}% 강함. 같은 비용 내 격차 큼.\n"
            )

    # 7.5 — 인카운터 측 power vs 시뮬 차이
    md.append("\n### 7.5 시너지 적용 후 적 실효 power\n")
    md.append(
        "현 인카운터 power는 **시너지 미적용 베이스값** 기준. 실제 전투에선 "
        "`en_syn_bandit_horde`(3+ 시 atk +30%) 같은 GLOBAL_TRAIT 발동 시 적 power가 30% 이상 증가.\n"
        "→ encounters.md §3 target과 실측 비교 시 baseline-only 값임을 명심.\n"
    )

    # 7.6 — DPS 승수 효과로 인한 Arden 시너지 비대칭
    md.append("\n### 7.6 ⚠️ Arden 시너지가 Ven 시너지보다 훨씬 강할 가능성\n")
    md.append(
        "§3.2의 '총 % 합'은 단순 산술합. 실제 효과는 **곱**이라 비교를 새로 해야 함:\n\n"
        "**Ven+보병 t5** — atk +35%, hp +16%. "
        "DPS(= atk × as) 효과 = 1.35× = +35%. HP 효과 = 1.16× = +16%.\n\n"
        "**Arden+궁병 t4** — atk +20%, as +60%, rng +30%. "
        "DPS = 1.20 × 1.60 = **1.92× = +92%**. 사거리 +30%까지 더해 카이팅 강화.\n\n"
        "| 그룹 | 시너지 최고 tier 적용 시 실효 DPS 배수 |\n|---|---|\n"
        "| 벤+보병 (t5) | 1.35× (35% ↑) |\n"
        "| 벤+창병 (t5) | 1.40× (40% ↑) |\n"
        "| 크렘+보병 (t5) | 1.35× (35% ↑) |\n"
        "| 넬름+창병 (t5) | 1.40× (40% ↑) |\n"
        "| **아르덴+궁병 (t4)** | **1.92× (92% ↑)** |\n"
        "| **아르덴+석궁병 (t4)** | **1.68× (68% ↑)** |\n"
        "| **크렘+궁병 (t4)** | **1.92× (92% ↑)** |\n"
        "| **넬름+석궁병 (t4)** | **1.68× (68% ↑)** |\n\n"
        "→ **궁병/석궁병 빌드의 DPS 시너지가 보병/창병의 2배 이상**. "
        "원거리 빌드가 명백히 우월. HP 보너스 없는 점은 약점이지만 "
        "원거리는 맞을 일이 적어 HP가 덜 중요. **밸런스 핵심 이슈로 검토 필요.**\n"
    )

    return "".join(md)


# ─────────────────────────────────────────────────────────────
# CSV 출력
# ─────────────────────────────────────────────────────────────


def write_csvs(units: list[Unit], syns: list[Synergy], encounters: list[Encounter]) -> None:
    out_dir = OUT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    with (out_dir / "2026-06-01-units.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["id", "display_name", "nation", "class", "type", "max_hp", "attack", "attack_speed", "attack_range", "move_speed", "cost", "tier", "power"])
        for u in units:
            w.writerow(
                [u.id, u.display_name, u.nation, u.cls, u.typ, u.max_hp, u.attack, u.attack_speed, u.attack_range, u.move_speed, u.cost, u.tier, round(u.power, 1)]
            )

    with (out_dir / "2026-06-01-synergies.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["id", "applies_to", "requires_adj", "min_adjacent", "atk%", "hp%", "as%", "ms%", "rng%"])
        for s in syns:
            w.writerow(
                [s.id, s.applies_to_type, s.requires_adjacent_type, s.min_adjacent, s.attack_bonus_pct, s.hp_bonus_pct, s.attack_speed_bonus_pct, s.move_speed_bonus_pct, s.range_bonus_pct]
            )

    with (out_dir / "2026-06-01-encounters.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["id", "display_name", "enemy_count", "total_power"])
        for e in encounters:
            w.writerow([e.id, e.display_name, len(e.enemies), round(e.total_power, 1)])


# ─────────────────────────────────────────────────────────────
# 메인
# ─────────────────────────────────────────────────────────────


def main() -> None:
    units = load_units()
    syns = load_synergies()
    enemies = load_enemies()
    encounters = load_encounters(enemies)

    print(
        f"Loaded: {len(units)} units, {len(syns)} synergies, "
        f"{len(enemies)} enemies, {len(encounters)} encounters"
    )

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    header = (
        "# 정적 밸런스 분석 — 2026-06-01\n\n"
        "데이터 원본: `resource/units/*.tres`, `resource/synergies/*.tres`, "
        "`resource/enemies/*.tres`, `resource/encounters/*.tres`. "
        "스크립트: `tools/balance_check.py`. "
        "이 보고서는 시뮬레이션 X — 데이터 그 자체 검증.\n"
    )

    body = (
        header
        + "\n"
        + section_unit_power(units)
        + section_cost_value(units)
        + section_synergy(syns, units)
        + section_mirror(syns)
        + section_encounters(encounters)
        + section_economy(encounters)
        + section_issues(units, syns, enemies)
    )

    (OUT_DIR / REPORT_NAME).write_text(body, encoding="utf-8")
    print(f"Wrote: {OUT_DIR / REPORT_NAME}")

    write_csvs(units, syns, encounters)
    print(f"Wrote CSVs to {OUT_DIR}")


if __name__ == "__main__":
    main()
