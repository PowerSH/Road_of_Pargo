# Road of Pargo

2D auto-chess + Slay-the-Spire-style 로그라이트. Godot 4.3 + GDScript.

> **새 세션/다른 PC에서 시작한다면**: 먼저 [`docs/NEXT-SESSION.md`](docs/NEXT-SESSION.md)부터 읽기.

## 컨셉

플레이어는 상단(商團)을 운영하는 거상이 되는 게 목표. 한 런은 **마을→마을(C1) → 도시→도시(C2) → 국가→국가(C3)** 3챕터 여정.

- **편성 단계**: 5×3 그리드 위에 유닛을 배치. 그리드 위치는 **시너지 계산용**이다(8방향 인접). 예: 양 옆의 유닛이 "보병" 타입이면 해당 유닛 공격력 +10%.
- **전투 단계**: 그리드와 무관하게, 양 진영이 자유롭게 이동·공격하는 실시간 틱 오토배틀러. AFK Arena/Battle Cats 계열의 자유 이동/타겟팅 방식.
- **적재(Cargo) 시스템**: Backpack Hero식 격자 위 아이템 배치. 도시에서 판매하면 골드, 전투 직전 소비하면 부스트 효과. 사용 vs 보존의 긴장.
- **유닛 사망**: 전투에서 HP 0 → 부상. 미치료 누적 → 사망. 시체는 적재 공간 1×2 차지, 도시 신전에서 부활 가능.
- **진행**: 챕터 내 스테이지 = 맵 노드(전투/여관/미니보스/특수). 노드 종류는 도착 전까지 fog of war.

## 디자인 문서

- [`docs/design/synergy-axes.md`](docs/design/synergy-axes.md) — 시너지 3축 + 국가별 친화 매트릭스
- [`docs/design/progression.md`](docs/design/progression.md) — 챕터/스테이지/이벤트 + 난이도 곡선 + Fog of War
- [`docs/design/cargo-and-mortality.md`](docs/design/cargo-and-mortality.md) — 적재 격자 + 유닛 3상태 시스템

## 코드 구조

```
scripts/
├── data/                  # Resource 타입 — 디스크에 .tres로 저장 가능
│   ├── unit_data.gd       # 유닛 기본 스탯 + 시너지 타입 태그
│   ├── synergy_rule.gd    # "self가 X타입이고 인접 N개가 Y타입이면 +Z%"
│   └── computed_stats.gd  # 시너지 적용 후 최종 스탯 (전투에 들어가는 값)
├── board/
│   ├── board_state.gd     # 5×3 그리드 모델 (RefCounted, UI 없음)
│   └── synergy_engine.gd  # compute(board, rules) → {Vector2i: ComputedStats}
├── combat/
│   ├── combat_unit.gd     # Node2D, 상태머신(SEARCH/MOVE/ATTACK/DEAD)
│   └── combat_manager.gd  # _process 틱, 양 진영 스폰, 결과 시그널
├── run/
│   ├── run_state.gd       # 한 런의 체력/골드/덱/현재 노드
│   ├── map_node.gd        # 맵 노드 Resource
│   └── map_generator.gd   # depth × lane 행렬 + 보스로 수렴
└── globals/
    └── game_state.gd      # Autoload: 현재 run + board, 헬퍼 메서드
```

## 시너지 축 (2회차 합의)

3축 구조 + 국가별 친화 매트릭스. 자세한 정의·예시·확장 노트는 `docs/design/synergy-axes.md`.

| 축 | 값 |
|---|---|
| 소속 국가 | 벤 / 크렘 / 아르덴 / 넬름 |
| 직업 | 보병 / 창병 / 궁병 / 석궁병 |
| 유형 | 군인 / 모험가 / 용병 |

친화 매트릭스 (국가가 자기 친화 태그를 가진 인접 유닛이 있을 때 시너지 발동):

| 국가 | 친화 |
|---|---|
| 벤 | 보병, 창병, 군인 |
| 크렘 | 보병, 궁병, 모험가 |
| 아르덴 | 궁병, 석궁병, 용병 |
| 넬름 | 창병, 석궁병, 모험가 |

상수는 `scripts/data/synergy_types.gd`에 정의. 시너지 룰 12개(`SynergyRule` `.tres`)의 보너스 수치는 유닛 카탈로그 확정 후 채움.

## 설계 결정 (1회차 합의)

- **시너지 인접 판정**: 8방향. `BoardState.get_adjacent(row, col)`.
- **시너지 축**: 1축으로 시작. `UnitData.types: Array[StringName]`이라 다축(예: 종족+직업)으로 확장 가능.
- **보너스 합산**: 같은 스탯의 보너스는 **합산** 후 곱(`final = base * (1 + sum_of_pct)`). 균형 잡기 직관적.
- **데이터 vs 로직 분리**: 유닛/시너지/맵노드는 모두 `Resource`라 에디터에서 `.tres`로 만들고 `@export`로 편집. 로직 클래스(SynergyEngine, MapGenerator)는 정적 함수만 노출.
- **UI 없음**: 사용자가 인터페이스를 만들 예정이라 씬 파일/스프라이트는 비워뒀음. 모든 시스템은 데이터 입력 → 데이터 출력으로 동작하므로 UI는 위에 얹기만 하면 됨.

## 어떻게 켜는지

1. Godot 4.3+로 이 폴더 열기. `project.godot`가 자동 인식됨.
2. 첫 실행 시 `run/main_scene`이 비어 있다는 경고가 뜸 — 메인 씬 만들고 지정.
3. `GameState`는 autoload 등록되어 있어서 어디서든 `GameState.start_new_run()`으로 런 시작.

## 다음 단계 후보

- 메인 씬 + 편성/전투/맵 UI
- `resources/units/*.tres` 샘플 유닛 정의
- `resources/synergies/*.tres` 샘플 시너지 정의
- 적 인카운터 데이터 + 난이도 곡선
- 상점/이벤트/렐릭 시스템
- 저장/불러오기 (RunState를 Resource로 전환 후 `ResourceSaver.save`)
