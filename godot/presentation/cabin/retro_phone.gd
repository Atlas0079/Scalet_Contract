extends Node3D
## Shared handset session, LCD and audio. Model binding is supplied by the handset.
## Backend signals live on `call`; preview acknowledgements can
## be disabled when the game takes ownership. Session IDs reject late callbacks.
const CALL = preload("res://presentation/cabin/phone_call.gd")
const FONT = preload("res://assets/fonts/fusion-pixel-12px-monospaced-zh_hans.otf")
var call = CALL.new()
var preview_backend := true
var model: Node3D
var keys := {}
var display: SubViewport
var text: Label
var softkeys: Label
var ring_audio: AudioStreamPlayer3D
var tone_audio: AudioStreamPlayer3D
var voice_audio: AudioStreamPlayer3D
var ring_timer := 0.0
var audio_phase := "idle"

func audio_player(volume: float) -> AudioStreamPlayer3D:
 var player := AudioStreamPlayer3D.new()
 player.volume_db = volume;player.unit_size = 1.0;player.max_distance = 3.0
 add_child(player)
 return player

func build_lcd(mesh: MeshInstance3D):
 display = SubViewport.new();display.size = Vector2i(120,84)
 display.disable_3d = true;display.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 add_child(display)
 var background := ColorRect.new();background.size = display.size;background.color = Color("87966a")
 display.add_child(background)
 var header := label(Vector2(4,1),12);header.text = "▮▮▮    ▰"
 text = label(Vector2(4,17),12)
 text.size = Vector2(112,52);text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
 softkeys = label(Vector2(4,68),12)
 var shader := Shader.new()
 shader.code = """shader_type spatial;
render_mode cull_disabled;
varying vec2 lcd_uv;
uniform sampler2D display_texture: filter_nearest;
uniform vec2 lcd_min;
uniform vec2 lcd_size;
void vertex(){lcd_uv=vec2((VERTEX.x-lcd_min.x)/lcd_size.x,1.0-(VERTEX.y-lcd_min.y)/lcd_size.y);}
void fragment(){vec3 ink=texture(display_texture,lcd_uv).rgb;ALBEDO=ink;ROUGHNESS=0.8;EMISSION=ink*0.18;}
"""
 var material := ShaderMaterial.new();material.shader = shader
 material.set_shader_parameter("display_texture",display.get_texture())
 var bounds := mesh.get_aabb()
 material.set_shader_parameter("lcd_min",Vector2(bounds.position.x,bounds.position.y))
 material.set_shader_parameter("lcd_size",Vector2(bounds.size.x,bounds.size.y))
 mesh.material_override = material

func label(at: Vector2, size: int) -> Label:
 var result := Label.new();result.position = at
 result.add_theme_font_override("font",FONT);result.add_theme_font_size_override("font_size",size)
 result.add_theme_color_override("font_color",Color("1b2918"))
 display.add_child(result)
 return result

func refresh():
 if not text: return
 var lines: String = call.status+"\n"+(call.number if call.phase=="idle" else call.peer)
 if call.phase=="connected": lines += "\n%02d:%02d" % [int(call.elapsed)/60,int(call.elapsed)%60]
 text.text = lines
 softkeys.text = "呼叫     清除" if call.phase=="idle" else ("接听     拒接" if call.phase=="ringing" else "         挂断")
 if audio_phase != call.phase:
  audio_phase = call.phase
  ring_audio.stop();tone_audio.stop();ring_timer = 0.0
  if call.phase != "connected": voice_audio.stop()
  if call.phase=="ringing": ring()
  elif call.phase=="outgoing":
   tone_audio.stream = sound([Vector3(440,480,0.6),Vector3(0,0,1.4)])
   tone_audio.play()

func _process(delta: float):
 call.advance(delta)
 if call.phase=="ringing":
  ring_timer -= delta
  if ring_timer<=0: ring()
 elif call.phase=="outgoing" and not tone_audio.playing:
  tone_audio.play()

func ring():
 ring_timer = 2.1
 ring_audio.stream = sound([Vector3(880,0,0.12),Vector3(1175,0,0.12),Vector3(988,0,0.12),Vector3(1320,0,0.18),Vector3(0,0,0.1),Vector3(880,0,0.12),Vector3(1175,0,0.12),Vector3(988,0,0.12),Vector3(1320,0,0.18)])
 ring_audio.play()

func sound(notes: Array) -> AudioStreamWAV:
 var data := PackedByteArray()
 const RATE = 22050
 for note in notes:
  var count := int(note.z*RATE)
  for i in range(count):
   var t := float(i)/RATE
   var edge := minf(1.0,minf(float(i),float(count-1-i))/110.0)
   var value := 0.0 if note.x==0 else sin(TAU*note.x*t)
   if note.y>0: value = (value+sin(TAU*note.y*t))*0.5
   var sample := int(value*edge*12000.0)
   data.append(sample&255);data.append((sample>>8)&255)
 var wav := AudioStreamWAV.new();wav.format = AudioStreamWAV.FORMAT_16_BITS;wav.mix_rate = RATE;wav.data = data
 return wav

func press(value: String):
 if value in keys:
  var node: Node3D = keys[value]
  if node.has_meta("press"):
   var old: Tween = node.get_meta("press")
   if old and old.is_valid():old.kill()
  var tween := create_tween();node.set_meta("press",tween)
  var rest: Vector3=node.get_meta("rest_position")
  tween.tween_property(node,"position",rest+Vector3(node.get_meta("press_travel")),0.05)
  tween.tween_property(node,"position",rest,0.1)
 if value.length()==1 and value in "0123456789*#":
  if call.digit(value):
   var index := "123456789*0#".find(value)
   var low: int = [697,770,852,941][index/3]
   var high: int = [1209,1336,1477][index%3]
   tone_audio.stream = sound([Vector3(low,high,0.12)]);tone_audio.play()
 elif value in ["call","ok","soft_left"]:
  if call.phase=="ringing":call.answer()
  elif call.phase=="idle":call.dial()
 elif value=="clear":
  if call.phase=="idle":call.clear()
  else:call.hang_up()
 elif value=="end":call.hang_up()

func keyboard(event: InputEventKey) -> bool:
 if not event.pressed or event.echo:return false
 var value := String.chr(event.unicode) if event.unicode>0 else ""
 if value in "0123456789*#" and value.length()==1:press(value);return true
 if event.keycode>=KEY_0 and event.keycode<=KEY_9:press(str(event.keycode-KEY_0));return true
 match event.keycode:
  KEY_ENTER,KEY_KP_ENTER:press("call")
  KEY_BACKSPACE,KEY_DELETE:press("clear")
  KEY_END:press("end")
  KEY_I:
   if preview_backend:receive_call("未知号码")
  _:return false
 return true

func contact(ray_owner: Node3D, camera: Camera3D, point: Vector2) -> String:
 for value in keys:
  var node: MeshInstance3D = keys[value].get_child(0)
  if ray_owner.mesh_hit(camera,point,node)!=null:return value
 return ""

func receive_call(caller: String) -> int:
 return call.receive_call(caller)
func play_voice(stream: AudioStream):
 if call.phase!="connected":return
 voice_audio.stream = stream;voice_audio.play()
func preview_outgoing(id: int, _number: String):
 if not preview_backend:return
 await get_tree().create_timer(2.0).timeout
 if is_inside_tree() and preview_backend:call.connect_call(id)
func preview_answer(id: int):
 if not preview_backend:return
 await get_tree().create_timer(0.2).timeout
 if is_inside_tree() and preview_backend:call.connect_call(id)
