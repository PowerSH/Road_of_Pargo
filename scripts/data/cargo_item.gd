class_name CargoItem
extends Resource

## 상단 적재함의 1개 아이템. shape_cells가 anchor 기준 점유 셀들을 정의한다.
## 전투 직전 슬롯에 넣으면 `battle_effect`가 발동, 도시에서 팔면 `sell_value`만큼 골드.
##
## cargo-and-mortality.md §2 (점유 모양 카탈로그) + §4 (판매가) 참조.

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
}

@export var id: StringName
@export var display_name: String
@export_multiline var description: String

@export_group("Shape")
## Anchor 기준 점유 셀들. anchor 자체는 (0,0)으로 간주.
##  1×1   = [(0,0)]
##  1×2 세로 = [(0,0), (0,1)]
##  2×2   = [(0,0), (1,0), (0,1), (1,1)]
##  L자    = [(0,0), (0,1), (1,1)]
##  시체 1×2 = [(0,0), (0,1)] + rotatable=false
@export var shape_cells: Array[Vector2i] = [Vector2i(0, 0)]
## 회전 허용 여부. 시체는 false 권장.
@export var rotatable: bool = true

@export_group("Economy")
## 도시 판매 시 받는 골드 (베이스). 챕터 모디파이어는 City actions에서 적용.
@export var sell_value: int = 0
## 어느 챕터부터 등장하는지 (1/2/3). 0이면 모든 챕터에서 등장 가능.
@export var chapter_tier: int = 1
@export var rarity: Rarity = Rarity.COMMON

@export_group("Battle")
## 전투 직전 슬롯에 넣고 "전투 시작" 시 발동되는 효과. null이면 순수 판매 아이템.
@export var battle_effect: ItemEffect

@export_group("Visuals")
@export var icon: Texture2D


## anchor + rotation으로 실제 점유 셀들을 계산해 반환.
## rotation: 0 = 원본, 1 = 90° CW, 2 = 180°, 3 = 270° CW.
func compute_occupied_cells(anchor: Vector2i, rotation: int = 0) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r: int = posmod(rotation, 4)
	for cell in shape_cells:
		out.append(anchor + _rotate_cell(cell, r))
	return out


## 회전 후 점유 셀들이 들어가는 박스 크기(폭, 높이). UI 미리보기·정렬용.
func bounding_box(rotation: int = 0) -> Vector2i:
	if shape_cells.is_empty():
		return Vector2i.ZERO
	var r: int = posmod(rotation, 4)
	var first: Vector2i = _rotate_cell(shape_cells[0], r)
	var min_xy: Vector2i = first
	var max_xy: Vector2i = first
	for c in shape_cells:
		var rc: Vector2i = _rotate_cell(c, r)
		min_xy.x = mini(min_xy.x, rc.x)
		min_xy.y = mini(min_xy.y, rc.y)
		max_xy.x = maxi(max_xy.x, rc.x)
		max_xy.y = maxi(max_xy.y, rc.y)
	return Vector2i(max_xy.x - min_xy.x + 1, max_xy.y - min_xy.y + 1)


## CargoItem.shape_cells가 비어 있거나 anchor 셀(0,0)이 빠져 있으면 잘못된 데이터.
func is_shape_valid() -> bool:
	if shape_cells.is_empty():
		return false
	for c in shape_cells:
		if c == Vector2i.ZERO:
			return true
	return false


static func _rotate_cell(cell: Vector2i, r: int) -> Vector2i:
	match r:
		1:
			return Vector2i(-cell.y, cell.x)
		2:
			return Vector2i(-cell.x, -cell.y)
		3:
			return Vector2i(cell.y, -cell.x)
	return cell
