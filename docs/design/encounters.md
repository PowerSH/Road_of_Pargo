# 인카운터 + 적 시너지 시스템

## 0. 합의된 결정 (5회차 — 2026-05-26)

| 항목 | 결정 |
|---|---|
| 적 라인업 생성 | **카탈로그 + 약간의 무작위 변동** — `EncounterTemplate`로 시드 정의, 슬롯의 variation_pool로 다양성 |
| 적 시너지 형태 | **플레이어와 다른 5개 패턴** — `EnemySynergyRule.EffectType`로 분기 |
| 적 유닛 데이터 | **별도 신규** — `EnemyUnitData` (플레이어 `UnitData`와 분리) |
| 인카운터 난이도 | **적 유닛 power_score 합으로 자동 산정** — 휴리스틱 공식 + 수동 오버라이드 가능 |
| 적군 5×3 배치 | **자체 시너지 적용 받음** — `enemy_board: BoardState` + `enemy_synergy_engine` 별도 운영 |

진영(faction) 목록과 챕터별 유닛 카탈로그는 **사용자가 추후 전달**. 그때까지 이 문서의 mock 예시를 placeholder로 사용.

## 1. 데이터 모델

### 클래스 4종 (`scripts/data/`)

```
EnemyUnitData (Resource)
  id, display_name
  max_hp, attack, attack_speed, attack_range, move_speed
  faction_tags: Array[StringName]
  is_boss: bool
  icon, sprite
  + compute_power_score() -> float
  + has_faction(t) -> bool

EnemySynergyRule (Resource)
  id, display_name, description
  effect_type: EffectType         # GLOBAL_TRAIT / BOSS_AURA / DEATH_TRIGGER / HP_THRESHOLD / NUMBER_ADVANTAGE
  trigger_faction, trigger_count, hp_threshold
  attack_bonus_pct, hp_bonus_pct, ..., range_bonus_pct
  + is_pre_battle() -> bool

EncounterSlot (Resource)
  row, col
  fixed_unit: EnemyUnitData | null
  variation_pool: Array[EnemyUnitData]
  optional: bool
  skip_chance: float

EncounterTemplate (Resource)
  id, display_name
  power_target_override: float = -1.0   # -1이면 자동 산정
  slots: Array[EncounterSlot]
  rules: Array[EnemySynergyRule]
  + compute_total_power() -> float
  + count_boss_slots() -> int
```

플레이어 `UnitData`와 의도적으로 분리. 같은 인터페이스를 강요하지 않아 향후 적 전용 능력(소환, 폭발, 디버프 등) 추가 시 자유롭게 확장 가능.

## 2. 5개 시너지 패턴

### A. `GLOBAL_TRAIT` — 글로벌 트레이트 (TFT 식)
- **트리거**: 보드 위 `trigger_faction` 유닛이 `trigger_count` 마리 이상
- **적용**: 그 진영 전체 보너스
- **적용 시점**: pre-battle (`ComputedStats` 변형)
- **예시**: "산적단 3마리 이상 → 전 산적 공격력 +30%"

### B. `BOSS_AURA` — 보스 오라
- **트리거**: 같은 진영(trigger_faction) 부하가 보스(`is_boss=true`)와 8방향 인접
- **적용**: 그 부하에게 보너스
- **적용 시점**: pre-battle
- **예시**: "두목 인접 부하 → 공속 +50%"
- **메모**: 보스가 사망하면? combat-time 변형 필요할 수 있음 → 우선은 pre-battle 단순화

### C. `DEATH_TRIGGER` — 복수
- **트리거**: 적 1마리 사망
- **적용**: 생존 적 전체에 누적 보너스 (사망 시마다 stacking)
- **적용 시점**: combat-time (`CombatManager`가 적 사망 시그널 감지)
- **예시**: "동료 1명 사망 시 남은 적 공격력 ×1.10 (중첩 가능)"
- **메모**: stacking 상한 둘 것을 권장 (예: 최대 5중첩)

### D. `HP_THRESHOLD` — 광폭화
- **트리거**: 자신의 HP가 `hp_threshold` 이하로 떨어짐
- **적용**: 자기 강화 (1회)
- **적용 시점**: combat-time
- **예시**: "HP 50% 이하 시 자기 공격력 +50%, 공속 +20%"
- **메모**: HP가 다시 회복돼도 보너스 유지 vs 회복 시 해제 — 일단 **유지** (한 번 발동하면 끝까지)

### E. `NUMBER_ADVANTAGE` — 수 우위
- **트리거**: 살아있는 적 수 - 살아있는 플레이어 유닛 수 ≥ `trigger_count`
- **적용**: 적 전체 또는 trigger_faction
- **적용 시점**: combat-time (매 틱 검사, 동적으로 on/off)
- **예시**: "플레이어보다 2명 이상 많을 때 전 적 이동속도 +25%"

### 통합 포인트

| 패턴 | 어디서 평가 | 어떤 구조 |
|---|---|---|
| A (GLOBAL_TRAIT) | pre-battle | enemy_board iterate → count faction → apply to ComputedStats |
| B (BOSS_AURA) | pre-battle | enemy_board iterate → check adjacent to boss → apply |
| C (DEATH_TRIGGER) | combat-time | CombatUnit.died 시그널 listener → 생존 유닛에 누적 boost |
| D (HP_THRESHOLD) | combat-time | CombatUnit.damaged 시그널 listener → 임계 도달 시 1회 적용 |
| E (NUMBER_ADVANTAGE) | combat-time | CombatManager._process에서 매 틱 alive count 비교 → 동적 buff/debuff |

pre-battle 평가는 기존 `SynergyEngine` 옆에 `EnemySynergyEngine.compute_pre_battle()` 추가. combat-time 평가는 `CombatManager`에 새 hook들 추가.

## 3. Power Score 공식

```
power_score = max_hp * 0.4
            + attack * attack_speed * 6.0
            + attack_range * 0.05
            + move_speed * 0.05
```

가중치 의도:
- HP: 생존력 — 0.4
- DPS (attack × attack_speed): 출력 — 6.0 가장 큰 가중치
- 사거리: 약간의 우위
- 이동속도: 위치 선점 — 약간

밸런싱 시 계수 조정. EnemyUnitData에 `compute_power_score()` 메서드로 노출.

### 챕터별 target power (1차 가이드라인)

| 노드 | C1 | C2 | C3 |
|---|---|---|---|
| BATTLE (일반) | 100 | 180 | 320 |
| ELITE (미니보스) | 160 | 290 | 520 |
| BOSS (챕터 보스) | 220 | 400 | 740 |

이 값은 `EncounterTemplate.power_target_override` 또는 generator의 챕터 곱셈을 통해 적용. progression.md §4의 챕터 배수 (1.0 / 1.6 / 2.8)와 결과적으로 같은 곡선이 되도록 조정.

## 4. Mock 데이터 (사용자 카탈로그 도착 전 임시)

> 실제 카탈로그는 추후 전달. 아래는 시스템 검증용 mock — 코드에 하드코딩하지 말고 `.tres`로 받아 교체할 것.

### Mock 진영 4개

| 태그 | 이름 | 챕터 컨셉 |
|---|---|---|
| `MOCK_BANDIT` | 산적 | C1 — 도로 강도 |
| `MOCK_BEAST` | 야수 | C1~C2 — 야생 짐승 |
| `MOCK_SOLDIER` | 정규군 | C2 — 도시 위병/타국 병력 |
| `MOCK_ELITE` | 정예 | C3 — 국가급 정예부대 |

### Mock 적 유닛 8종

| id | display | faction | is_boss | HP | ATK | AS | Range | MS | power |
|---|---|---|---|---|---|---|---|---|---|
| `mock_bandit_thug` | 산적 졸병 | BANDIT | × | 60 | 8 | 1.0 | 70 | 110 | ≈ 78 |
| `mock_bandit_veteran` | 산적 숙련공 | BANDIT | × | 90 | 12 | 1.1 | 75 | 110 | ≈ 120 |
| `mock_bandit_chief` | 산적 두목 | BANDIT | ○ | 180 | 18 | 1.0 | 80 | 100 | ≈ 188 |
| `mock_beast_wolf` | 늑대 | BEAST | × | 70 | 14 | 1.3 | 50 | 180 | ≈ 147 |
| `mock_beast_bear` | 곰 | BEAST | × | 200 | 22 | 0.7 | 60 | 100 | ≈ 187 |
| `mock_soldier_infantry` | 정규군 보병 | SOLDIER | × | 130 | 14 | 1.0 | 75 | 115 | ≈ 144 |
| `mock_soldier_archer` | 정규군 궁수 | SOLDIER | × | 90 | 18 | 1.2 | 300 | 95 | ≈ 175 |
| `mock_elite_captain` | 정예 대장 | ELITE | ○ | 280 | 28 | 0.9 | 80 | 110 | ≈ 280 |

### Mock 적 시너지 룰 5개 (각 패턴 1개씩)

| id | pattern | trigger | effect |
|---|---|---|---|
| `mock_bandit_horde` | GLOBAL_TRAIT | BANDIT 3마리 이상 | 전 산적 atk +30% |
| `mock_chief_aura` | BOSS_AURA | 두목 인접 + faction=BANDIT | 부하 atk_speed +50% |
| `mock_revenge` | DEATH_TRIGGER | 임의 적 사망 | 생존 적 atk +10% (중첩) |
| `mock_berserk` | HP_THRESHOLD | HP ≤ 40% | 자기 atk +50%, atk_speed +20% |
| `mock_overwhelm` | NUMBER_ADVANTAGE | 적이 플레이어보다 2명+ 많을 때 | 전 적 move_speed +25% |

### Mock 인카운터 템플릿 3개

**`mock_c1_bandit_patrol`** (C1 BATTLE, power ≈ 280)
- 슬롯 4개: 산적 졸병 ×3 (fixed), 산적 숙련공 1 (variation: thug/veteran)
- 룰: `mock_bandit_horde` (조건부 발동)

**`mock_c1_bear_camp`** (C1 ELITE, power ≈ 380)
- 슬롯 3개: 곰 1 (fixed, boss-flag 없음), 늑대 2 (fixed)
- 룰: 없음 (단순 큰 적 + 빠른 적 조합)

**`mock_c1_bandit_lair`** (C1 BOSS, power ≈ 488)
- 슬롯 5개: 산적 두목 1 (fixed, boss), 산적 숙련공 2 (fixed), 산적 졸병 2 (variation pool)
- 룰: `mock_bandit_horde` + `mock_chief_aura`

## 5. EncounterGenerator (구현 예정)

```
EncounterGenerator
  static func generate(template: EncounterTemplate, rng: RandomNumberGenerator)
    -> Array[Dictionary]  # [{unit: EnemyUnitData, row, col}, ...]

알고리즘:
  for slot in template.slots:
    if slot.optional and rng.randf() < slot.skip_chance:
      continue
    if slot.is_fixed():
      yield (slot.fixed_unit, slot.row, slot.col)
    else:
      pick = slot.variation_pool[rng.randi() % size]
      yield (pick, slot.row, slot.col)
```

생성된 결과는 `enemy_board: BoardState`에 채워 넣고, `EnemySynergyEngine.compute_pre_battle()`로 ComputedStats 생성 후 `CombatManager.start_battle()`에 전달.

## 6. 통합 흐름 (battle_screen 진입 시)

```
1. 노드 진입 → EncounterTemplate 선택 (챕터·노드 종류·power_target 매칭)
2. EncounterGenerator.generate() → enemy_board 채움
3. enemy_board 마주보기 UI에 표시 (사용자 결정사항)
4. 플레이어 편성·아이템 결정 (battle_screen 내부)
5. "전투 시작" 클릭
6. SynergyEngine.compute(player_board, player_rules) → player_stats
7. EnemySynergyEngine.compute_pre_battle(enemy_board, encounter.rules + global_enemy_rules) → enemy_stats
8. ItemEffect 적용 (전투 직전 - 별도 결정)
9. CombatManager.start_battle(player_stats, enemy_stats, combat_rules)
   - combat_rules에 DEATH_TRIGGER / HP_THRESHOLD / NUMBER_ADVANTAGE 룰 전달
10. _process 틱마다 combat_rules 평가 + 적용
11. battle_ended 시그널 → 결과 처리 (다음 라운드: 4번 차원)
```

## 7. TBD

| 항목 | 비고 |
|---|---|
| 실제 진영 카탈로그 | 사용자 전달 대기 |
| 챕터별 유닛 카탈로그 | 사용자 전달 대기 |
| 변동 정도 (±20%의 정확한 의미) | 슬롯 variation_pool로 충분한지, 스탯 ±20%도 별도 도입할지 |
| 보스 사망 시 BOSS_AURA 해제 | 현재는 pre-battle 단순화. 필요 시 combat-time으로 승격 |
| DEATH_TRIGGER stacking 상한 | 기본 5중첩 권장, 룰 단위로 설정 가능하게 할지 |
| HP_THRESHOLD 회복 시 거동 | 현재: 한 번 발동 시 유지. 회복-재발동 모드도 옵션화 가능 |
| EncounterGenerator 구현 | 위 알고리즘대로. 별도 task |
| EnemySynergyEngine 구현 | pre-battle 평가만 우선. combat-time 훅은 CombatManager 통합 시 |
| 챕터 전역 적 룰셋 | 챕터별로 항상 적용되는 추가 룰 (예: C3 적은 모두 +20% HP) 도입 여부 |
