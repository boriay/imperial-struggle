class_name Overlay
extends Control

## 2D layer over the 3D view: health bars, aim lines, hit chances, the selection box.
## Draws whatever game.draw_overlay decides to show.

var game: Node


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if game != null:
		game.draw_overlay(self)
