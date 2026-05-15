# 다음 세션 핸드오프

> 이 파일은 **세션이 끝날 때마다 갱신**한다. 다른 PC/새 Claude 세션이 컨텍스트를 빠르게 잡는 진입점.

## 0. 새 세션 시작 시 읽을 순서

1. **이 파일** (`docs/NEXT-SESSION.md`) — 현재 위치, 다음 할 일
2. **README.md** — 게임 컨셉, 코드 구조, 합의된 설계 결정
3. **docs/design/** — 설계 문서 (현 시점 3개)
   - `synergy-axes.md` — 시너지 축 3개 + 친화 매트릭스 + 발동 해석
   - `progression.md` — 챕터/스테이지/이벤트 구조 + 난이도 곡선 + Fog of War
   - `cargo-and-mortality.md` — 적재 그리드 + 유닛 사망 시스템
4. **docs/session-reports/** — 시간순 작업 로그
   - `2026-05-14-initial-scaffold.md` — 1회차: 코어 시스템 코드 골격
   - `2026-05-14-synergy-axes.md` — 2회차: 시너지 축 정의
   - `2026-05-15-progression-and-cargo.md` — 3회차: 진행 구조 + 적재/사망 디자인

코드 위치:
- 데이터 리소스: `scripts/data/`
- 보드/시너지 엔진: `scripts/board/`
- 자동 전투: `scripts/combat/`
- 로그라이트 진행: `scripts/run/`
- 오토로드: `scripts/globals/game_state.gd`

## 1. 현재 상태 (2026-05-15 기준)

### ✅ 완료
- Godot 4.3+ 프로젝트 셋업 (`project.godot`, `.gitignore`, `icon.svg`)
- 데이터 모델: `UnitData`, `SynergyRule`, `ComputedStats`
- 보드: 5×3 `BoardState`, 8방향 인접
- 시너지 엔진: `SynergyEngine.compute(board, rules)` — 인접 기반 보너스 적용
- 자동 전투: `CombatUnit` (FSM) + `CombatManager` (틱 시뮬레이션)
- 로그라이트 진행: `RunState` + `MapNode` + `MapGenerator` (StS 스타일 DAG)
- 오토로드 `GameState`
- 시너지 축 3개 + 친화 매트릭스 코드화 (`scripts/data/synergy_types.gd`)
- `UnitData.validate_axes()` 등 축별 헬퍼
- **디자인 문서 3종** (`docs/design/`)

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

구현 우선순위 (`cargo-and-mortality.md` §7 참조):
1. `OwnedUnit` 클래스 + `RunState.owned_units` 타입 마이그레이션
2. 전투 종료 시 부상 처리 (HP 0 PLAYER 측 → `INJURED`)
3. `CargoState` 기본 모델 (회전 X 단순판)
4. `CargoItem` + 판매가
5. 회전 + 자동정렬 (UI 편의 기능)
6. `ItemEffect` 인터페이스 — `stat_boost`부터
7. 도시 액션 (부활/치료/구매/그리드 확장)

**카탈로그 받기 전에 B를 먼저 진행해도 됨** — 카탈로그는 데이터, B는 시스템 구조.

### 🚫 의도적으로 비워둔 것 (사용자가 직접 작업)
- 씬 파일 / UI 위젯 / 스프라이트
- 시스템 코드는 데이터 in / 데이터 out으로 동작 — UI는 위에 얹기만 하면 됨

## 2. 핵심 합의 사항 (다시 묻지 말 것)

| 항목 | 결정 |
|---|---|
| 엔진 | Godot 4.3 / 4.4 stable + GDScript |
| 그리드 | 5×3, **시너지 계산 전용**. 전투에는 안 쓰임 |
| 전투 | 그리드 밖, 양 진영 자유 이동/타겟팅 (AFK Arena 계열) |
| 인접 판정 | 8방향 |
| 시너지 축 | 3축: 국가 / 직업 / 유형. 각 유닛은 축당 정확히 1개 태그 |
| 시너지 발동 | "국가 유닛 입장에서 인접에 친화 태그 있으면 발동" |
| 보너스 합산 | 같은 스탯 % 보너스는 합산 후 곱: `base * (1 + sum_of_pct)` |
| 챕터 구조 | C1 마을 / C2 도시 / C3 국가 — 3챕터 × 8/10/12 스테이지 |
| 이벤트 종류 | 전투 / 여관 / 미니보스 / 특수 이벤트 (+ 챕터 보스) |
| Fog of War | 도착 시 노드 종류 공개 (기본값, 재논의 가능) |
| 난이도 배수 | C1=1.0 / C2=1.6 / C3=2.8, 챕터 내 +0~50% 추가 |
| 거래 모델 | 챕터 간 도시 화면에서 일괄 처리 (코어는 호위 전투) |
| 적재 시스템 | Backpack Hero식 격자, 회전 OK, 자동정렬 OK, 시너지 격자와 별개 |
| 아이템 사용 | **전투 시작 전 미리 사용**만 (전투 중 발동 X) |
| 유닛 상태 | 전투가능 / 부상 / 사망 — 회복 후 영구 페널티 없음 |
| 시체 적재 | 1×2 셀 점유, 도시 부활 가능, 버리기 = 단순 공간 회수 |
| UI 작업 주체 | 사용자 직접 — Claude는 씬 파일 안 만듦 |
| 커밋 정책 | 사용자 명시 요청 시만 (예외: 명시적 핸드오프 워크플로) |

## 3. 다른 PC에서 시작하는 법

```bash
# 1. 클론
git clone https://github.com/PowerSH/Road_of_Pargo.git
cd Road_of_Pargo

# 2. git identity (로컬 한정)
git config user.name 'Harry'
git config user.email '39876295+PowerSH@users.noreply.github.com'

# 3. Godot 4.3+로 폴더 열기 (project.godot 자동 인식)
```

## 4. 새 세션에 빠르게 컨텍스트 주는 한 줄 프롬프트

> "Road of Pargo 게임 프로젝트. 다른 PC에서 작업하던 거 이어서 한다. 먼저 `docs/NEXT-SESSION.md` 읽고 현재 상태 정리해서 알려줘."

또는 더 짧게:

> "docs/NEXT-SESSION.md 읽고 상태 보고."

## 5. 세션 끝낼 때 체크리스트 (다음 사람을 위해)

- [ ] 이 파일(`docs/NEXT-SESSION.md`)의 "현재 상태" / "대기 중" 섹션 갱신
- [ ] 작업 요약을 `docs/session-reports/YYYY-MM-DD-<topic>.md`로 추가
- [ ] 새 합의 사항은 "핵심 합의 사항" 표에 반영
- [ ] 커밋 + 푸시
