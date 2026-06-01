class_name CityActions
extends RefCounted

## 도시 거래(shop/hub) 순수 로직. UI와 분리.
## cargo-and-mortality.md §4 (판매가/매입가) + §5 (회복/부활) 참조.
##
## 모든 함수는 호출자가 RunState/CargoState 인스턴스를 전달하는 stateless 헬퍼.
## 성공 시 true, 실패 시 false (조건 미충족 — 골드 부족, 카고 공간 부족, 상태 잘못 등).

## 챕터별 판매가 배수 (cargo-and-mortality.md §4)
##  C1=1.0 / C2=1.5 / C3=2.0
const SELL_MULTIPLIER: Dictionary = {1: 1.0, 2: 1.5, 3: 2.0}

## 매입가 = 판매가 × MARKET_MARGIN (시장 마진)
const MARKET_MARGIN: float = 1.7

## 회복 비용 — 도시 의무실(여관과 별개, 즉시 회복 + 비싼).
## 챕터 비례 — 후반일수록 상승.
const HEAL_COST_BY_CHAPTER: Dictionary = {1: 15, 2: 30, 3: 60}

## 사망 → 부활 비용. 챕터 비례 가파른 상승.
const REVIVE_COST_BY_CHAPTER: Dictionary = {1: 80, 2: 200, 3: 500}

## 카고 그리드 1열 확장 비용. 가로/세로 모두 같은 비용.
const CARGO_EXPAND_COST_BY_CHAPTER: Dictionary = {1: 50, 2: 120, 3: 250}


# ─────────────────────────────────────────────────────────────
# 판매 / 구매
# ─────────────────────────────────────────────────────────────

## 카고의 아이템을 판매. RunState.gold 증가 + 카고에서 제거.
## 챕터 비례 보너스 적용.
static func sell(run: RunState, item: CargoItem) -> bool:
	if run == null or item == null:
		return false
	if not run.cargo.contains(item):
		return false
	var mult: float = SELL_MULTIPLIER.get(run.chapter, 1.0)
	var price: int = int(round(float(item.sell_value) * mult))
	run.cargo.remove(item)
	run.gold += price
	return true


## 도시 상점에서 매입. RunState.gold 차감 + 카고에 자동 배치.
## 카고에 공간이 없으면 거래 실패(골드 차감 X).
static func buy(run: RunState, item: CargoItem) -> bool:
	if run == null or item == null:
		return false
	var mult: float = SELL_MULTIPLIER.get(run.chapter, 1.0)
	var price: int = int(round(float(item.sell_value) * mult * MARKET_MARGIN))
	if run.gold < price:
		return false
	# 자동 배치 시도 — 공간 없으면 거래 무산.
	var slot: Dictionary = run.cargo.find_slot_for(item)
	if slot.is_empty():
		return false
	run.gold -= price
	run.cargo.place(item, slot["anchor"], slot["rotation"])
	return true


# ─────────────────────────────────────────────────────────────
# 회복 / 부활
# ─────────────────────────────────────────────────────────────

## 도시 의무실에서 1유닛 즉시 회복 (쉼터와 별개, 골드 소비).
## 풀 HP + INJURED→READY. DEAD는 별도 부활.
static func heal(run: RunState, owned: OwnedUnit) -> bool:
	if run == null or owned == null:
		return false
	if owned.status == OwnedUnit.Status.DEAD:
		return false
	var cost: int = HEAL_COST_BY_CHAPTER.get(run.chapter, 30)
	if run.gold < cost:
		return false
	if not owned.heal_full():
		return false
	run.gold -= cost
	return true


## 사망 유닛 부활. 도시 신전 한정. 카고에서 시체 CargoItem이 있다면 제거(후속 — 시체 CargoItem 도입 후).
static func revive(run: RunState, owned: OwnedUnit) -> bool:
	if run == null or owned == null:
		return false
	if owned.status != OwnedUnit.Status.DEAD:
		return false
	var cost: int = REVIVE_COST_BY_CHAPTER.get(run.chapter, 200)
	if run.gold < cost:
		return false
	owned.revive()
	run.gold -= cost
	return true


# ─────────────────────────────────────────────────────────────
# 카고 그리드 확장
# ─────────────────────────────────────────────────────────────

## 카고 그리드 가로 1칸 확장 (width += 1). 골드 차감.
static func expand_cargo_width(run: RunState) -> bool:
	if run == null:
		return false
	var cost: int = CARGO_EXPAND_COST_BY_CHAPTER.get(run.chapter, 100)
	if run.gold < cost:
		return false
	if not run.cargo.resize(run.cargo.width + 1, run.cargo.height):
		return false
	run.gold -= cost
	return true


## 카고 그리드 세로 1칸 확장 (height += 1). 골드 차감.
static func expand_cargo_height(run: RunState) -> bool:
	if run == null:
		return false
	var cost: int = CARGO_EXPAND_COST_BY_CHAPTER.get(run.chapter, 100)
	if run.gold < cost:
		return false
	if not run.cargo.resize(run.cargo.width, run.cargo.height + 1):
		return false
	run.gold -= cost
	return true


# ─────────────────────────────────────────────────────────────
# 가격 조회 (UI 표시용 — 거래 시도 안 함)
# ─────────────────────────────────────────────────────────────

static func sell_price(run: RunState, item: CargoItem) -> int:
	if run == null or item == null:
		return 0
	var mult: float = SELL_MULTIPLIER.get(run.chapter, 1.0)
	return int(round(float(item.sell_value) * mult))


static func buy_price(run: RunState, item: CargoItem) -> int:
	if run == null or item == null:
		return 0
	var mult: float = SELL_MULTIPLIER.get(run.chapter, 1.0)
	return int(round(float(item.sell_value) * mult * MARKET_MARGIN))


static func heal_cost(run: RunState) -> int:
	return HEAL_COST_BY_CHAPTER.get(run.chapter if run != null else 1, 30)


static func revive_cost(run: RunState) -> int:
	return REVIVE_COST_BY_CHAPTER.get(run.chapter if run != null else 1, 200)


static func cargo_expand_cost(run: RunState) -> int:
	return CARGO_EXPAND_COST_BY_CHAPTER.get(run.chapter if run != null else 1, 100)
