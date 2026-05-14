# 시너지 축 설계

## 1. 축 개요

유닛은 시너지 계산용 태그를 **세 개의 축**에서 각각 정확히 하나씩 가진다. 추가 태그는 아이템·렐릭으로 부여 가능(아래 5절).

| 축 | 이름 | 값 | 코드 상수 |
|---|---|---|---|
| 1 | **소속 국가** | 벤 / 크렘 / 아르덴 / 넬름 | `NATION_VEN`, `NATION_KREM`, `NATION_ARDEN`, `NATION_NELM` |
| 2 | **직업** | 보병 / 창병 / 궁병 / 석궁병 | `CLASS_INFANTRY`, `CLASS_SPEARMAN`, `CLASS_ARCHER`, `CLASS_CROSSBOWMAN` |
| 3 | **유형** | 군인 / 모험가 / 용병 | `TYPE_SOLDIER`, `TYPE_ADVENTURER`, `TYPE_MERCENARY` |

상수 정의: `scripts/data/synergy_types.gd`.

## 2. 친화 매트릭스

각 국가는 특정 직업 2개 + 유형 1개에 시너지 친화도를 가진다.

| 국가 | 친화 직업 1 | 친화 직업 2 | 친화 유형 |
|---|---|---|---|
| 벤 (Ven) | 보병 | 창병 | 군인 |
| 크렘 (Krem) | 보병 | 궁병 | 모험가 |
| 아르덴 (Arden) | 궁병 | 석궁병 | 용병 |
| 넬름 (Nelm) | 창병 | 석궁병 | 모험가 |

### 친화도 관찰

- **보병**: 벤, 크렘 (북부/내륙 정규군 성격?)
- **창병**: 벤, 넬름
- **궁병**: 크렘, 아르덴
- **석궁병**: 아르덴, 넬름
- **군인**: 벤 단독 (벤이 정규군 국가)
- **모험가**: 크렘, 넬름
- **용병**: 아르덴 단독 (아르덴이 용병 국가?)

→ 직업 4종은 각각 2개 국가가 공유하지만 **벤의 군인**과 **아르덴의 용병**은 유일 친화라서 빌드 정체성이 강해진다. 밸런싱 시 의도된 비대칭인지 확인 필요.

## 3. 시너지 발동 해석

현재 채택한 해석:

> **국가 X 유닛은, 자신의 친화 태그(직업/유형)를 가진 유닛이 8방향 인접에 있을 때 강화된다.**

즉 시너지는 **국가 유닛 입장에서 발동**한다. 인접한 유닛 자신은 시너지를 받지 않는다(자기 국가 룰로 별도 발동할 수 있음).

### 예시

배치:
```
[ 벤·보병·군인 ][ 크렘·궁병·모험가 ]
```
- 좌측 벤 유닛: 인접에 크렘이 있고 크렘은 궁병/모험가다. **벤의 친화는 보병·창병·군인** → 크렘 유닛의 직업(궁병)·유형(모험가)은 벤 친화에 없음. **벤 시너지 미발동.**
- 우측 크렘 유닛: 인접에 벤이 있고 벤은 보병/군인이다. **크렘의 친화는 보병·궁병·모험가** → 인접 벤이 보병에 해당 ✓. **크렘 시너지 발동(+α%)**.

이 패턴은 "혼합 편성을 의도적으로 디자인"하게 만든다. 같은 국가만 모아도 친화도가 정확히 안 맞으면 시너지가 약해질 수 있음.

### 대안 해석 (아직 채택 X)

- (B) **양방향 시너지**: 인접한 두 유닛 모두 보너스. 더 관대.
- (C) **글로벌 트레이트** (TFT 스타일): 보드 전체에 벤 유닛 N개면 모든 벤 유닛 강화. 인접 무관.
- (D) **자기 친화 자기 강화**: 벤 유닛이 자기가 보병이면 무조건 보너스. 인접 무관.

현재 코드(`SynergyRule` + `SynergyEngine`)는 **(A) 인접 발동**만 구현. (B)(C)(D)는 룰 데이터 또는 엔진을 확장하면 됨. (C) 추가 시 `SynergyRule.scope: { ADJACENT, GLOBAL }` 필드를 도입.

## 4. SynergyRule 데이터 매핑

각 친화 관계는 `SynergyRule` 한 개에 해당. 총 **12개**의 룰이 필요(국가 4 × 친화 3 = 12).

룰 명세 패턴:
```
id: "ven_affinity_infantry"
display_name: "벤·보병 친화"
description: "벤 유닛이 인접에 보병을 두면 강화"
applies_to_type: NATION_VEN
requires_adjacent_type: CLASS_INFANTRY
min_adjacent: 1
attack_bonus_pct: <TBD>
hp_bonus_pct: <TBD>
attack_speed_bonus_pct: <TBD>
move_speed_bonus_pct: <TBD>
range_bonus_pct: <TBD>
```

### 전체 룰 목록 (수치는 유닛 카탈로그 확정 후 채움)

| 룰 ID | applies_to | requires_adjacent | 비고 |
|---|---|---|---|
| `ven_affinity_infantry` | 벤 | 보병 | |
| `ven_affinity_spearman` | 벤 | 창병 | |
| `ven_affinity_soldier` | 벤 | 군인 | 벤 단독 친화 |
| `krem_affinity_infantry` | 크렘 | 보병 | |
| `krem_affinity_archer` | 크렘 | 궁병 | |
| `krem_affinity_adventurer` | 크렘 | 모험가 | |
| `arden_affinity_archer` | 아르덴 | 궁병 | |
| `arden_affinity_crossbowman` | 아르덴 | 석궁병 | |
| `arden_affinity_mercenary` | 아르덴 | 용병 | 아르덴 단독 친화 |
| `nelm_affinity_spearman` | 넬름 | 창병 | |
| `nelm_affinity_crossbowman` | 넬름 | 석궁병 | |
| `nelm_affinity_adventurer` | 넬름 | 모험가 | |

## 5. 아이템 시너지 (확장 노트)

아이템은 유닛의 `types` 배열에 태그를 추가하거나, 런타임에 추가 `SynergyRule`을 `RunState.active_rules`에 주입하는 방식으로 시너지를 부여할 수 있다.

두 가지 패턴:

1. **태그 추가형**: 아이템 "벤의 깃발"을 장착하면 유닛의 `types`에 `NATION_VEN`을 추가 → 원래 벤이 아니어도 벤 시너지 룰들의 대상이 됨.
2. **룰 추가형**: 아이템 "정복의 깃발"을 보유하면 새 룰 `flag_of_conquest_buff`(예: 인접에 군인이 2개 이상이면 자기 공격력 +20%)를 `active_rules`에 추가.

→ 현재 `UnitData.types`가 `Array[StringName]`이고 `SynergyEngine.compute(board, rules)`가 룰 배열을 매번 받는 구조라 두 패턴 모두 코드 수정 없이 가능. 아이템 시스템은 별도 작업으로 분리.

## 6. 검증 도구

- `UnitData.validate_axes()` → 한 유닛이 각 축에서 정확히 1개의 태그를 가졌는지 검사. 누락·중복 시 문제 리스트 반환.
- 향후 추가 권장: `SynergyValidator.check_catalog(units, rules)` — 전체 카탈로그가 일관적인지(룰에 참조된 태그가 어떤 유닛에도 없으면 경고) 검사하는 정적 함수.

## 7. TBD (유닛 카탈로그 확정 후 결정)

- 각 룰의 보너스 수치 (% 값)
- 친화 누적 효과: 인접 2개 / 3개로 늘면 보너스가 누적되는가, 고정인가?
  - 누적이라면 `min_adjacent` 별 룰을 다단계로 만들거나, `SynergyRule`에 `per_stack_bonus` 필드 추가.
- 단독 친화(벤·군인, 아르덴·용병)에 더 큰 가중치를 줄지.
- 보스/엘리트 적의 시너지 보유 여부.
