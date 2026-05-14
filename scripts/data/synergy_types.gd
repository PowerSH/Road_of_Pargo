class_name SynergyTypes
extends RefCounted

## 시너지 축 상수 모음 + 친화 매트릭스. 절대 인스턴스화하지 말 것 — 네임스페이스 용도.
## StringName은 내부적으로 interned 되므로 비교가 O(1)이고, 오타는 grep으로 즉시 잡힌다.

# ─────────────────────────────────────────────────────────────
# Axis 1: 소속 국가
# ─────────────────────────────────────────────────────────────
const NATION_VEN: StringName = &"nation_ven"        # 벤
const NATION_KREM: StringName = &"nation_krem"      # 크렘
const NATION_ARDEN: StringName = &"nation_arden"    # 아르덴
const NATION_NELM: StringName = &"nation_nelm"      # 넬름

# ─────────────────────────────────────────────────────────────
# Axis 2: 직업
# ─────────────────────────────────────────────────────────────
const CLASS_INFANTRY: StringName = &"class_infantry"        # 보병
const CLASS_SPEARMAN: StringName = &"class_spearman"        # 창병
const CLASS_ARCHER: StringName = &"class_archer"            # 궁병
const CLASS_CROSSBOWMAN: StringName = &"class_crossbowman"  # 석궁병

# ─────────────────────────────────────────────────────────────
# Axis 3: 유형
# ─────────────────────────────────────────────────────────────
const TYPE_SOLDIER: StringName = &"type_soldier"          # 군인
const TYPE_ADVENTURER: StringName = &"type_adventurer"    # 모험가
const TYPE_MERCENARY: StringName = &"type_mercenary"      # 용병

# ─────────────────────────────────────────────────────────────
# 전수 리스트 (검증·UI 루프용)
# ─────────────────────────────────────────────────────────────
const ALL_NATIONS: Array[StringName] = [
	NATION_VEN, NATION_KREM, NATION_ARDEN, NATION_NELM
]
const ALL_CLASSES: Array[StringName] = [
	CLASS_INFANTRY, CLASS_SPEARMAN, CLASS_ARCHER, CLASS_CROSSBOWMAN
]
const ALL_TYPES: Array[StringName] = [
	TYPE_SOLDIER, TYPE_ADVENTURER, TYPE_MERCENARY
]

# ─────────────────────────────────────────────────────────────
# 친화 매트릭스: 국가 → 시너지가 발동하는 축2/축3 태그 모음.
# "벤 유닛은 인접에 보병/창병/군인이 있을 때 강화" 식의 해석을 코드화한 것.
# 보너스 수치(% 값)는 유닛 카탈로그 확정 후 SynergyRule .tres 데이터로 분리 저장.
# ─────────────────────────────────────────────────────────────
const AFFINITY: Dictionary = {
	NATION_VEN: [CLASS_INFANTRY, CLASS_SPEARMAN, TYPE_SOLDIER],
	NATION_KREM: [CLASS_INFANTRY, CLASS_ARCHER, TYPE_ADVENTURER],
	NATION_ARDEN: [CLASS_ARCHER, CLASS_CROSSBOWMAN, TYPE_MERCENARY],
	NATION_NELM: [CLASS_SPEARMAN, CLASS_CROSSBOWMAN, TYPE_ADVENTURER],
}


## 어떤 축에 속하는 태그인지 분류 (디버깅·UI 그룹핑용).
static func axis_of(tag: StringName) -> StringName:
	if ALL_NATIONS.has(tag):
		return &"nation"
	if ALL_CLASSES.has(tag):
		return &"class"
	if ALL_TYPES.has(tag):
		return &"type"
	return &"unknown"


## 태그를 한국어 디스플레이 이름으로. (UI에서 i18n 시스템 도입 전까지 임시 사용)
static func display_name_ko(tag: StringName) -> String:
	match tag:
		NATION_VEN: return "벤"
		NATION_KREM: return "크렘"
		NATION_ARDEN: return "아르덴"
		NATION_NELM: return "넬름"
		CLASS_INFANTRY: return "보병"
		CLASS_SPEARMAN: return "창병"
		CLASS_ARCHER: return "궁병"
		CLASS_CROSSBOWMAN: return "석궁병"
		TYPE_SOLDIER: return "군인"
		TYPE_ADVENTURER: return "모험가"
		TYPE_MERCENARY: return "용병"
		_: return String(tag)
