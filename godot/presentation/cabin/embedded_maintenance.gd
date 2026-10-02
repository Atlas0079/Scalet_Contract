extends "res://presentation/maintenance/maintenance.gd"
var input_active := false
func _ready():
 super._ready()
 # Cabin compositor reuses the same CRT shader and our separate scene/text textures.
 set_bypass(true)
 var game_size := Vector2i(1920,1440)
 size = game_size
 for viewport in [view,compose,final_view,object_outline.mask_view,object_outline.output]: viewport.size = game_size
 object_outline.output.get_child(0).size = game_size
 final_view.get_child(0).size = game_size
 object_outline.material.set_shader_parameter("resolution",Vector2(game_size))
 ui_layer.size = game_size
 # Re-anchor interface blocks; world labels are projected again from the 4:3 camera.
 for item in ui_layer.get_children():
  if item in [status,help,note,note_back]: continue
  if item is ColorRect:
   if item.position.x > 1500: item.position.x = 1280; item.size.x = 580
   elif item.position.y > 1200: item.size.x = 1160
 status.position.x = 1300
 help.text = "WASD 移动  鼠标朝向  滚轮缩放\nE 查看现场  O 开关门  N 描边  空格暂停  2 CRT"
 note_back.position.x = 1240
 note_back.size.x = 620
 note.position.x = 1260
 note.size.x = 580
 update_outline_width()
 update_text_positions()
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 refresh_status()
func _unhandled_input(event: InputEvent):
 if event is InputEventKey and event.keycode in [KEY_V,KEY_F,KEY_BRACKETLEFT,KEY_BRACKETRIGHT]: return
 if input_active: super._unhandled_input(event)
func _process(delta: float):
 if input_active:
  super._process(delta)
 elif is_instance_valid(unit) and post:
  if not frozen: clock_time += delta
  post.set_shader_parameter("elapsed_time",clock_time)
  if object_outline: object_outline.sync_instances()

func refresh_status():
 if not post or not status: return
 note_back.visible = not note.text.is_empty()
 status.text = "游戏源画面 1920 x 1440\nCRT 信号 720 x 540"

func screen_uv_to_scene(uv: Vector2) -> Vector2:
 # Base scene normalizes its mouse against its standalone 16:9 design size.
 return uv * Vector2(2560.0/1920.0,1.0)
