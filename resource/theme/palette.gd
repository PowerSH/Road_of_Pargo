class_name Palette
extends RefCounted

## Ashen Crown 색 토큰. asset/component/Private_Design/css/theme.css 의 :root 변수와 1:1 대응.
## UI 코드에서 색을 직접 박을 때 여기 상수를 참조한다 (오타·불일치 방지).
## Theme 리소스(ashen_crown.tres)도 같은 값을 쓰지만 .tres는 float Color라 별도 보관.
## 인스턴스화 금지 — 네임스페이스 용도.

# ─── Parchment surfaces ───
const PAPER_HI := Color("f4ecd6")   ## raised / highlight
const PAPER := Color("e9ddbe")      ## base parchment
const PAPER_2 := Color("decda4")    ## sunken / pressed
const PAPER_3 := Color("d2bc8e")    ## deep recess
const PAPER_EDGE := Color("b89b68") ## worn outer edge

# ─── Ink ───
const INK := Color("2a2014")        ## primary text
const INK_2 := Color("5c4b32")      ## secondary text
const INK_3 := Color("8a7351")      ## muted / disabled
const RULE := Color("6e5634")       ## hairline rules
const RULE_2 := Color("4a3a22")     ## heavy rules

# ─── Accents ───
const RUBRIC := Color("9a2e22")     ## wax-seal red
const GOLD := Color("b5893a")       ## gilt
const GOLD_HI := Color("d8b45e")    ## bright gilt edge

# ─── Gauges ───
const HP := Color("97271b")
const HP_2 := Color("c0392b")
const MP := Color("355b79")
const MP_2 := Color("4e80a6")
const XP := Color("b5893a")
const STAM := Color("6b6a2e")

# ─── Rarity (아이템 등급) ───
const RAR_COMMON := INK_3
const RAR_RARE := MP_2
const RAR_EPIC := Color("7b4ba0")
const RAR_LEGEND := GOLD
