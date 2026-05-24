# 세션 보고서: Godot 4.6 마이그레이션 + UI 씬 골격

- **날짜**: 2026-05-25
- **에이전트**: Claude Code (Opus 4.7, 1M context)
- **작업자**: PowerSH
- **목표**: 다른 PC에서 작업 이어가기 위한 환경 셋업, Godot 4.6 호환성 정리, 전체 게임 흐름의 UI 씬 골격(placeholder) 구축.

---

## 1. 환경 셋업

### 1.1 다른 PC에 GitHub 저장소 동기화
- 로컬(`C:\Users\PSH\Game_create\road-of-pargo`)에 빈 Godot 프로젝트가 있었음 — Godot 4.6에서 만든 기본 placeholder.
- GitHub(`PowerSH/Road_of_Pargo`)에 실제 게임 코드 + 디자인 문서 존재.
- 처리: 로컬 전용 파일(`.godot` 캐시, `.editorconfig`, `.gitattributes`, `icon.svg.import`) 백업 → 로컬 폴더 비우기 → GitHub repo clone 내용물 이동 → 백업 파일 복원.
- 결과: 로컬이 정상적인 git clone 상태 (origin remote 연결, 커밋 히스토리 보존).
- 백업본 `.road-of-pargo-local-backup` 은 안전 차원에서 보존.

### 1.2 Godot 4.6 자동 마이그레이션
- 사용자가 Godot 4.6으로 프로젝트 첫 오픈 → 4.3 → 4.6 자동 변환 수락.
- `project.godot` 자동 갱신:
  - `config/features=PackedStringArray("4.6", "GL Compatibility")`
  - 1280×720 viewport / canvas_items stretch / expand aspect 유지
  - main_scene이 사용자가 만든 `main_menu.tscn` UID로 자동 설정됨
- Godot 4.4+ 도입 `.gd.uid` 파일들이 `scripts/**` 전반에 새로 생성됨 (untracked 상태).

## 2. Godot 4.6 코드 호환성 수정

### 2.1 빌트인 시그니처 충돌
- **`unit_data.gd:41`** `func get_class() -> StringName:` — `Object.get_class()`의 시그니처(`-> String`)와 충돌.
  - 해결: `get_class_tag()` 로 개명. 내부 호출(line 65) 동기화.
  - 의도와 다른 빌트인 오버라이드는 Godot 내부에서 부작용 위험 있음.
- **`map_screen.gd`** `func _get_tooltip(index: int) -> String:` — `Control._get_tooltip(Vector2) -> String` 가상 메서드와 충돌.
  - 해결: `_tooltip_for(index)` 로 개명.

### 2.2 정적 타입 추론 엄격화
- **`board_state.gd:60-61`**, **`map_generator.gd:30`** — `for x in [-1, 0, 1]:` 패턴.
  - 4.6에선 untyped Array 리터럴의 원소를 `Variant`로 추론. `int + Variant` 산술은 결과 타입 결정 불가 → 에러.
  - 해결: `for x: int in [-1, 0, 1]:` 명시적 타입.

### 2.3 인스펙터 표시용 가짜 속성
- **`map_screen.gd`** `label.theme_override_font_sizes["font_size"] = 18` — 4.6에선 dict 접근 불가.
  - 해결: `label.add_theme_font_size_override(&"font_size", 18)`.

## 3. 데이터 모델 확장

### 3.1 `RunState` — Fog of War 추적
- `revealed_nodes: Array[int]` 추가.
- `is_revealed(index)` / `reveal_initial()` 헬퍼.
- `enter_node(index)` 가 진입 시 자동으로 `revealed_nodes`에 추가.
- `reveal_initial()` 은 boss 노드만 사전 공개 (목적지로 기능). progression.md §3 옵션 A 준수.

### 3.2 `GameState.start_new_run()`
- `MapGenerator.generate()` 직후 `run.reveal_initial()` 호출 라인 1줄 추가.

## 4. UI 씬 골격 (11개 씬 + 11개 스크립트)

전체 게임 흐름을 placeholder로 구축. 모든 씬은 `Control` 루트 + 외부 스크립트 부착 + 시그널은 .tscn `[connection]` 으로 정의.

### 흐름도
```
Menu → Story → Hub → Map → [Battle/Elite/Rest/Shop/Event/Treasure/Boss]
        (인트로)  (거점)   (StS DAG)         (kind별 분기 후 Map 복귀)
                   ▲                              │
                   └───────── 보스 승리 ──────────┘
```

### 씬 인벤토리

| 파일 | 역할 | 상태 |
|---|---|---|
| `main_menu.tscn` | Start / Exit | ✅ 구현 |
| `story_screen.tscn` | 인트로 텍스트 → 거점 | placeholder (계속 버튼만) |
| `hub_screen.tscn` | 거점 (용병/상점/NPC/맵 출발) | placeholder (버튼 5개, 동작 미구현) |
| `map_screen.tscn` | StS식 노드 맵 | ✅ 구현 (격자 배치, 엣지, fog, kind 라벨) |
| `battle_screen.tscn` | 일반 전투 | placeholder (승리/패배 테스트) |
| `elite_screen.tscn` | 엘리트 전투 | placeholder |
| `rest_screen.tscn` | 휴식/모닥불 | placeholder (HP 회복은 실동작) |
| `shop_screen.tscn` | 상점 노드 | placeholder |
| `event_screen.tscn` | 특수 이벤트 | placeholder (선택지 2개) |
| `treasure_screen.tscn` | 보물 노드 | placeholder |
| `boss_screen.tscn` | 챕터 보스 | placeholder (승리 → 거점) |

### map_screen.gd 라우팅
`_scene_for_kind(kind)` 가 `MapNode.Kind` 7종 모두를 해당 씬으로 매핑.

### 합의된 placeholder 결정
- **5×3 시너지 그리드(편성)**: 별도 씬 X. Battle/Elite/Boss 씬 내부 단계로 통합 예정.
- **챕터 진행**(보스 → 다음 챕터): 현재는 보스 승리 시 Hub 복귀까지만. 챕터 카운터, 맵 재생성은 후순위 구현.
- **스토리 화면**: 게임 시작 시 인트로 1회만. 챕터 사이 컷씬은 후순위.
- **Hub 내부**(용병 고용/아이템 상점/NPC 조우): 일단 print만 (placeholder).

## 5. 문서 갱신

### 변경
- `README.md` line 3, 76: "Godot 4.3" → "Godot 4.6"
- `docs/NEXT-SESSION.md` line 28, 76, 106: 동일한 버전 표기 갱신, "엔진 4.3/4.4 stable" → "4.6"

### 비변경 원칙
- `docs/session-reports/*.md` 3개는 시간순 작업 로그라 사후 편집 안 함. 본 보고서가 4번째.

## 6. 학습된 함정 (다음 세션을 위해)

### 6.1 Godot 인라인 스크립트 함정
- 에디터에서 시그널 connect 시 "Make Function" 체크박스가 켜져 있으면 .tscn 안에 인라인 GDScript sub-resource를 자동 생성. 외부 스크립트와 별개로 stub 메서드들이 쌓이고, 외부 스크립트의 진짜 구현은 호출 안 됨.
- **원칙**: connect 다이얼로그에서 항상 "Make Function" 끄고, Receiver Method 칸에 외부 스크립트 기존 메서드명 직접 타이핑.
- 이번에 한 번 당해서 `main_menu.tscn`을 인라인 스크립트 통째로 들고 있게 됐었음. Detach Script → 외부 .gd 드래그로 정리.

### 6.2 외부 .tscn 편집 vs Godot 인메모리 상태
- Godot이 .tscn을 열어서 메모리에 들고 있는 동안 외부 도구가 그 파일을 고치면, Godot이 다음 저장 때 인메모리 버전으로 덮어씀.
- **원칙**: Godot에 이미 로드된 씬의 구조 변경은 GUI 안에서. 스크립트(.gd) 내용 변경은 외부 편집 OK (Godot이 reload 감지함). 새 .tscn 파일 작성은 Godot이 아직 모르므로 외부 작성 안전.

### 6.3 GDScript 4.6 타입 추론 변화
- `for x in [literal_array]:` 의 x는 Variant로 추론. 산술하면 결과 타입 결정 불가 에러.
- **원칙**: 배열 리터럴로 도는 for-loop는 항상 `for x: int in [...]:` 형태로 명시.

### 6.4 빌트인 가상 메서드 이름 회피
- `get_class`, `_get_tooltip`, `_get_drag_data`, `_can_drop_data`, `_drop_data`, `_gui_input`, `_has_point`, `_make_custom_tooltip`, `_get_minimum_size`, `_notification`, `_to_string` 등.
- **원칙**: 헬퍼 메서드는 빌트인과 안 겹치는 이름으로. 의심스러우면 `Control._method_name` 검색.

### 6.5 인스펙터 표시용 가짜 속성
- `theme_override_font_sizes`, `theme_override_colors`, `theme_override_constants` 등은 인스펙터 표시용 그룹. 코드에선 `add_theme_*_override(name, value)` 메서드 사용.

## 7. 코드 변경 인벤토리

### 신규 파일
- **씬 (10개)**: `scenes/{story,hub,battle,elite,rest,shop,event,treasure,boss,map}_screen.tscn`
- **스크립트 (11개)**: `scripts/ui/{main_menu,story,hub,map,battle,elite,rest,shop,event,treasure,boss}_screen.gd`

### 수정
- `scripts/data/unit_data.gd` — `get_class` → `get_class_tag` 개명 (+ 내부 호출)
- `scripts/board/board_state.gd:60-61` — for-loop 명시 타입
- `scripts/run/map_generator.gd:30` — for-loop 명시 타입
- `scripts/run/run_state.gd` — `revealed_nodes`, `is_revealed`, `reveal_initial` 추가, `enter_node` 자동 reveal
- `scripts/globals/game_state.gd` — `start_new_run` 에서 `reveal_initial` 호출
- `README.md`, `docs/NEXT-SESSION.md` — Godot 4.3 → 4.6 표기

## 8. 다음 세션 권장 작업

우선순위 후보 (사용자 결정):

1. **battle_screen 진짜 구현** — 5×3 편성 단계 + 자동 전투 시뮬레이션(`CombatManager` 연동). 게임 코어가 처음으로 움직이는 시점. 가장 큰 작업이지만 백엔드 코드는 이미 있음.
2. **챕터 진행 로직** — `RunState.chapter`, 보스 승리 → 맵 재생성. 작업량 작고 게임 흐름 완결.
3. **hub_screen 내부 채우기** — 용병/상점/NPC sub-popup. 콘텐츠 없어도 골격 가능.
4. **유닛 카탈로그 수령 → `.tres` 일괄 생성** — 사용자 엑셀 작업 완료 후. 12개 시너지 룰 보너스 수치 동시 채움.

## 9. 의도적으로 미룬 것

- 메인 메뉴 시각 디자인 (현재 중앙 정렬 텍스트 + 버튼만, 배경 아트 없음)
- 각 씬의 실제 UI 디자인 (placeholder는 모두 CenterContainer + VBox)
- 챕터 카운터 / 챕터별 적 스케일링 적용
- `.gd.uid` 파일 git 추적 정책 — 현재 untracked, 커밋 여부 미정
- 세션 보고서 자체의 git 커밋 — `NEXT-SESSION.md:93` "커밋은 사용자 명시 요청 시만" 원칙에 따라
