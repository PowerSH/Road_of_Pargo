# 전투 흐름 통합

> 배틀 시스템 기획 라운드 1~6의 결정을 한 문서로 통합. `cargo-and-mortality.md` / `encounters.md` / `progression.md` / `synergy-axes.md`와 상호 참조.

## 0. 라운드별 결정 요약

| 라운드 | 차원 | 핵심 결정 |
|---|---|---|
| R1 | 편성 페이즈 UX | 5×3 적·플레이어 마주보기 한 화면, 보드는 영구 상태, 보관함은 사이드 패널, 시너지 실시간 미리보기, 명시적 "전투 시작" 버튼, 같은 유닛 두 번 배치 OK |
| R5 | 적 시스템 | 카탈로그+변동, 5개 적 시너지 패턴, EnemyUnitData 별도, power_score 자동 산정, 적군도 시너지 받음 |
| R4 | 전투 결과 | 패배=게임 오버, HP carry over (유닛 영구 자원), 무승부 캡 120초, 골드=power×0.25, 보스 골드 ×2 |
| R2 | 아이템 사용 | 전투 직전 일괄 적용, 같은 effect_type 1회 (max), 사용 후 카고 즉시 회수, 슬롯 3개 제한, 적 시너지 비표시 |
| R3 | 연출 | 별도 전투 화면, 1×/2× 배속, 일시정지 OK, HP바·데미지숫자=Settings, 페이드 사망, 시너지 아이콘 항상 표시, 도주 X, 결과 슬로우모션 |
| R6 | 데이터 모델 | OwnedUnit · BattleResult · ItemEffect · Settings 신규, 기존 클래스 마이그레이션 |

## 1. 화면 상태머신

```
                    ┌─────────────────────┐
                    │  PREP               │
                    │  편성 + 아이템 슬롯 + │  ← 진입 (map_screen에서)
                    │  보관함 + 적군 표시   │
                    └─────────────────────┘
                              │
                       "전투 시작" 클릭
                              │
                              ▼
                    ┌─────────────────────┐
                    │  ITEM_APPLY         │
                    │  아이템 효과 적용     │
                    │  + 카고 슬롯 해방    │
                    │  + 짧은 알림 (0.5s)  │
                    └─────────────────────┘
                              │ (자동)
                              ▼
                    ┌─────────────────────┐
                    │  BATTLE             │
                    │  CombatManager 실행  │
                    │  배속 / 일시정지     │
                    └─────────────────────┘
                              │
                    battle_ended 시그널
                              │
                ┌─────────────┼─────────────┐
                ▼             ▼             ▼
              승리          패배           무승부
                │             │             │
                ▼             ▼             ▼
        ┌──────────────┐   ┌──────┐  ┌─────────────┐
        │ RESULT_SLOWMO│   │ GAME │  │ DRAW_PENALTY│
        │   1.5초      │   │ OVER │  │ 양쪽 부상   │
        └──────────────┘   └──────┘  │ 보상 절반   │
                │                    └─────────────┘
                ▼                            │
        ┌──────────────┐                    │
        │RESULT_SCREEN │◄───────────────────┘
        │ 골드/부상/사망 │
        │  "계속" 버튼  │
        └──────────────┘
                │
                ▼
            map_screen 복귀
```

씬 구조: `battle_screen.tscn` 한 씬에 4개 페이즈 컨테이너(`PrepPhase`, `ItemApplyPhase`, `BattlePhase`, `ResultPhase`)를 자식 노드로 두고 visibility 토글. 씬 전환 오버헤드 X.

## 2. PREP 페이즈 — 편성

### 레이아웃

```
┌────────────────────────────────────────────────┐
│ Chapter X / Stage Y    HP: -    Gold: 124      │
├──────────────────────────────┬─────────────────┤
│ 적군 5×3 (위)                 │  [보관함]⇄[아이템]│
│ [E][E][ ][E][E]               │   토글 패널      │
│ [E][ ][E][E][ ]               │                  │
│ [ ][E][E][ ][E]               │  보관함 모드:     │
│                              │   유닛 리스트     │
│   ─── ⚔ 접전 진행 방향 ⚔ ─── │   상태 뱃지 ✓⚠☠ │
│                              │                  │
│ 플레이어 5×3 (아래)            │  아이템 모드:     │
│ [V][V][ ][V][V]               │   카고 아이템     │
│ [V][ ][V][ ][V]               │   슬롯에 할당     │
│ [ ][V][V][V][ ]               │                  │
├──────────────────────────────┤  아이템 슬롯 (3): │
│ 시너지 아이콘 [⚔3] [🏹2] [🛡1] │  [   ][   ][   ] │
├──────────────────────────────┴─────────────────┤
│                              [전투 시작]         │
└────────────────────────────────────────────────┘
```

### 상호작용 룰

- **빈 셀 클릭**: 보관함의 전투가능 유닛 선택 모드 활성, 선택 시 셀에 배치
- **채워진 셀 클릭**: 옵션 — 보관함으로 이동 / 스왑 / 정보
- **부상/사망 유닛**: 보관함에 ⚠/☠ 뱃지로 표시, 배치 불가
- **사망 유닛 버리기**: 보관함에서 불가. 쉼터 노드 한정.
- **같은 유닛 두 번**: 같은 종류의 `OwnedUnit` 인스턴스 2개를 영입했으면 두 칸에 배치 가능 (인스턴스 단위)
- **실시간 시너지**: 셀 변경 시 `SynergyEngine.compute()` 즉시 재호출 → 시너지 패널 아이콘 갱신
- **아이템 슬롯**: 카고에서 아이템 드래그 → 슬롯, 슬롯에서 다시 빼기 자유 (전투 시작 전까지)

### 데이터 흐름

```
RunState.owned_units : Array[OwnedUnit]
   ├─ 배치된 것 → BoardState._cells (영구 상태)
   └─ 미배치 / 부상 / 사망 → 보관함에 표시

GameState.board : BoardState  # 영구 — 전투 사이에 유지
```

## 3. ITEM_APPLY 페이즈 — 아이템 효과 적용

### 슬롯 룰

- 최대 **3개** (`MAX_ITEM_SLOTS = 3`)
- 같은 `ItemEffect.effect_type` 룰을 여러 슬롯에 넣으면 **각 스탯 % 중 max만 적용** (합산 X)
- 다른 `effect_type`은 독립적으로 누적

### 적용 흐름

```
"전투 시작" 클릭 시:
  1. 슬롯의 ItemEffect들을 모은다 → applied_effects: Array[ItemEffect]
  2. effect_type별로 그룹핑, 같은 종류 중 max 보너스만 선택
  3. 효과 적용:
       STAT_BOOST   : player ComputedStats에 % 합산
       FAKE_SYNERGY : SynergyEngine 재실행 시 가상 룰 1개 추가
       TEMP_UNIT    : enemy_board와 별개 player 보드에 임시 유닛 추가
       ENEMY_DEBUFF : enemy ComputedStats에 % 차감
       SHIELD       : CombatUnit.shield 필드에 amount 할당
  4. CargoState에서 해당 아이템 인스턴스 제거 → 공간 즉시 회수
  5. 짧은 시각 알림 (0.5초)
  6. BATTLE 페이즈로 자동 전환
```

## 4. BATTLE 페이즈 — 자동 전투

### 진입 시점 데이터

```
PlayerStats: Array[ComputedStats]  ← SynergyEngine + ItemEffect 누적
EnemyStats:  Array[ComputedStats]  ← EnemySynergyEngine.compute_pre_battle() + EnemyDebuff

CombatManager.start_battle(player_stats, enemy_stats, combat_time_rules)
```

### CombatManager 변경점

- `start_battle` 시그니처에 `combat_time_rules: Array[EnemySynergyRule]` 추가 (DEATH_TRIGGER / HP_THRESHOLD / NUMBER_ADVANTAGE)
- 매 틱 평가:
  - **DEATH_TRIGGER**: `CombatUnit.died` 시그널 연결 → 적 사망 시 생존 적에게 누적 boost (상한 5중첩 권장)
  - **HP_THRESHOLD**: `CombatUnit.damaged` 시그널 → 임계 도달 시 1회 자기 강화
  - **NUMBER_ADVANTAGE**: 매 틱 alive count 비교 → 동적 on/off
- `max_duration_sec = 120.0` (라운드 4 갱신)

### UI 컨트롤

- **배속 토글** 1× / 2× — `Engine.time_scale` 또는 `CombatManager` 자체 multiplier
- **일시정지** — `CombatManager._running = false`로 토글, 일시정지 중에는 정보 확인만 (입력 X)
- **도주 버튼 없음**

### 정보 표시 (Settings 기반)

```
Settings.hp_bar_mode:
  ALWAYS    : CombatUnit 위 HP 바 상시
  ON_HOVER  : 마우스 오버 시만

Settings.damage_number_mode:
  ALL  : 모든 데미지 숫자 띄움
  NONE : 표시 안 함

사망 연출: 페이드 아웃 (0.5초 알파 0→1)
시너지 아이콘: 각 CombatUnit 옆 활성 시너지 아이콘 (작은 뱃지)
```

## 5. RESULT 페이즈 — 결과 처리

### 분기

```
PlayerSide alive > 0 && EnemySide alive == 0 → PLAYER_WIN
PlayerSide alive == 0                        → PLAYER_LOSS (게임 오버)
120초 elapsed                                → DRAW
```

### PLAYER_WIN 처리

```
1. 마지막 적 사망 순간 슬로우모션 (Engine.time_scale = 0.3, 1.5초)
2. RESULT_SCREEN 표시:
   - 골드 보상: gold = round(total_enemy_power * 0.25)
                if encounter.is_chapter_boss: gold *= 2
   - 살아남은 유닛 → OwnedUnit.current_hp = CombatUnit.current_hp (carry over 저장)
   - HP 0 도달 유닛 → OwnedUnit.mark_injured()
   - 부상자 목록 표시 (이번 전투 부상자)
3. RunState.gold += gold_drop
4. "계속" 클릭 → map_screen 복귀
```

### PLAYER_LOSS 처리

```
1. 즉시 RESULT_SCREEN with outcome = GAME_OVER
2. 런 종료
3. "메인 메뉴로" 버튼만 노출
4. GameState.end_run(victory=false)
```

### DRAW 처리 (라운드 4 — 어쩔 수 없이 발생 시)

```
1. 양 진영 살아남은 유닛 전부 부상 처리
2. 골드 보상 절반: gold = round(total_enemy_power * 0.125)
3. RESULT_SCREEN 표시
4. "계속" 클릭 → map_screen 복귀
```

## 6. 데이터 모델

### 신규 클래스 (4종 — 이번 세션 작성)

```
OwnedUnit (Resource)
  source: UnitData
  status: Status (READY / INJURED / DEAD)
  current_hp: float = -1.0   # -1 == "use source.max_hp"
  injured_stages_left: int
  acquired_chapter, acquired_stage

BattleResult (RefCounted)
  outcome: Outcome (PLAYER_WIN / PLAYER_LOSS / DRAW)
  gold_reward: int
  newly_injured: Array[OwnedUnit]
  died_this_battle: Array[OwnedUnit]
  survivor_hp: Dictionary  # OwnedUnit → final HP
  duration_sec: float
  enemy_power_total: float

ItemEffect (Resource)
  effect_type: EffectType (5종)
  attack/hp/atk_speed/move_speed bonus_pct
  target_filter_tag, temp_unit, shield_amount

Settings (autoload Node)
  hp_bar_mode: HpBarMode (ALWAYS / ON_HOVER)
  damage_number_mode: DamageNumberMode (ALL / NONE)
  combat_speed: float = 1.0  # 1.0 or 2.0
```

### 신규 클래스 (나중 — battle_screen 실구현 시)

```
EncounterGenerator (RefCounted static)
EnemySynergyEngine (RefCounted static)
BattleScreenController (Node script, battle_screen.tscn 루트)
CargoItem (Resource) — cargo-and-mortality.md 참조
CargoState (RefCounted)
```

### 기존 클래스 변경 (나중 — battle_screen 실구현 시)

| 클래스 | 변경 |
|---|---|
| `RunState` | `owned_units: Array[UnitData]` → `Array[OwnedUnit]`, `cargo: CargoState` 추가 |
| `BoardState` | 셀 타입 `UnitData` → `OwnedUnit` |
| `CombatUnit` | `setup(owned: OwnedUnit, stats: ComputedStats, ...)` — current_hp 초기값을 OwnedUnit에서 가져옴 |
| `CombatManager` | 종료 시 OwnedUnit current_hp / status 기록, combat-time 룰 평가 hook |
| `SynergyEngine` | 변경 없음 |

## 7. 통합 시퀀스 (PREP → BATTLE → RESULT)

```
PREP:
  GameState.board (BoardState)                           # OwnedUnit refs
  GameState.run.owned_units                              # Array[OwnedUnit]
  EncounterGenerator.generate(template, rng)
    → enemy_board (BoardState)
  SynergyEngine.compute(player_board, active_rules)
    → preview_stats  (UI 미리보기)
  itemslots: Array[ItemEffect]                           # 사용자가 슬롯에 채움

"전투 시작" 클릭:

ITEM_APPLY:
  applied_effects = consolidate(itemslots)               # effect_type별 max 선택
  player_stats = apply_stat_boosts(preview_stats, applied_effects)
  enemy_stats = EnemySynergyEngine.compute_pre_battle(
      enemy_board, encounter.rules + global_enemy_rules)
  enemy_stats = apply_enemy_debuffs(enemy_stats, applied_effects)
  cargo.remove_used_items(applied_effects)
  combat_time_rules = filter_combat_time(encounter.rules + global_enemy_rules)

BATTLE:
  CombatManager.start_battle(player_stats, enemy_stats, combat_time_rules)
  매 틱:
    for unit in player_units: unit.tick(delta, enemy_units)
    for unit in enemy_units: unit.tick(delta, player_units)
    evaluate_combat_time_rules(delta)   # DEATH_TRIGGER / HP_THRESHOLD / NUMBER_ADVANTAGE
  종료 → battle_ended(BattleResult)

RESULT_SLOWMO (PLAYER_WIN 한정):
  Engine.time_scale = 0.3
  await 1.5s
  Engine.time_scale = 1.0

RESULT_SCREEN:
  display(BattleResult)
  for u in survivors: u.current_hp = combat_unit.current_hp
  for u in HP-zero player units: u.mark_injured()
  RunState.gold += BattleResult.gold_reward
  "계속" 클릭 → return_to_map()
```

## 8. Settings (autoload)

`scripts/globals/settings.gd` — `Settings` autoload로 등록.

```
HpBarMode: ALWAYS / ON_HOVER
DamageNumberMode: ALL / NONE
combat_speed: 1.0 / 2.0
```

향후 확장: 사운드, 자동 회복 알림, fog 표시 옵션 등.

저장은 추후 — `user://settings.cfg`에 `ResourceSaver.save` 또는 `ConfigFile`.

## 9. TBD

| 항목 | 비고 |
|---|---|
| 같은 effect_type 룰의 "max" 비교 기준 | 첫 번째 스탯(attack_bonus_pct)? 합산? — 일단 attack_bonus_pct 기준 |
| FAKE_SYNERGY 가상 룰의 구체적 표현 | 임시 `SynergyRule` 생성 후 한 번만 컴퓨트에 끼움 |
| TEMP_UNIT의 OwnedUnit 처리 | UnitData만 받고 OwnedUnit은 즉석 생성, 전투 종료 후 폐기 |
| BOSS_AURA의 보스 사망 시 거동 | 일단 pre-battle 단순화 — 전투 내내 유지 |
| DEATH_TRIGGER stacking 상한 | 5중첩 권장, 룰 단위로 조정 가능하게 |
| 일시정지 중 정보 확인 UI | 슬로우모션 + UI 강조 정도 |
| Settings 저장/불러오기 | 후순위 |
| 챕터 전역 적 룰셋 | 챕터별 항상 적용 룰 도입 여부 |
