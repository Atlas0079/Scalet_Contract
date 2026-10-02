extends "res://presentation/tactical/tactical_study.gd"
## Reuse the running range; cabin navigation must not become game input.
var input_active := false
func _ready():
 super._ready()
 # Use a 2560x1920 logical layout, uniformly rendered into the 1920x1440 feed.
 scale = Vector2.ONE * 0.75
 for control in ui.get_children():
  if control is Panel:
   control.size.y += 480
   for child in control.get_children():
    if child is ScrollContainer: child.size.y += 480
  elif control.position.y >= 1200: control.position.y += 480
 target_paper.size.y += 480
 ui.theme = Theme.new()
 ui.theme.default_font = preload("res://assets/NotoSansSC-Regular.ttf")
 for control in ui.get_children():
  if control is Label and "1–8 射位" in control.text:
   control.text = control.text.replace("1–8 射位", "3–8 射位 · 1 切换画面 · 2 CRT")
func manual_input() -> Vector2:
 return super.manual_input() if input_active else Vector2.ZERO
func _input(event):
 if input_active: super._input(event)
func _unhandled_input(event):
 if input_active:
  var local_event = event.duplicate()
  if local_event is InputEventMouse:
   local_event.position /= 0.75
   local_event.global_position = local_event.position
  super._unhandled_input(local_event)
