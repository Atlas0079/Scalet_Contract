extends Label
## Lightweight frame pacing display; independent from the gameplay instructions.
var elapsed := 0.0
var samples := 0
var frame_time := 0.0
var previous_tick := 0

func _ready():
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
 set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
 offset_left = -300;offset_right = -24;offset_top = 16;offset_bottom = 88
 add_theme_font_override("font",preload("res://assets/fonts/fusion-pixel-12px-monospaced-zh_hans.otf"))
 add_theme_font_size_override("font_size",28)
 add_theme_color_override("font_color",Color("d2ded5"))
 add_theme_color_override("font_shadow_color",Color.BLACK)
 add_theme_constant_override("shadow_offset_x",2)
 add_theme_constant_override("shadow_offset_y",2)
 text = "FPS --"
 previous_tick = Time.get_ticks_usec()

func _process(_delta: float):
 var tick := Time.get_ticks_usec()
 var interval := float(tick-previous_tick)/1000.0
 frame_time += interval
 previous_tick = tick
 samples += 1
 elapsed += interval/1000.0
 if elapsed < 0.5:return
 text = "FPS %d\n%.1f ms" % [Engine.get_frames_per_second(),frame_time/maxi(samples,1)]
 elapsed = 0.0;frame_time = 0.0;samples = 0
