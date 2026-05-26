# 다음 세션 핸드오프

> 이 파일은 **세션이 끝날 때마다 갱신**한다. 다른 PC/새 Claude 세션이 컨텍스트를 빠르게 잡는 진입점.

## 0. 새 세션 시작 시 읽을 순서

1. **이 파일** (`docs/NEXT-SESSION.md`) — 현재 위치, 다음 할 일
2. **README.md** — 게임 컨셉, 코드 구조, 합의된 설계 결정
3. **docs/design/** — 설계 문서 (현 시점 5개)
   - `synergy-axes.md` — 시너지 축 3개 + 친화 매트릭스 + 발동 해석
   - `progression.md` — 챕터/스테이지/이벤트 구조 + 난이도 곡선 + Fog of War
   - `cargo-and-mortality.md` — 적재 그리드 + 유닛 사망 + HP carry over
   - `encounters.md` — 적 시스템 (EnemyUnitData, 5개 시너지 패턴, EncounterTemplate, mock 데이터)
   - `battle-flow.md` — 전투 흐름 통합 (라운드 1-6 종합, 상태머신, UI 룰, 데이터 인터페이스)
4. **docs/session-reports/** — 토픽 단위 마일스톤 로그
   - `2026-05-14-initial-scaffold.md` — 1회차: 코어 시스템 코드 골격
   - `2026-05-14-synergy-axes.md` — 2회차: 시너지 축 정의
   - `2026-05-15-progression-and-cargo.md` — 3회차: 진행 구조 + 적재/사망 디자인
   - `2026-05-25-godot-4-6-and-ui-skeleton.md` — 4회차: Godot 4.6 마이그레이션 + UI 씬 골격 11개
   - (5회차는 daily-reports/2026-05-26.md로 누적 — 배틀 시스템 기획 6 라운드 + 적 시스템 코드 + battle-flow 통합)
5. **docs/daily-reports/** — 날짜 단위 타임라인 로그 (그날 무엇을 했나)
   - `YYYY-MM-DD.md` 형식. 운영 규칙은 §6 참조.

코드 위치:
- 데이터 리소스: `scripts/data/`
- 보드/시너지 엔진: `scripts/board/`
- 자동 전투: `scripts/combat/`
- 로그라이트 진행: `scripts/run/`
- 오토로드: `scripts/globals/game_state.gd`, `scripts/globals/settings.gd`
- **UI 스크립트**: `scripts/ui/` (씬당 .gd 1개)
- **씬 파일**: `scenes/` (총 11개 placeholder)

## 1. 현재 상태 (2026-05-25 기준)

### ✅ 완료
- Godot 4.6 프로젝트 셋업 (`project.godot`, `.gitignore`, `icon.svg`)
- 데이터 모델: `UnitData`, `SynergyRule`, `ComputedStats`
- 보드: 5×3 `BoardState`, 8방향 인접
- 시너지 엔진: `SynergyEngine.compute(board, rules)` — 인접 기반 보너스 적용
- 자동 전투: `CombatUnit` (FSM) + `CombatManager` (틱 시뮬레이션)
- 로그라이트 진행: `RunState` + `MapNode` + `MapGenerator` (StS 스타일 DAG)
- 오토로드 `GameState`
- 시너지 축 3개 + 친화 매트릭스 코드화 (`scripts/data/synergy_types.gd`)
- `UnitData.validate_axes()` 등 축별 헬퍼
- **디자인 문서 5종** (`docs/design/`)
- **UI 씬 골격 11개** (`scenes/*.tscn`) + 외부 스크립트 11개 (`scripts/ui/*.gd`)
- **메인 메뉴** + **맵 화면 완전 구현** — StS DAG 격자 배치, 엣지 라인, kind별 라벨, Fog of War, HP/Gold 정보, 노드 종류별 라우팅
- Fog of War 데이터: `RunState.revealed_nodes` + `is_revealed()` + `reveal_initial()` (boss는 항상 공개)
- Godot 4.6 호환성 fix — `get_class` 충돌, 타입 추론 명시, 빌트인 메서드 충돌 회피
- **적 시스템 데이터 모델** (`EnemyUnitData`, `EnemySynergyRule`, `EncounterSlot`, `EncounterTemplate`)
- **배틀 시스템 데이터 모델** (`OwnedUnit`, `BattleResult`, `ItemEffect`, `Settings` autoload)
- **일일 보고서 워크플로** (`docs/daily-reports/`) + 운영 규칙 §6

### ⏸ 대기 중

**A. 유닛 카탈로그 (사용자가 엑셀로 작성 중)**

엑셀(.xlsx) / CSV / 마크다운 테이블 / 스크린샷 모두 처리 가능.

기대 스키마:
| id | display_name | nation | class | type | max_hp | attack | atk_speed | atk_range | move_speed | cost | tier | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|

- `nation`: 벤 / 크렘 / 아르덴 / 넬름
- `class`: 보병 / 창병 / 궁병 / 석궁병
- `type`: 군인 / 모험가 / 용병
- `id`는 비어 있으면 컨벤션(`{nation}_{class}_{NN}` 예: `ven_infantry_01`)으로 자동 부여
- 한국어 입력 OK — 받을 때 `SynergyTypes` 상수로 매핑

**B. 적재/사망 시스템 코드 구현 (디자인 확정됨, 구현 대기)**

데이터 모델 1차 작성 완료 (`OwnedUnit`, `BattleResult`, `ItemEffect`, `Settings`).
남은 구현 우선순위:
1. `RunState.owned_units` 타입 마이그레이션 (`Array[UnitData]` → `Array[OwnedUnit]`)
2. `BoardState` 셀 타입을 `OwnedUnit` 참조로 마이그레이션
3. `CombatUnit.setup()`이 `OwnedUnit.get_starting_hp()`로 시작 HP 결정
4. 전투 종료 시 OwnedUnit current_hp/status 기록 (CombatManager 변경)
5. `CargoState` + `CargoItem` 기본 모델 (회전 X 단순판)
6. 도시 액션 (부활/치료/구매/그리드 확장)
7. `EncounterGenerator` + `EnemySynergyEngine` (pre-battle 평가)

**C. 씬 내부 실제 구현 (UI 골격 완성됨, 내부 채우기)**

우선순위:
1. **`battle_screen`** — 4 페이즈 상태머신(PREP/ITEM_APPLY/BATTLE/RESULT). 설계는 `battle-flow.md` 완료. 데이터 인터페이스 준비됨 (`OwnedUnit`, `BattleResult`, `ItemEffect`, `Settings`).
2. **챕터 진행 로직** — `RunState.chapter`, 보스 승리 → 맵 재생성. 작업량 작고 게임 흐름 완결.
3. **쉼터(여관) 액션** — HP 풀 회복 + 부상 → 전투가능. `rest_screen` 내부.
4. `hub_screen` 내부 — 용병/상점/NPC sub-popup. 거래 화면(판매/구매/부활/그리드 확장).
5. `shop_screen` / `event_screen` / `treasure_screen` 시스템 (콘텐츠는 후순위).
6. `elite_screen` 차별화 (현재는 placeholder 버튼만).

**C-1 (battle_screen)이 임팩트 가장 큼.** 백엔드 코드(`SynergyEngine`, `CombatManager`)는 이미 준비됨. 데이터 모델도 5/26 완료.

### 🚫 의도적으로 비워둔 것
- UI 시각 디자인 (현재 placeholder = CenterContainer + VBox + 기본 Button)
- 스프라이트, 배경 아트, 폰트, 사운드
- 시스템 코드는 데이터 in / 데이터 out으로 동작 — 시각화는 위에 얹기만 하면 됨

> ℹ️ 4회차 세션(2026-05-25)에서 UI 작업 분담이 갱신됨: **Claude가 placeholder .tscn 작성 + .gd 구현**, 사용자가 시각 디자인 / Inspector 미세 조정.

### ⚠️ Godot 4.6 함정 (다음 세션이 같은 실수 안 하도록)

자세한 건 `docs/session-reports/2026-05-25-godot-4-6-and-ui-skeleton.md` §6.

- **인라인 스크립트 함정**: 에디터에서 시그널 connect 시 "Make Function" 체크박스 **반드시 끄기**. 외부 .gd의 기존 메서드명을 직접 타이핑. 안 그러면 .tscn 안에 빈 stub 가진 인라인 GDScript가 자동 생성되어 외부 스크립트의 진짜 구현을 가림.
- **외부 .tscn 편집 금지** (Godot이 열고 있는 동안): Godot의 인메모리 상태가 다음 저장 때 외부 변경을 덮어씀. 새 .tscn 파일 작성은 안전. 기존 씬 구조 변경은 Godot GUI 안에서.
- **GDScript 4.6 타입 추론**: `for x in [literal]:` 의 x는 Variant로 추론됨. 산술하면 결과 타입 결정 불가 에러. → `for x: int in [...]:` 로 명시.
- **빌트인 메서드 이름 회피**: `get_class`(→ String), `_get_tooltip`(Vector2), `_get_drag_data`, `_can_drop_data`, `_drop_data`, `_gui_input`, `_has_point`, `_make_custom_tooltip`, `_get_minimum_size`, `_notification`, `_to_string`. 헬퍼는 안 겹치는 이름으로.
- **인스펙터 표시용 가짜 속성**: `theme_override_font_sizes["font_size"] = 18` 같은 dict 접근 안 됨. → `add_theme_font_size_override(&"font_size", 18)` 메서드 사용.

## 2. 핵심 합의 사항 (다시 묻지 말 것)

| 항목 | 결정 |
|---|---|
| 엔진 | Godot 4.6 + GDScript |
| 그리드 | 5×3, **시너지 계산 전용**. 전투에는 안 쓰임 |
| 전투 | 그리드 밖, 양 진영 자유 이동/타겟팅 (AFK Arena 계열) |
| 인접 판정 | 8방향 |
| 시너지 축 | 3축: 국가 / 직업 / 유형. 각 유닛은 축당 정확히 1개 태그 |
| 시너지 발동 | "국가 유닛 입장에서 인접에 친화 태그 있으면 발동" |
| 보너스 합산 | 같은 스탯 % 보너스는 합산 후 곱: `base * (1 + sum_of_pct)` |
| 챕터 구조 | C1 마을 / C2 도시 / C3 국가 — 3챕터 × 8/10/12 스테이지 |
| 이벤트 종류 | 전투 / 여관 / 미니보스 / 특수 이벤트 (+ 챕터 보스) |
| Fog of War | 도착 시 노드 종류 공개 (기본값, 재논의 가능). boss는 항상 공개 |
| 난이도 배수 | C1=1.0 / C2=1.6 / C3=2.8, 챕터 내 +0~50% 추가 |
| 거래 모델 | 챕터 간 도시 화면에서 일괄 처리 (코어는 호위 전투) |
| 적재 시스템 | Backpack Hero식 격자, 회전 OK, 자동정렬 OK, 시너지 격자와 별개 |
| 아이템 사용 | **전투 시작 전 미리 사용**만 (전투 중 발동 X) |
| 유닛 상태 | 전투가능 / 부상 / 사망 — 회복 후 영구 페널티 없음 |
| 시체 적재 | 1×2 셀 점유, 도시 부활 가능, 버리기 = **쉼터 한정** |
| 유닛 HP | **Carry Over** — 전투 사이 영구 자원. 쉼터(여관)에서 풀 회복 |
| 부상 룰 | 전투 중 HP 0 → INJURED, 미치료 N 스테이지 → DEAD (C1=4/C2=3/C3=2) |
| 패배 시 | **게임 오버** — 런 즉시 종료 |
| 무승부 | 캡 120초, 발생 시 양쪽 부상 + 보상 절반 |
| 골드 보상 | `round(total_enemy_power × 0.25)`, 보스 ×2 |
| 편성 화면 | 5×3 적·플레이어 마주보기 (한 화면), 보드는 영구 상태, 보관함 사이드 패널 |
| 보관함 ⇄ 아이템 | 사이드 패널 토글 (한 공간 공유). 상태는 아이콘 뱃지 ✓⚠☠ |
| 같은 유닛 두 번 | 같은 종류 OwnedUnit 두 인스턴스 영입 시 두 칸 배치 가능 |
| 아이템 사용 | 전투 시작 직전 일괄 적용, 슬롯 3개, 같은 effect_type은 max만, 적 시너지 비표시 |
| 적 시스템 | EnemyUnitData 별도, 5개 적 시너지 패턴, EncounterTemplate 카탈로그 + variation |
| 전투 페이즈 | 별도 화면 페이즈, 1×/2× 배속, 일시정지 OK, 도주 X, 결과 슬로우모션 |
| HP바·데미지숫자 | Settings autoload 옵션 (ALWAYS/ON_HOVER, ALL/NONE) |
| 씬 흐름 | Menu → Story → Hub → Map → [Battle/Elite/Rest/Shop/Event/Treasure/Boss] → Map. 보스 승리 → Hub |
| 노드 종류별 씬 | 7종 모두 각각 별도 .tscn (BATTLE/ELITE/REST/SHOP/EVENT/TREASURE/BOSS) |
| 거점(Hub) 역할 | 챕터 시작 + 챕터 사이 통과 도시 (둘 다 같은 씬) |
| 5×3 편성 그리드 | Battle/Elite/Boss 씬 내부 단계 (별도 씬 X) |
| 챕터 진행 (현재) | 보스 승리 → Hub만 처리. 챕터 카운터/맵 재생성은 후순위 |
| 스토리 화면 | 게임 시작 시 인트로 1회만. 챕터 사이 컷씬 후순위 |
| UI 작업 분담 | Claude가 placeholder .tscn 작성 + .gd 구현, 사용자가 시각 디자인 다듬음 (4회차 갱신) |
| 일일 보고서 | `docs/daily-reports/YYYY-MM-DD.md`, 6섹션 고정, 사용자 트리거 시 작성, 그날 작업 커밋과 동시 커밋 (§6 참조) |
| 커밋 정책 | 사용자 명시 요청 시만 (예외: 명시적 핸드오프 워크플로, 일일 보고서) |

## 3. 다른 PC에서 시작하는 법

```bash
# 1. 클론
git clone https://github.com/PowerSH/Road_of_Pargo.git
cd Road_of_Pargo

# 2. git identity (로컬 한정)
git config user.name 'Harry'
git config user.email '39876295+PowerSH@users.noreply.github.com'

# 3. Godot 4.6+로 폴더 열기 (project.godot 자동 인식)
```

기존 로컬에 빈 Godot 프로젝트가 이미 있는 PC라면 clone 대신 wipe-and-replace 패턴 사용 (4회차 보고서 §1.1 참조).

## 4. 새 세션에 빠르게 컨텍스트 주는 한 줄 프롬프트

> "Road of Pargo 게임 프로젝트. 다른 PC에서 작업하던 거 이어서 한다. 먼저 `docs/NEXT-SESSION.md` 읽고 현재 상태 정리해서 알려줘."

또는 더 짧게:

> "docs/NEXT-SESSION.md 읽고 상태 보고."

## 5. 세션 끝낼 때 체크리스트 (다음 사람을 위해)

- [ ] 이 파일(`docs/NEXT-SESSION.md`)의 "현재 상태" / "대기 중" 섹션 갱신
- [ ] 굵직한 마일스톤이면 `docs/session-reports/YYYY-MM-DD-<topic>.md`로 추가
- [ ] 사용자가 일일 보고서 트리거를 줬으면 `docs/daily-reports/YYYY-MM-DD.md` 작성·갱신 (§6)
- [ ] 새 합의 사항은 "핵심 합의 사항" 표에 반영
- [ ] 새로 발견된 Godot 함정은 §1.⚠️ 섹션에 추가
- [ ] 커밋 + 푸시 (사용자 명시 요청 시)

## 6. 일일 보고서 운영 규칙

**위치**: `docs/daily-reports/YYYY-MM-DD.md` (파일명에 토픽 suffix 없음)

**트리거**: 사용자가 다음 류의 문구를 줬을 때 작성·갱신
- "오늘 작업 정리해"
- "데일리 보고서 써줘"
- "일일 보고서 갱신"
- "정리"

**구조 (6섹션 고정)**:
1. 오늘 한 일 — 시간순 액션 로그
2. 직접 변경한 파일 — 표 형식
3. 결정 / 합의 사항 — 그날 대화에서 정해진 것
4. 현재 환경 메모 — 어떤 PC/엔진/제약에서 작업했는지
5. 다음 작업 후보 — 환경 제약 안에서 진행 가능한 것
6. 미해결 / 메모 — 다음 세션 인계 사항

**커밋 정책**: 그날 코드/문서 변경분과 **동시 커밋** (보고서만 따로 커밋 X). 커밋 메시지에 일일 보고서 추가 사실 명시.

**session-reports와의 구분**:
- `session-reports/`: 굵직한 마일스톤 (디자인 결정, 마이그레이션 등). **토픽 단위**.
- `daily-reports/`: 그날 무엇을 했는가의 타임라인 로그. **날짜 단위**.

같은 날 둘 다 작성될 수도 있음 (마일스톤 날 = session-report + daily-report 모두 갱신).
