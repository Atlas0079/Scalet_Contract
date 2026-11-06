extends "res://presentation/tactical/tactical_study.gd"
## Reuse the running range; cabin navigation must not become game input.
var input_active := false
var display_layout: Array[Dictionary] = []
var paper_height := 0.0
func _ready():
 super._ready()
 for control in ui.get_children():
  display_layout.append({"control":control,"position":control.position,"size":control.size})
  if control is Panel:
   for child in control.get_children():
    if child is ScrollContainer: display_layout.append({"control":child,"position":child.position,"size":child.size})
 paper_height = target_paper.size.y
 set_display_size(get_viewport().size)
 ui.theme = Theme.new()
 ui.theme.default_font = preload("res://assets/NotoSansSC-Regular.ttf")
 for control in ui.get_children():
  if control is Label and "1–8 射位" in control.text:
   control.text = control.text.replace("1–8 射位", "3–8 射位 · 1 切换画面 · 2 CRT")

func set_display_size(game_size: Vector2i):
 # Fit the entire existing tool horizontally, retaining uniform UI/sprite scale.
 scale = Vector2.ONE*float(game_size.x)/2560.0
 var extra := float(game_size.y)/scale.y-1440.0
 for item in display_layout:
  var control: Control = item.control
  control.position = item.position
  control.size = item.size
  if control is Panel or control is ScrollContainer: control.size.y += extra
  elif control.position.y >= 1200: control.position.y += extra
 target_paper.size.y = paper_height+extra
func manual_input() -> Vector2:
 return super.manual_input() if input_active else Vector2.ZERO
func _input(event):
 if input_active: super._input(event)
func _unhandled_input(event):
 if input_active:
  var local_event = event.duplicate()
  if local_event is InputEventMouse:
   local_event.position /= scale.x
   local_event.global_position = local_event.position
  super._unhandled_input(local_event)
