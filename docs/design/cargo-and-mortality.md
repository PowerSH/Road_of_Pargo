# 적재(Cargo) + 유닛 사망 시스템

## 0. 디자인 의도

Backpack Hero식 **공간 적재 메카닉** + **유닛 영구 사망 가능성**을 결합해 세 가지 긴장을 만든다:

1. **소비 vs 보존**: 아이템 = 다음 도시 판매 이익 ∩ 지금 전투 승리 도구. 쓰면 이긴다, 안 쓰면 마진 확보.
2. **데스 스파이럴**: 유닛 사망 → 시체가 적재 공간 차지 → 아이템 공간 ↓ → 다음 전투 더 어려움 → 더 죽음.
3. **공간 퍼즐**: 회전·자동정렬 가능한 격자 위에서의 Tetris식 배치 최적화.

핵심 결정 사항 (사용자 확정):
- 아이템 **회전 허용**
- 적재 그리드와 시너지 5×3 격자는 **완전 별개**
- 시체 버리기 코스트 = **단순 공간 회수** (사기 페널티 없음)
- **자동 정렬 기능 제공**
- 아이템은 **전투 시작 전 미리 사용** (전투 중 발동 X)
- 부상 회복 시 **누적 페널티 없이 깨끗**

## 1. 적재 그리드

### 크기와 업그레이드 곡선

| 단계 | 그리드 | 셀 수 | 획득 시점 |
|---|---|---|---|
| 마차 | 4×3 | 12 | C1 시작 (기본) |
| 포장마차 | 5×3 | 15 | C1 중반 구매 |
| 대형마차 | 5×4 | 20 | C2 시작 |
| 소형 캐러밴 | 6×4 | 24 | C2 중반 |
| 대형 캐러밴 | 6×5 | 30 | C3 시작 |
| 카라반 행렬 | 7×5 | 35 | C3 중반 (선택) |

업그레이드는 도시 거래 화면에서 골드로 구매. 챕터 진행에 맞춰 가격 곡선 설계.

### 회전 (Rotation)
- 모든 아이템은 90° 단위 4방향 회전 가능.
- 회전한 모양도 원래 모양과 동일한 점유 셀로 계산.
- UI 단축키 권장: 드래그 중 R(혹은 우클릭)로 회전.

### 자동 정렬 (Auto-sort)
- 명시적 버튼으로 호출 (실시간 자동 X — 의도치 않게 사용자 배치를 뭉개면 안 됨).
- 정렬 알고리즘: 단순 First-Fit Decreasing(큰 아이템부터 좌상단부터 채움). 결정적·재현 가능.
- 정렬 후 사용자가 다시 손으로 옮길 수 있음. 자동 정렬은 **편의 도구**일 뿐 강제 아님.

### 점유 모델
- 그리드 = 2D 배열 (`width × height`).
- 각 셀: 비어있거나, 특정 아이템 인스턴스의 일부.
- 아이템 인스턴스는 (anchor 좌표, 회전 방향, 모양) 보유.
- 충돌 검사: 배치 시도 시 모양 셀 전부가 비어있어야 OK.

## 2. 아이템 모양 카탈로그

### 크기 클래스

| 클래스 | 모양 | 예시 | 비고 |
|---|---|---|---|
| 소형 | 1×1 | 회복 포션, 두루마리, 부적 | 빈 셀 메우는 용 |
| 중형 일자 | 1×2 또는 2×1 | 검, 활, 붕대, 보존식 | 가장 흔한 크기 |
| L자 | 3셀 L | 굽은 활, 광물 자루 | 회전이 의미 있는 모양 |
| 사각 | 2×2 | 갑옷, 식수통, 보석함 | 큰 가치, 큰 부담 |
| 시체 | 1×2 | 사망 유닛 | 자동 배치 시 가장자리 우선 |
| 거대 | 2×3 | 미니보스 트로피, 챕터 보스 드랍 | 매우 비싼 판매가, 매우 거추장스러움 |

### 아이템 인스턴스 데이터

```
CargoItem (Resource):
  id: StringName
  display_name: String
  shape_cells: Array[Vector2i]   # anchor 기준 점유 셀
  rotatable: bool                # 보통 true, 시체는 false 권장
  sell_value: int                # 도시에서 판매 시 받을 골드
  battle_effect: ItemEffect      # 전투 전 사용 시 효과 (null이면 비전투 아이템)
  rarity: Rarity                 # COMMON / UNCOMMON / RARE / EPIC
  chapter_tier: int              # 1/2/3 — 어느 챕터부터 등장하는지
```

## 3. 아이템 효과 (전투 전 사용)

### 결정: 전투 중 사용 X, 전투 시작 전에만

전투 화면 진입 직전 **준비 페이즈** 추가:
1. 적군 구성·예상 난이도 표시
2. 플레이어 보드 편성
3. **아이템 사용 단계** — 카고에서 아이템 선택, 효과 적용, 아이템 소모 → 적재 공간 회수
4. 전투 시작

### 효과 카테고리

| 카테고리 | 예시 효과 | 구현 위치 |
|---|---|---|
| **스탯 부스트** | 전 유닛 공격력 +20% / 특정 국가 유닛 HP +50 | 전투 시작 시 `ComputedStats`에 적용 |
| **시너지 보충** | 한 번만 가상의 인접 시너지 발동 ("전사 1명 추가로 친 것처럼") | `SynergyEngine` 실행 시 가상 룰 주입 |
| **임시 영입** | 일회용 NPC 유닛 1체 추가 배치 | 전투 시작 시 보드에 임시 유닛 스폰 |
| **적 약화** | 적군 공격 속도 -30% / 적 1명 처치 시작 | 적군 `ComputedStats`에 디버프 |
| **방어/회복** | 전 유닛 시작 HP +30% / 보호막 1회 | 전투 시작 시 유닛 stats 변형 |

### 효과 인터페이스 (구현 시점에 결정될 데이터 모델 스케치)

```
ItemEffect (Resource):
  effect_type: StringName        # "stat_boost" / "fake_synergy" / "temp_unit" / "enemy_debuff" / "shield"
  parameters: Dictionary         # 효과 종류별로 다른 파라미터
```

→ 단일 인터페이스, 여러 구현. 추가 효과 카테고리는 `effect_type` 추가만으로 확장.

## 4. 판매가 (Sell Value)

### 도시 판매 화면
- 카고에 적재된 아이템을 도시에서 골드로 환원.
- 골드는 다음 챕터 준비(유닛 영입, 그리드 확장, 부활)에 사용.

### 챕터별 판매 가격 모디파이어
- C1 도시: 베이스 1.0×
- C2 도시: 1.5×
- C3 도시: 2.0×

→ "당장 쓸 것인가, 더 비싸게 팔 것인가"의 추가 변수. 챕터 1에서 보존한 아이템은 챕터 3에서 두 배 비싸게 팔린다.

### 매입가 (구매 시)
- 도시 종류별로 다른 풀(예: 벤 도시에서는 벤 무기가 저렴).
- 매입가는 판매가의 1.5~2배 (시장 마진).

## 5. 유닛 상태 + HP 시스템

### HP Carry Over (라운드 4 합의)

유닛 HP는 **전투 사이에 영구 자원**으로 작동한다. 별도의 "런 HP" 게이지는 없음.

```
전투 1: 유닛 A (max_hp 100) → 35 데미지 받음 → 종료 시 65 HP
스테이지 이동 (자동 회복 없음)
전투 2: 유닛 A → 65 HP로 시작
쉼터 진입 → A의 HP 풀 회복
다음 전투: A → 100 HP로 시작
```

`OwnedUnit.current_hp`가 carry over의 저장소. -1이면 "max_hp 사용"으로 해석.

전투 시작 시 `CombatUnit.current_hp = min(OwnedUnit.current_hp, ComputedStats.max_hp)`. 시너지로 max_hp가 올라가도 carry over는 절대값 기준 그대로.

### 3상태 모델

```
[전투가능 Ready]
   │  전투 중 HP 0
   ▼
[부상 Injured]
   │  N 스테이지 미치료 (C1:4 / C2:3 / C3:2)
   ▼
[사망 Dead]
```

회복 경로 (라운드 4 갱신):

```
[부상] ──→ [전투가능]
  - 쉼터(여관) : HP 풀 회복 + 상태 전환 (HP=max). 무료
  - 도시 의무실: HP 풀 회복 + 상태 전환. 고가
  - 치료 아이템: 즉시 HP 풀 회복 + 상태 전환. 아이템 1개 소모

[사망] ──→ [전투가능]
  - 도시 신전/사원: 고가 골드 + 특수 아이템 (희귀)
  - 부활 코스트는 챕터 진행에 따라 급격히 상승
```

> 쉼터의 가치가 커진다. carry over로 인해 plain HP 회복도 의미 있음.

### 상태별 적재 공간 점유

| 상태 | 적재 점유 | 비고 |
|---|---|---|
| 전투가능 | 없음 | 캐러밴 크루석. 별도 인원 슬롯 시스템(추후) |
| 부상 | 없음 | 의무 마차에 누워서 이동. 게임 단순화 위해 점유 없음 |
| 사망 | **1×2** (시체) | 카고 그리드의 일부로 자동 배치 |

### 부상 → 사망 임계

| 챕터 | 임계 스테이지 |
|---|---|
| C1 (마을) | 4 스테이지 미치료 시 사망 |
| C2 (도시) | 3 스테이지 |
| C3 (국가) | 2 스테이지 |

→ 후반일수록 응급조치 압박 ↑. 부상자가 누적되면 한 챕터 안에 사망자가 쏟아짐.

### 회복 후 영구 페널티 없음
- 부상 → 전투가능 회복 시 스탯 100% 복구.
- 사망 → 부활 시 스탯 100% 복구.
- 즉 "흉터" 같은 영구 디버프 없음. 데스 페널티는 **자원(골드·아이템·공간)**으로만 표현.

### 시체 처리
- **부활**: 도시 신전에서 골드 + 특수 아이템 지불.
- **버리기 (Discard)**: 카고 공간 즉시 회수. 유닛은 영구 손실(다시 영입 불가).
- 시체는 회전 불가(`rotatable=false`). 1×2 형태 고정.

## 6. 데이터 모델 변경점 (구현 시 필요)

### 신규 클래스

```
OwnedUnit (Resource)
  source: UnitData
  status: Status        # READY / INJURED / DEAD
  injured_stages_left: int   # 부상→사망 카운트다운
  acquired_at: int      # 영입한 챕터/스테이지 (메타데이터)

CargoState (RefCounted)
  width: int
  height: int
  placements: Array[Placement]
  # Placement = {item: CargoItem, anchor: Vector2i, rotation: int}
  func can_place(item, anchor, rotation) -> bool
  func place(item, anchor, rotation) -> bool
  func remove(placement_id) -> CargoItem
  func auto_sort() -> void
  func find_slot_for(item) -> Placement|null

CargoItem (Resource)  # 위 §2 참고

ItemEffect (Resource) # 위 §3 참고

CityActions (RefCounted)
  func sell(state, item) -> int
  func buy(state, item, price) -> bool
  func heal(unit, gold_cost) -> bool
  func revive(unit, gold_cost, special_item) -> bool
  func upgrade_cargo(state, new_w, new_h, gold_cost) -> bool
```

### 기존 클래스 변경

```
RunState:
  - owned_units: Array[UnitData] → Array[OwnedUnit]
  - cargo: CargoState 추가
  - 각 스테이지 진입 시 OwnedUnit.injured_stages_left 감소 처리

BoardState:
  - place_unit(row, col, unit) → place_owned_unit(row, col, owned)
  - 부상/사망 유닛은 배치 거부

CombatUnit:
  - 전투 종료 시 HP 0 도달한 PLAYER 측 유닛 → OwnedUnit.status = INJURED
  - died 시그널의 의미 재정의: "이번 전투에서 다운됨" (영구 사망은 별도 절차)

SynergyEngine:
  - 변경 없음 (보드 입력만 받음 — 부상/사망 유닛은 보드에 안 들어옴)
```

→ 핵심 시너지 엔진과 전투 틱 코드는 **그대로 살아남음**. 변경은 주변 레이어(소유 유닛 추상화 + 카고 + 도시 액션)에만 집중.

## 7. 구현 우선순위 (제안)

1. **OwnedUnit + 상태 시스템** — `RunState` 갱신, 전투 후 부상 처리. 카고 없어도 동작 검증 가능.
2. **CargoState 기본 (회전 X)** — 그리드 + 충돌 검사 + 시체 자동 배치만.
3. **CargoItem + 판매가** — 도시 판매 화면 데이터 모델.
4. **회전 + 자동정렬** — UI 편의 기능. 시스템 완성 후.
5. **ItemEffect 인터페이스** — 한 번에 모든 효과 카테고리 구현 X. `stat_boost`부터.
6. **부활/치료/구매/그리드 확장** — 도시 거래 화면 UI 작업과 페어링.

## 8. TBD

| 항목 | 비고 |
|---|---|
| 아이템 풀 카탈로그 | 콘텐츠 작업. 카테고리 확정 후 |
| 부상 → 사망 임계의 챕터별 정확한 값 | C1=4/C2=3/C3=2 기본, 플레이테스트로 조정 |
| 그리드 확장 가격 곡선 | 골드 경제 안정화 후 |
| 부활 비용 곡선 | 동상 |
| 정찰 도구(맵 fog 일부 공개 아이템) | 아이템 풀 작업 시 |
