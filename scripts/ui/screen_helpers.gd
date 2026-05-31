class_name ScreenHelpers
extends RefCounted

## 모든 UI 씬에서 공통으로 쓰는 헬퍼. 인스턴스화하지 말 것 — static만 사용.


## 화면 루트에 배경 이미지 + 가독성용 dim 오버레이를 가장 뒤(첫 자식)로 삽입.
## - root: 화면 루트 Control 노드 (보통 self)
## - path: res:// 경로 (예: "res://resource/bg_img/bg_main.jpg")
## - dim: 검은 오버레이 알파 (0.0 ~ 1.0, 0이면 오버레이 없음). 기본 0.35.
static func add_background(root: Control, path: String, dim: float = 0.35) -> void:
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		push_warning("[ScreenHelpers] background not found: %s" % path)
		return

	var bg := TextureRect.new()
	bg.name = "Background"
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	root.move_child(bg, 0)

	if dim > 0.0:
		var overlay := ColorRect.new()
		overlay.name = "BackgroundDim"
		overlay.color = Color(0.0, 0.0, 0.0, dim)
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(overlay)
		root.move_child(overlay, 1)
