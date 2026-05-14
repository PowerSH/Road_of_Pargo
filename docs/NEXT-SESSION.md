# 다음 세션 핸드오프

> 이 파일은 **세션이 끝날 때마다 갱신**한다. 다른 PC/새 Claude 세션이 컨텍스트를 빠르게 잡는 진입점.

## 0. 새 세션 시작 시 읽을 순서

1. **이 파일** (`docs/NEXT-SESSION.md`) — 현재 위치, 다음 할 일
2. **README.md** — 게임 컨셉, 코드 구조, 합의된 설계 결정
3. **docs/design/synergy-axes.md** — 시너지 축 3개 + 친화 매트릭스 + 발동 해석
4. **docs/session-reports/** — 시간순 작업 로그
   - `2026-05-14-initial-scaffold.md` — 1회차: 코어 시스템 코드 골격
   - `2026-05-14-synergy-axes.md` — 2회차: 시너지 축 정의

코드 위치:
- 데이터 리소스: `scripts/data/`
- 보드/시너지 엔진: `scripts/board/`
- 자동 전투: `scripts/combat/`
- 로그라이트 진행: `scripts/run/`
- 오토로드: `scripts/globals/game_state.gd`

## 1. 현재 상태 (2026-05-14 기준)

### ✅ 완료
- Godot 4.3+ 프로젝트 셋업 (`project.godot`, `.gitignore`, `icon.svg`)
- 데이터 모델: `UnitData`, `SynergyRule`, `ComputedStats`
- 보드: 5×3 `BoardState`, 8방향 인접
- 시너지 엔진: `SynergyEngine.compute(board, rules)` — 인접 기반 보너스 적용
- 자동 전투: `CombatUnit` (FSM) + `CombatManager` (틱 시뮬레이션)
- 로그라이트 진행: `RunState` + `MapNode` + `MapGenerator` (StS 스타일 DAG)
- 오토로드 `GameState` (현재 run + board 보관)
- 시너지 축 3개 + 친화 매트릭스 코드화 (`scripts/data/synergy_types.gd`)
- `UnitData.validate_axes()` 등 축별 헬퍼

### ⏸ 대기 중 (사용자가 다른 PC에서 작업 후 던질 예정)

**유닛 카탈로그 (엑셀로 작성 중)**

사용자가 엑셀로 정리해서 올릴 예정. 기대 스키마:

| id | display_name | nation | class | type | max_hp | attack | atk_speed | atk_range | move_speed | cost | tier | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|

- `nation`: 벤 / 크렘 / 아르덴 / 넬름
- `class`: 보병 / 창병 / 궁병 / 석궁병
- `type`: 군인 / 모험가 / 용병
- `id`는 비어 있으면 컨벤션(`{nation}_{class}_{NN}` 예: `ven_infantry_01`)으로 자동 부여
- `atk_speed`: 초당 공격 횟수, `atk_range`: 픽셀 단위
- 한국어 입력 OK — 받을 때 `SynergyTypes` 상수로 매핑

엑셀(.xlsx) / CSV / 마크다운 테이블 / 스크린샷 모두 처리 가능.

**유닛 카탈로그를 받으면 다음 작업**:
1. 데이터 검증 (각 축에 정확히 1개 태그, 누락된 직업/국가 조합 체크)
2. `resources/units/*.tres` 일괄 생성 (`UnitData` 인스턴스 → `ResourceSaver.save`)
3. 12개 `SynergyRule` `.tres` 생성 — 보너스 % 값은 사용자가 별도 시트로 줄 수도, 1차안을 Claude가 제시할 수도.

### 🚫 의도적으로 비워둔 것 (사용자가 직접 작업)
- 씬 파일 / UI 위젯 / 스프라이트
- 사용자가 인터페이스 작업할 예정 — 시스템 코드는 모두 데이터 in / 데이터 out으로 동작하므로 UI는 위에 얹기만 하면 됨

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
| UI 작업 주체 | 사용자 직접 — Claude는 씬 파일 안 만듦 |
| 커밋 정책 | 사용자 명시 요청 시만 |

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
