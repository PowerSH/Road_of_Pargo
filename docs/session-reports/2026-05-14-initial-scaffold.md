# 세션 보고서: 초기 코드 스캐폴드

- **날짜**: 2026-05-14
- **에이전트**: Claude Code (Opus 4.7, 1M context)
- **작업자**: PowerSH (psh95king@gmail.com)
- **목표**: Godot 4 + GDScript로 게임의 코어 시스템 코드를 미리 깔기. UI는 사용자가 직접 작업 예정.

---

## 1. 게임 컨셉 (합의된 내용)

- **장르**: 2D 오토체스 + Slay-the-Spire 스타일 로그라이트.
- **편성 단계**: 5×3 그리드에 유닛 배치. 그리드 위치는 **시너지 계산 전용**.
  - 예: 어떤 유닛의 양 옆에 "A" 타입 유닛이 있으면 그 유닛 공격력 +10%.
- **전투 단계**: 그리드와 무관. 양 진영이 마주보고 자유롭게 이동·타겟팅(AFK Arena/Battle Cats 계열). TFT처럼 그리드 위에서 싸우는 게 아님.
- **진행**: Slay the Spire 노드 맵(전투/엘리트/상점/휴식/이벤트/보물/보스). 한 런이 끝나면 다음 런.

## 2. 1회차에서 합의한 설계 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 엔진 | Godot 4.3 / 4.4 stable | 최신 GDScript 2.0, 2D 렌더 개선 |
| 전투 공간 | 양 진영 자유 이동/공격 (그리드 X) | 그리드는 시너지용이라는 사용자 명시 정정 |
| 시너지 인접 판정 | 8방향(상하좌우+대각선) | 조합/전략성 ↑ |
| 시너지 축 | 1축으로 시작, 다축 확장 여지 유지 | MVP 단순화, `Array[StringName]` 구조로 확장성 확보 |
| 보너스 합산 | 같은 스탯 % 보너스는 합산 후 곱 | `final = base * (1 + sum_of_pct)` — 균형 잡기 직관적 |
| UI 작업 | 사용자가 직접 (씬 파일 안 만듦) | 사용자 명시 요청 |

## 3. 파일 인벤토리

### 프로젝트 루트
- `project.godot` — Godot 4.3 프로젝트 설정. `GameState` autoload 등록. `run/main_scene`은 비워둠(사용자가 메인 씬 만들면 지정).
- `.gitignore` — Godot 4 표준 + macOS/IDE 무시 규칙.
- `icon.svg` — 5×3 그리드 모티프의 임시 아이콘.
- `README.md` — 프로젝트 개요, 코드 구조, 설계 결정, 실행 방법.

### `scripts/data/` — 데이터 리소스 (Resource 상속)
- `unit_data.gd` (`class_name UnitData`)
  - 유닛 베이스 스탯(`max_hp`, `attack`, `attack_speed`, `attack_range`, `move_speed`).
  - `types: Array[StringName]` — 시너지 태그. 다축 확장에 대비해 Array.
  - `cost`, `tier`, `icon`, `sprite`.
- `synergy_rule.gd` (`class_name SynergyRule`)
  - 데이터 드리븐 시너지 룰. `applies_to_type`, `requires_adjacent_type`, `min_adjacent`.
  - 효과: `attack_bonus_pct`, `hp_bonus_pct`, `attack_speed_bonus_pct`, `move_speed_bonus_pct`, `range_bonus_pct`.
  - 헬퍼: `matches_self(unit)`, `count_qualifying(neighbors)`.
- `computed_stats.gd` (`class_name ComputedStats`)
  - 시너지 적용 후 최종 스탯. `applied_synergies: Array[StringName]`로 어떤 시너지가 기여했는지 추적(UI 툴팁용).
  - 정적 헬퍼: `from_base(unit) -> ComputedStats`.

### `scripts/board/` — 편성 보드 + 시너지 엔진
- `board_state.gd` (`class_name BoardState extends RefCounted`)
  - 5×3 그리드 모델(`ROWS=3`, `COLS=5`). 순수 데이터, 노드 없음.
  - API: `place_unit`, `remove_unit`, `get_unit`, `swap`, `get_adjacent`(8방향), `iter_placed`, `count_placed`.
- `synergy_engine.gd` (`class_name SynergyEngine`)
  - 정적 `compute(board, rules) -> Dictionary[Vector2i, ComputedStats]`.
  - 룰을 받아서 각 슬롯의 유닛에 적용. 같은 스탯 보너스는 합산 후 1+sum 곱.

### `scripts/combat/` — 자동 전투 시뮬레이션
- `combat_unit.gd` (`class_name CombatUnit extends Node2D`)
  - 상태머신: SEARCH → MOVE → ATTACK → DEAD.
  - 매 틱 `tick(delta, enemies)`: 가장 가까운 적 추적, 사거리 내면 공격 쿨다운에 맞춰 데미지.
  - 시그널: `died(unit)`, `damaged(unit, amount)`.
- `combat_manager.gd` (`class_name CombatManager extends Node2D`)
  - `start_battle(player_stats, enemy_stats)`로 시작.
  - 양 진영을 아레나 좌/우 끝에 스폰(약간의 X 지터). 시그모이드 같은 라인업 X.
  - `_process(delta)`에서 양 진영 유닛 `tick` → 한 쪽 전멸 시 `battle_ended(result)` 시그널.
  - 결과: `Result.PLAYER_WIN | ENEMY_WIN | DRAW`. `max_duration_sec`(기본 60초) 초과 시 DRAW.

### `scripts/run/` — 로그라이트 진행
- `map_node.gd` (`class_name MapNode extends Resource`)
  - 노드 종류: `BATTLE | ELITE | SHOP | REST | EVENT | TREASURE | BOSS`.
  - `next_indices: Array[int]` — 전진 방향 에지(DAG).
- `run_state.gd` (`class_name RunState extends RefCounted`)
  - 한 런의 체력/골드/덱(`owned_units`)/현재 시너지 룰셋(`active_rules`)/노드 맵/현재 위치.
  - API: `add_unit`, `spend_gold`, `take_damage`, `heal`, `reachable_from_current`, `enter_node`.
- `map_generator.gd` (`class_name MapGenerator`)
  - 정적 `generate(rng, depth=12, lanes=4)`: depth × lanes 그리드 + 최종 보스 노드로 수렴.
  - 노드 종류는 깊이 기반 가중치(`_pick_kind`)로 분배.

### `scripts/globals/` — 오토로드
- `game_state.gd` — autoload `GameState`.
  - 현재 `run: RunState`, `board: BoardState` 보관.
  - 시그널: `run_started`, `run_ended`, `node_entered`, `board_changed`.
  - 헬퍼: `start_new_run`, `enter_node`, `compute_current_synergies`, `build_player_stats`.

## 4. 데이터 흐름

```
[에디터에서 UnitData.tres 작성]
       ↓
[UI: 보드에 드래그앤드롭] → BoardState.place_unit(row, col, unit)
       ↓
SynergyEngine.compute(board, run.active_rules) → {Vector2i: ComputedStats}
       ↓
[UI: "전투 시작" 버튼] → GameState.build_player_stats() → Array[ComputedStats]
       ↓
CombatManager.start_battle(player_stats, enemy_stats)
       ↓
_process(delta) 매 프레임 양 진영 tick
       ↓
battle_ended(result) 시그널 → UI가 결과 화면 표시 + RunState 갱신
```

## 5. 의도적으로 비워둔 것

- **UI/씬 파일**: 사용자가 직접 작업. `res://scenes/` 디렉터리는 만들지 않았음.
- **샘플 `.tres` 데이터**: Godot 에디터에서 만드는 게 편함. 코드로 미리 만들면 UID 충돌 등 잡일 발생 가능.
- **저장/불러오기**: `RunState`를 `RefCounted`로 시작 → 데이터 모델 안정화 후 `Resource`로 전환 + `ResourceSaver.save()` 한 줄로 끝.
- **적 AI 다양성, 스킬 시스템, 렐릭/상점/이벤트 로직**: 시스템 골격 검증 이후 결정.
- **단위 테스트**: GUT 등 별도 프레임워크 도입 미정.

## 6. 확장 포인트

- **다축 시너지 (종족 + 직업 같은)**: `UnitData.types`가 이미 `Array[StringName]`. `SynergyRule` 인스턴스를 축별로 만들면 즉시 동작.
- **글로벌 시너지 (TFT 트레이트 — 보드에 N개 이상 있으면 모두 적용)**: 현재 `SynergyEngine`은 인접 기반만 처리. 글로벌 시너지를 추가하려면 `SynergyEngine.compute`에 두 번째 패스 추가하거나, `SynergyRule`에 `scope: ENUM { ADJACENT, GLOBAL }` 필드 추가.
- **비퍼센트 효과 (스플래시, 보호막, 상태이상)**: `SynergyRule`에 `extra_effect: GDScript` 필드를 추가하고 `apply_extra(target, neighbors)`을 호출하는 패턴.
- **전투 결정성**: 현재 `_process(delta)` 기반이라 프레임 의존. 결정적 리플레이가 필요하면 고정 틱(예: 30 Hz)으로 전환.

## 7. 다음 세션 후보 작업

- (a) 샘플 `UnitData`/`SynergyRule` `.tres` 세트 (밸런싱 한 패스 + 디버깅용).
- (b) `CombatManager` 단위 테스트 (헤드리스: 두 진영의 결정적 시뮬레이션 가능).
- (c) 적 인카운터 데이터 모델(`EncounterData`: 라운드별 적 구성).
- (d) Slay-the-Spire 스타일 맵 UI 위에서 동작하는 `enter_node` 통합.
- (e) 상점/렐릭/이벤트 시스템.

## 8. 알려진 잠재 이슈 / 메모

- `project.godot`의 `run/main_scene`이 빈 문자열 → 첫 실행 시 경고. 메인 씬 만들면 지정.
- `CombatUnit`은 현재 충돌 처리 없음(유닛끼리 겹칠 수 있음). 시각적 분리는 UI 단계에서 결정(physics body로 갈지, 단순 푸시 벡터로 갈지).
- 시너지 보너스 합산이 곱이 아닌 합산이라 강한 시너지 여러 개가 겹치면 다소 약해 보일 수 있음 — 밸런싱 시 재고 가능.

---

**커밋 단위**: 이 보고서와 스캐폴드는 한 커밋으로 묶음. 다음 세션에서 같은 보고서 형식을 `docs/session-reports/YYYY-MM-DD-*.md`로 누적.
