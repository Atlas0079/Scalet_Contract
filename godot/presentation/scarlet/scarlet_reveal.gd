extends Node3D
## Standalone cinematic study. Reuses project textures; no gameplay integration.
const MODEL = preload("res://assets/environment/scarlet/scarlet.glb")
const PAINT = preload("res://assets/environment/scarlet/textures/housing_paint.png")
const METAL_COLOR = preload("res://assets/environment/metal_plate_02/metal_plate_02_diff_1k.jpg")
const METAL_ROUGH = preload("res://assets/environment/metal_plate_02/metal_plate_02_rough_1k.jpg")
const METAL_NORMAL = preload("res://assets/environment/metal_plate_02/metal_plate_02_nor_gl_1k.jpg")
const METAL_METALLIC = preload("res://assets/environment/metal_plate_02/metal_plate_02_metal_1k.jpg")
const GLASS = preload("res://presentation/scarlet/optical_glass.gdshader")
const PERIOD = 15.0
const ARM_BAKE_FPS = 120.0
const ARM_BAKE_DURATION = 10.0
var clock := 0.0
var paused := false
var inspection := false
var clay := false
var clay_applied := false
var surface_materials := {}
var clay_materials := {}
var view_mode := 0
var armor_hidden := false
var armor_parts: Array[Node3D] = []
var stage_meshes: Array[MeshInstance3D] = []
var model: Node3D
var head: Node3D
var focus_collar: Node3D
var objective_carrier: Node3D
var lens_gimbal: Node3D
var objective_rest := Vector3.ZERO
var performance_preview := false
var material_preview := false
var iris_leaves: Array[Node3D] = []
var left_eye: Node3D
var right_eye: Node3D
var left_side_eye: Node3D
var right_side_eye: Node3D
var camera_hands: Array[Node3D] = []
var claw_closed := false
var claw_amount := 0.0
var claw_joints: Array[Node3D] = []
var claw_rest: Array[Basis] = []
var camera: Camera3D
var sweep: SpotLight3D
var reveal_fill: SpotLight3D
var rim: SpotLight3D
var inspection_light: DirectionalLight3D
var environment: Environment
var hud: Label
var materials := {}
var animatic := false
var arm_rigs: Array[Dictionary] = []
var blackout: ColorRect
var end_title: Label
var contact_camera := Vector3(.35,2.65,6.4)
var last_arm_error := 0.0
var stage_clay: StandardMaterial3D
var umbilical_material: ShaderMaterial

func _ready():
    DisplayServer.window_set_title("铁眼 · 深红揭示小样")
    get_window().size = Vector2i(1440,810)
    get_viewport().msaa_3d = Viewport.MSAA_4X
    build_materials()
    model = MODEL.instantiate()
    model.position.y = 3.7
    add_child(model)
    head = model.find_child("HeadPivot",true,false)
    focus_collar = model.find_child("FocusCollar",true,false)
    objective_carrier = model.find_child("ObjectiveCarrier",true,false)
    assert(objective_carrier != null)
    objective_rest = objective_carrier.position
    lens_gimbal = model.find_child("LensGimbal",true,false)
    assert(lens_gimbal != null)
    for i in range(9):iris_leaves.append(model.find_child("IrisLeaf%02d" % i,true,false))
    left_eye = model.find_child("LeftEye",true,false)
    right_eye = model.find_child("RightEye",true,false)
    left_side_eye = model.find_child("LeftSideEye",true,false)
    right_side_eye = model.find_child("RightSideEye",true,false)
    camera_hands = [left_eye,right_eye,left_side_eye,right_side_eye]
    for hand in camera_hands:assert(hand != null,"Missing camera-claw assembly")
    umbilical_material = ShaderMaterial.new()
    umbilical_material.shader = preload("res://presentation/scarlet/umbilical.gdshader")
    umbilical_material.set_shader_parameter("head_pivot_world",head.global_position)
    umbilical_material.set_shader_parameter("model_origin_y",model.global_position.y)
    for node in model.find_children("*Finger*","Node3D",true,false):
        var title := String(node.name)
        if title.ends_with("_Base") or title.ends_with("_Middle") or title.ends_with("_Tip"):
            claw_joints.append(node)
            claw_rest.append(node.basis)
    assert(claw_joints.size()==36,"Four three-finger camera claws need thirty-six joints")
    for title in ["ArmorShell"]:
        var part: Node3D = model.find_child(title,true,false)
        assert(part != null,"Missing continuous armor shell: "+title)
        armor_parts.append(part)
    for mesh in model.find_children("*","MeshInstance3D",true,false):
        var saved: Array[Material] = []
        for i in range(mesh.mesh.get_surface_count()):
            var original: Material = mesh.get_active_material(i)
            if materials.has(original.resource_name):
                var mat: Material = materials[original.resource_name]
                if original.resource_name == "LensMetal" and String(mesh.name).begins_with("Optics_"):
                    mat = mat.duplicate()
                    (mat as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
                if original.resource_name == "Rubber" and String(mesh.name).begins_with("Mount_"):
                    mat = umbilical_material
                if original.resource_name == "LensGlass":
                    mat = mat.duplicate()
                    mat.set_shader_parameter("lens_radius",.0833 if mesh.name.begins_with("Left") or mesh.name.begins_with("Right") else .699)
                mesh.set_surface_override_material(i,mat)
                if original.resource_name == "FrontGlass" or original.resource_name == "ObjectiveGlass":
                    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            saved.append(mesh.get_active_material(i))
        surface_materials[mesh] = saved
    clay_materials.armor = surface(Color(.55,.56,.57),.0,.78)
    clay_materials.body = surface(Color(.40,.42,.43),.0,.78)
    clay_materials.optics = surface(Color(.26,.28,.30),.0,.65)
    clay_materials.pupil = surface(Color(.012,.016,.020),0.0,.7)
    clay_materials.iris = surface(Color(.46,.48,.49),.35,.55)
    clay_materials.cable = surface(Color(.12,.14,.15),.0,.85)
    setup_arm_rigs()
    stage_clay = surface(Color(.065,.075,.085),0.0,.95)
    build_environment()
    build_lights()
    camera = Camera3D.new()
    add_child(camera)
    camera.fov = 40.0
    camera.near = .012
    camera.far = 60.0
    camera.current = true
    var layer := CanvasLayer.new()
    add_child(layer)
    hud = Label.new()
    hud.position = Vector2(28,26)
    hud.add_theme_font_override("font",preload("res://assets/fonts/fusion-pixel-12px-monospaced-zh_hans.otf"))
    hud.add_theme_font_size_override("font_size",24)
    hud.modulate = Color(.66,.70,.72,.7)
    layer.add_child(hud)
    var end_layer := CanvasLayer.new()
    end_layer.layer = 10
    add_child(end_layer)
    blackout = ColorRect.new()
    blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
    end_layer.add_child(blackout)
    end_title = Label.new()
    end_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    end_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    end_title.add_theme_font_override("font",preload("res://assets/fonts/fusion-pixel-12px-monospaced-zh_hans.otf"))
    end_title.add_theme_font_size_override("font_size",96)
    end_title.text = "铁眼"
    end_layer.add_child(end_title)
    performance_preview = "--performance" in OS.get_cmdline_user_args()
    material_preview = "--material" in OS.get_cmdline_user_args()
    animatic = (performance_preview or "--animatic" in OS.get_cmdline_user_args()) and not "--material" in OS.get_cmdline_user_args()
    if animatic or performance_preview or material_preview:hud.visible = false
    if "--inspect" in OS.get_cmdline_user_args():
        inspection = true
        paused = true
        clock = 8.8
        view_mode = 1
    if "--clay" in OS.get_cmdline_user_args():
        clay = true
        inspection = true
        paused = true
        clock = 8.8
        view_mode = 0
        get_window().content_scale_size = Vector2i(1440,1080)
        get_window().size = Vector2i(1440,1080)
    cache_arm_motion()
    apply_frame()
    print("SCARLET_READY | suspended original model | textured | bottom-to-top reveal")

func surface(color: Color, metallic: float, roughness: float, texture: Texture2D = null) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.metallic = metallic
    mat.roughness = roughness
    if texture:
        mat.albedo_texture = texture
        mat.uv1_triplanar = true
        mat.uv1_scale = Vector3.ONE * .85
        mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
        mat.normal_enabled = true
        mat.normal_texture = METAL_NORMAL
        mat.normal_scale = .10
        mat.roughness_texture = METAL_ROUGH
    return mat

func build_materials():
    materials.Paint = surface(Color(.46,.48,.47),.18,.85,PAINT)
    materials.DarkPaint = surface(Color(.18,.22,.23),.4,.82,PAINT)
    var sample_paint := ShaderMaterial.new()
    sample_paint.shader = preload("res://presentation/scarlet/sample_enamel.gdshader")
    sample_paint.set_shader_parameter("enamel_texture",PAINT)
    materials.SamplePaint = sample_paint
    materials.ArmorPaint = sample_paint
    materials.ArmorLiner = surface(Color(.026,.035,.040),.3,.68)
    materials.ArmorLiner.cull_mode = BaseMaterial3D.CULL_DISABLED
    materials.ScribeInk = surface(Color(.065,.080,.088),.0,.86)
    materials.ScribeInk.cull_mode = BaseMaterial3D.CULL_DISABLED
    materials.SampleDark = surface(Color(.065,.08,.085),.25,.66)
    materials.SampleRed = surface(Color(.22,.029,.019),.10,.67)
    materials.Stencil = surface(Color(.025,.033,.035),.0,.80)
    materials.Primer = surface(Color(.22,.24,.23),.30,.72)
    materials.Steel = surface(Color(.28,.31,.32),.85,.6,METAL_COLOR)
    materials.Steel.metallic_texture = METAL_METALLIC
    materials.Fasteners = surface(Color(.18,.20,.21),.85,.36,METAL_COLOR)
    materials.Rubber = surface(Color(.018,.023,.024),.0,.93)
    materials.Chrome = surface(Color(.61,.65,.69),.93,.21)
    materials.LensMetal = surface(Color(.075,.09,.095),.83,.29)
    materials.Pupil = surface(Color(.001,.002,.003),.0,.94)
    materials.Pupil.cull_mode = BaseMaterial3D.CULL_DISABLED
    materials.IrisBlade = surface(Color(.24,.26,.27),.65,.32)
    var objective := ShaderMaterial.new()
    objective.shader = preload("res://presentation/scarlet/objective_glass.gdshader")
    materials.ObjectiveGlass = objective
    materials.Ivory = surface(Color(.66,.59,.44),.0,.73)
    var glass := ShaderMaterial.new()
    glass.shader = GLASS
    materials.LensGlass = glass
    var cover := ShaderMaterial.new()
    cover.shader = preload("res://presentation/scarlet/cover_glass.gdshader")
    materials.FrontGlass = cover
    var sensor := surface(Color(.22,.006,.001),.2,.28)
    sensor.emission_enabled = true
    sensor.emission = Color(1,.035,.003)
    sensor.emission_energy_multiplier = 2.2
    materials.Sensor = sensor

func box(at: Vector3, size: Vector3, mat: Material):
    var mesh := MeshInstance3D.new()
    var geometry := BoxMesh.new()
    geometry.size = size
    mesh.mesh = geometry
    mesh.material_override = mat
    mesh.position = at
    add_child(mesh)
    mesh.set_meta("original_material",mat)
    stage_meshes.append(mesh)

func build_environment():
    environment = Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(.001,.0015,.002)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(.35,.43,.50)
    environment.ambient_light_energy = .055
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color(.018,.023,.03)
    sky_material.sky_horizon_color = Color(.16,.19,.22)
    sky_material.ground_horizon_color = Color(.12,.14,.16)
    sky_material.ground_bottom_color = Color(.005,.007,.01)
    var sky := Sky.new()
    sky.sky_material = sky_material
    environment.sky = sky
    environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment.ssao_enabled = true
    environment.ssao_radius = .35
    environment.ssao_intensity = 1.2
    environment.glow_enabled = true
    environment.glow_intensity = .36
    environment.glow_bloom = .03
    environment.volumetric_fog_enabled = true
    environment.volumetric_fog_density = .006
    environment.volumetric_fog_albedo = Color(.45,.52,.58)
    environment.volumetric_fog_length = 24.0
    var env := WorldEnvironment.new()
    env.environment = environment
    add_child(env)
    var wall := surface(Color(.026,.030,.035),.0,.95,METAL_COLOR)
    box(Vector3(0,4.5,-9.4),Vector3(40,30,.15),wall)
    box(Vector3(0,-.09,-.5),Vector3(40,.16,36),wall)
    # A few repeating architectural members provide scale, mostly in silhouette.
    for x in [-4.6,-2.3,2.3,4.6]:
        box(Vector3(x,3.3,-9.18),Vector3(.10,8,.16),wall)
    for y in [1.0,5.5,7.2]:
        box(Vector3(0,y,-9.12),Vector3(13,.16,.22),wall)
    for x in [-3.8,-3.65,3.7]:
        box(Vector3(x,3.5,-9.0),Vector3(.06,8,.08),wall)
    box(Vector3(0,8.4,-1.1),Vector3(8,.28,1.5),wall)

func spotlight(at: Vector3, energy: float, color: Color, angle: float) -> SpotLight3D:
    var light := SpotLight3D.new()
    add_child(light)
    light.position = at
    light.light_energy = energy
    light.light_color = color
    light.spot_range = 20
    light.spot_angle = angle
    light.spot_attenuation = .6
    light.spot_angle_attenuation = .7
    light.shadow_enabled = true
    light.shadow_bias = .015
    light.shadow_normal_bias = .25
    return light

func build_lights():
    sweep = spotlight(Vector3(-1.1,.8,4.8),11.0,Color(.81,.86,.91),42)
    var cookie := Image.create(256,256,false,Image.FORMAT_RGBA8)
    for y in range(256):
        for x in range(256):
            var xx := (float(x)/255.0-.5)*2.0
            var yy := (float(y)/255.0-.5)*2.0
            var value := exp(-pow(yy/.24,4))*smoothstep(1.0,.7,absf(xx))
            cookie.set_pixel(x,y,Color(value,value,value,1))
    sweep.light_projector = ImageTexture.create_from_image(cookie)
    reveal_fill = spotlight(Vector3(-1.5,.3,4.5),0,Color(.77,.82,.88),37)
    reveal_fill.look_at(Vector3(0,3.8,0))
    rim = spotlight(Vector3(2.8,6.1,-1.3),.7,Color(.47,.62,.82),49)
    rim.look_at(Vector3(0,3.7,.3))
    inspection_light = DirectionalLight3D.new()
    add_child(inspection_light)
    inspection_light.rotation_degrees = Vector3(-30,-28,0)
    inspection_light.light_energy = 1.15
    inspection_light.visible = false

func apply_frame():
    var t := fmod(clock,PERIOD)
    var material_study := material_preview and not animatic and not inspection
    var rise := smoothstep(.4,3.2,t)
    var fade := 1.0-smoothstep(9.70,9.85,t)
    camera.position = contact_camera
    camera.fov = 60.0
    # Attention is expressed inside the objective; the heavy housing remains still.
    head.rotation = Vector3.ZERO if inspection else Vector3(.16,.045,0)
    umbilical_material.set_shader_parameter("head_pitch",head.rotation.x)
    umbilical_material.set_shader_parameter("head_yaw",head.rotation.y)
    # Three intentional gaze targets, then a short servo correction into eye contact.
    var gaze := Vector2(-.06,-.17)
    gaze = gaze.lerp(Vector2(.045,-.09),dart(.42,.53,t))
    gaze = gaze.lerp(Vector2(-.018,.035),dart(.78,.88,t))
    gaze = gaze.lerp(Vector2.ZERO,dart(.98,1.05,t))
    lens_gimbal.rotation = Vector3.ZERO if inspection else Vector3(gaze.x,gaze.y,0)
    var search := dart(.80,.95,t)
    var correction := smoothstep(.98,1.05,t)
    var settle := smoothstep(1.10,1.18,t)
    objective_carrier.position = objective_rest+Vector3(0,0,0 if inspection else -.07+.17*search-.045*correction+.02*settle)
    focus_collar.rotation.z = 0.0 if inspection else .23*search-.055*correction+.02*settle
    var aperture := 0.0 if inspection else .08+.48*dart(.94,1.073333,t)-.035*settle
    for leaf in iris_leaves:leaf.rotation.z=aperture
    materials.ObjectiveGlass.set_shader_parameter("reflection_energy",.16 if inspection or material_study else .12*smoothstep(1.5,4.0,t)*fade)
    materials.FrontGlass.set_shader_parameter("reflection_energy",1.0 if inspection or material_study else smoothstep(.5,2.0,t)*fade)
    sweep.look_at(Vector3(0,lerpf(1.4,5.5,rise),.25))
    sweep.light_energy = 3.2*smoothstep(.2,1.1,t)*fade
    reveal_fill.light_energy = .65*smoothstep(1.0,3.4,t)*fade
    rim.light_energy = 2.5*smoothstep(.1,1.2,t)*fade
    if material_study:
        sweep.light_energy=0.0
        reveal_fill.position=Vector3(-3.8,4.6,4.5);reveal_fill.look_at(Vector3(0,3.5,.4));reveal_fill.light_energy=2.4
        rim.light_energy=2.0
    else:
        reveal_fill.position=Vector3(-1.5,.3,4.5);reveal_fill.look_at(Vector3(0,3.8,0))
    animate_arm_rigs(t)
    for i in range(claw_joints.size()):
        var title := String(claw_joints[i].name)
        var amount := claw_amount
        if not inspection:
            var motion_t := rhythm_clock(title.get_slice("_Finger",0),observation_time(t))
            var finger_offset := .12 if "Finger0" in title else (-.08 if "Finger2" in title else .0)
            if title.begins_with("LeftSideEye_"):
                amount = .67-.38*smoothstep(.1,1.3,motion_t)+.12*smoothstep(1.5,2.8,motion_t)
            elif title.begins_with("RightSideEye_"):
                amount = .60-.40*smoothstep(.25,2.3,motion_t)
            elif title.begins_with("LeftEye_"):
                amount = .25+.42*smoothstep(.1,2.6,motion_t)
            else:
                amount = .52-.42*smoothstep(.0,1.5,motion_t)+.18*smoothstep(1.6,2.8,motion_t)-.40*smoothstep(4.55,5.45,t)+.88*smoothstep(9.15,9.70,t)
            amount += finger_offset
        var angle := lerpf(.12,-.06,amount) if title.ends_with("_Base") else (lerpf(.07,-.035,amount) if title.ends_with("_Middle") else lerpf(.04,-.03,amount))
        claw_joints[i].basis = claw_rest[i] * Basis(Vector3.UP,angle)
    var cut := smoothstep(9.72,9.84,t) if not inspection else 0.0
    blackout.color = Color(0,0,0,cut)
    end_title.modulate = Color(1,1,1,smoothstep(10.50,11.20,t)*(1.0-smoothstep(13.8,14.4,t)) if not inspection else 0.0)
    var look_target := Vector3(0,3.30,0)
    if view_mode==1:camera.position = Vector3(5.2,4.2,6.5)
    elif view_mode==2:camera.position = Vector3(7.5,3.9,.10)
    elif view_mode==3:camera.position = Vector3(-4.5,4.2,-5.5)
    elif view_mode==4 or view_mode==6:
        var hand: Node3D = right_eye if view_mode==4 else right_side_eye
        camera.position = hand.global_position+hand.global_basis.z*2.7+Vector3(.60,.30,0)
        look_target = hand.global_position+hand.global_basis.z*.43
    elif view_mode==5:
        look_target = head.to_global(Vector3(2.98,.34,-.50)-head.position)
        camera.position = look_target+Vector3(2.6,.55,1.6)
    elif inspection:camera.position = Vector3(0,3.90,8.3)
    if inspection:camera.fov = 40.0
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL if clay else Camera3D.PROJECTION_PERSPECTIVE
    camera.size = 1.35 if view_mode==4 or view_mode==6 else (1.7 if view_mode==5 else 6.6)
    if inspection and not clay and view_mode<4:
        camera.position = look_target+(camera.position-look_target)*1.23
    camera.look_at(look_target)
    for part in armor_parts:part.visible = not armor_hidden
    for mesh in stage_meshes:
        mesh.visible = not inspection
        mesh.material_override = stage_clay if animatic or material_study else mesh.get_meta("original_material")
    inspection_light.visible = inspection or animatic or material_study
    environment.background_color = Color(.018,.022,.028) if material_study else (Color(.12,.14,.16) if animatic else (Color(.65,.67,.69) if clay else (Color(.038,.042,.047) if inspection else Color(.001,.0015,.002))))
    environment.ambient_light_color = Color(.8,.8,.8) if clay else Color(.35,.43,.50)
    environment.ambient_light_energy = .65 if inspection else (.32 if animatic else (.18 if material_study else .035))
    inspection_light.light_energy = .8 if inspection else (.60 if material_study else .55)
    environment.volumetric_fog_enabled = not inspection and not animatic and not material_study
    sweep.visible = not clay and not animatic
    reveal_fill.visible = not clay and not animatic
    rim.visible = not clay and not animatic
    var neutral := clay or animatic
    if neutral != clay_applied:
        for mesh in surface_materials:
            mesh.visible = not (neutral and ("FrontGlass" in String(mesh.name) or "ObjectiveGlass" in String(mesh.name)))
            for i in range(mesh.mesh.get_surface_count()):
                var category: String = "armor" if "Armor" in String(mesh.name) else ("optics" if "Optics" in String(mesh.name) or "Focus" in String(mesh.name) else "body")
                if String(mesh.name) in ["RearBody_Paint","RearBody_SamplePaint"]:
                    category = "armor"
                if "ArmorLiner" in String(mesh.name) or "ScribeInk" in String(mesh.name):
                    category = "optics"
                if "Stalks" in String(mesh.name):
                    category = "cable" if "Rubber" in String(mesh.name) else ("armor" if "Steel" in String(mesh.name) else "body")
                elif "Rubber" in String(mesh.name):
                    category = "cable"
                if "ObjectiveCarrier" in String(mesh.name) or "LensGimbal" in String(mesh.name):category="optics"
                if "IrisLeaf" in String(mesh.name):category="iris"
                if "_Pupil" in String(mesh.name) or "_LensGlass" in String(mesh.name):category="pupil"
                mesh.set_surface_override_material(i,clay_materials[category] if neutral else surface_materials[mesh][i])
        clay_applied = neutral
    hud.modulate = Color(.08,.09,.10,.85) if clay else Color(.66,.70,.72,.7)
    hud.text = "深红 · 四臂摄像头小样\nR 重播 · 空格 暂停 · I 明亮检查 · V 切换整体／爪部／底座视角\nC 四爪开合 · G 静态灰模 · B 动作灰模 · H 隐藏护罩 · F9 隐藏提示\n%.1f / %.0f 秒%s" % [t,PERIOD,"  暂停" if paused else ""]

func _process(delta: float):
    if not paused:
        clock += delta
        if performance_preview and clock>=3.0:clock=3.0;paused=true
    claw_amount = move_toward(claw_amount,1.0 if claw_closed else 0.0,delta*1.6)
    apply_frame()

func _unhandled_key_input(event: InputEvent):
    if not event.is_pressed() or event.is_echo():return
    match event.keycode:
        KEY_R:clock=0;paused=false;inspection=false;clay=false
        KEY_SPACE:paused=not paused
        KEY_I:inspection=not inspection
        KEY_G:clay=not clay;inspection=true;paused=true
        KEY_B:animatic=not animatic;clay=false;inspection=false;paused=false;clock=0
        KEY_C:claw_closed=not claw_closed
        KEY_V:view_mode=(view_mode+1)%7
        KEY_H:armor_hidden=not armor_hidden;inspection=true;paused=true
        KEY_LEFT:clock=maxf(0,clock-.5);paused=true
        KEY_RIGHT:clock+=.5;paused=true
        KEY_F9:hud.visible=not hud.visible
        KEY_ESCAPE:get_tree().quit()
    apply_frame()

func setup_arm_rigs():
    for skeleton: Skeleton3D in model.find_children("*","Skeleton3D",true,false):
        var label := String(skeleton.get_bone_name(0)).get_slice("_Station",0)
        var hand := model.find_child(label,true,false) as Node3D
        assert(hand != null,"Arm skeleton requires matching camera hand")
        var points: Array[Vector3] = []
        var rests: Array[Transform3D] = []
        var lengths: Array[float] = []
        for i in range(skeleton.get_bone_count()):
            var rest := skeleton.get_bone_global_rest(i)
            rests.append(rest)
            points.append(rest.origin)
            if i>0:lengths.append(points[i].distance_to(points[i-1]))
        arm_rigs.append({"skeleton":skeleton,"hand":hand,"label":label,"points":points,"rests":rests,"lengths":lengths})
    assert(arm_rigs.size()==4,"Four skinned arm assemblies required")

func solve_arm(points: Array[Vector3], lengths: Array[float], target: Vector3, reaching: bool, bend_offset := Vector3.ZERO, seed: Array[Vector3] = [], target_delta := Vector3.ZERO, bend_delta := Vector3.ZERO) -> Array[Vector3]:
    var solved: Array[Vector3] = points.duplicate() if seed.is_empty() else seed.duplicate()
    var last := points.size()-1
    var anchor := points[1]
    var offset := target-points[last]
    for i in range(2,points.size()):
        var u := float(i-1)/float(last-1)
        solved[i] += (offset if seed.is_empty() else target_delta)*pow(u,2.0)+(bend_offset if seed.is_empty() else bend_delta)*sin(PI*u)
    for iteration in range(180):
        solved[last] = target
        for i in range(last-1,0,-1):
            solved[i] = solved[i+1]+(solved[i]-solved[i+1]).normalized()*lengths[i]
        solved[1] = anchor
        for i in range(2,last+1):
            var proposed := solved[i]
            if reaching and i>2:
                # Reserve clearance around the pod for vertebra and cable radii.
                if proposed.x>1.55 and proposed.x<3.04 and proposed.y>-.76 and proposed.y<1.35 and proposed.z> -1.30 and proposed.z<.58:
                    var below := proposed.y+.76
                    var outside := 3.04-proposed.x
                    var ahead := .58-proposed.z
                    if below<outside and below<ahead:proposed.y=-.76
                    elif outside<ahead:proposed.x=3.04
                    else:proposed.z=.58
            var direction := (proposed-solved[i-1]).normalized()
            if points.size()>30:
                var incoming := (solved[i-1]-solved[i-2]).normalized()
                var bend := incoming.angle_to(direction)
                if bend>.58:direction=incoming.slerp(direction,.58/bend).normalized()
            solved[i] = solved[i-1]+direction*lengths[i-1]
        if iteration>40 and solved[last].distance_to(target)<.0003:break
    return solved

func arm_goal(rig: Dictionary,t: float) -> Dictionary:
    var label: String = rig.label
    var skeleton: Skeleton3D = rig.skeleton
    var points: Array[Vector3] = rig.points
    var authored := arm_track(label,rhythm_clock(label,observation_time(t)))
    var delayed := arm_track(label,rhythm_clock(label,observation_time(t-.10)))
    var target := points[-1]+authored
    var bend := Vector3(delayed.x*.45,delayed.y*.65,delayed.z*.38)
    # Other cameras keep making small, held changes of vantage during the examination.
    if label=="LeftSideEye":
        target += Vector3(.06,-.08,.08)*smoothstep(4.8,5.3,t)+Vector3(-.10,.05,.02)*smoothstep(6.9,7.45,t)+Vector3(.08,-.03,-.05)*smoothstep(8.7,9.3,t)
    elif label=="RightSideEye":
        target += Vector3(.12,-.06,-.08)*smoothstep(4.6,5.2,t)+Vector3(0,.09,.10)*smoothstep(6.1,6.6,t)+Vector3(-.08,.04,-.04)*smoothstep(7.8,8.2,t)
    elif label=="LeftEye":
        target += Vector3(-.10,.10,.16)*smoothstep(4.9,5.6,t)+Vector3(.08,-.04,.04)*smoothstep(7.2,7.8,t)
    elif t>=4.55:
        var forward := (Vector3(0,3.30,0)-contact_camera).normalized()
        var near := contact_camera+forward*1.35+Vector3(.18,-.10,0)
        var p0 := skeleton.to_global(points[-1]+arm_track(label,3.0))
        var world_target := p0.bezier_interpolate(p0+Vector3(.35,.20,1.0),near+Vector3(.40,-.05,-.65),near,smoothstep(4.55,6.55,t))
        # One leftward look, a hold, then a smaller rightward correction and another hold.
        world_target += Vector3(-.24,.08,.04)*smoothstep(6.90,7.25,t)
        world_target += Vector3(.34,-.04,.01)*smoothstep(7.65,8.05,t)
        if t>=8.55:
            var start := near+Vector3(.10,.04,.05)
            var contact := contact_camera+forward*.32+Vector3(.18,.10,0)
            world_target = start.bezier_interpolate(start+Vector3(.06,.08,.20),contact+Vector3(.12,.08,-.10),contact,smoothstep(8.55,9.70,t))
        target = skeleton.to_local(world_target)
    return {"target":target,"bend":bend}

func cache_arm_motion():
    # Solve chronologically once. Warm starting preserves the bend branch;
    # temporal transport preserves cable roll even as the tangent reverses.
    head.rotation = Vector3(.16,.045,0)
    for rig in arm_rigs:
        var previous: Array[Vector3] = []
        var previous_poses: Array[Transform3D] = []
        var old_target: Vector3 = rig.points[-1]
        var old_bend := Vector3.ZERO
        var frames: Array = []
        for frame in range(int(ARM_BAKE_DURATION*ARM_BAKE_FPS)+1):
            var goal := arm_goal(rig,float(frame)/ARM_BAKE_FPS)
            var solved := solve_arm(rig.points,rig.lengths,goal.target,rig.label=="RightEye",goal.bend,previous,goal.target-old_target,goal.bend-old_bend)
            var poses: Array[Transform3D] = []
            for i in range(solved.size()):
                var tangent := (solved[mini(i+1,solved.size()-1)]-solved[maxi(i-1,0)]).normalized()
                var prior: Basis = rig.rests[i].basis if previous_poses.is_empty() else previous_poses[i].basis
                var turn := Basis(Quaternion(prior.y.normalized(),tangent))
                poses.append(Transform3D((turn*prior).orthonormalized(),solved[i]))
            frames.append(poses)
            previous = solved;previous_poses = poses;old_target = goal.target;old_bend = goal.bend
        rig["motion_frames"] = frames
    print("ARM MOTION CACHED 120fps; continuous bend and roll")

func animate_arm_rigs(t: float):
    last_arm_error = 0.0
    for rig in arm_rigs:
        var skeleton: Skeleton3D = rig.skeleton
        var hand: Node3D = rig.hand
        var label: String = rig.label
        var poses: Array[Transform3D] = []
        var solved: Array[Vector3] = []
        var sample: float = clampf(t*ARM_BAKE_FPS,0.0,rig.motion_frames.size()-1)
        var index := int(sample)
        var next := mini(index+1,rig.motion_frames.size()-1)
        for i in range(rig.points.size()):
            var pose: Transform3D = rig.rests[i] if inspection else rig.motion_frames[index][i].interpolate_with(rig.motion_frames[next][i],sample-index)
            poses.append(pose);solved.append(pose.origin)
            var parent := skeleton.get_bone_parent(i)
            skeleton.set_bone_pose(i,poses[parent].affine_inverse()*pose if parent>=0 else pose)
        var target: Vector3 = rig.points[-1] if inspection else arm_goal(rig,t).target
        last_arm_error = maxf(last_arm_error,solved[-1].distance_to(target))
        hand.global_position = skeleton.to_global(solved[-1])
        var motion_t := rhythm_clock(label,observation_time(t))
        var notice := smoothstep(.75,1.42,motion_t) if label=="LeftSideEye" else (smoothstep(1.15,2.5,motion_t) if label=="RightSideEye" else (.55*smoothstep(.4,2.4,motion_t) if label=="LeftEye" else smoothstep(.8,2.5,motion_t)))
        if inspection:notice=0.0
        var sign_x := -1.0 if label.begins_with("Left") else 1.0
        var inward := Vector3(-sign_x*.48,-.20 if "SideEye" in label else .28,1.0).normalized()
        var rest_basis := head.global_basis*Basis.looking_at(inward,Vector3.UP,true)*Basis(Vector3.BACK,sign_x*.25)
        var gaze_target := contact_camera+Vector3(-.4,-.65,0) if label=="LeftEye" else contact_camera
        var aimed := Basis.looking_at((gaze_target-hand.global_position).normalized(),Vector3.UP,true)
        hand.global_basis = rest_basis.slerp(aimed,notice)
        if not inspection and label=="RightEye" and t>=4.55:
            var roll := -.075*smoothstep(6.90,7.25,t)+.13*smoothstep(7.65,8.05,t)
            roll *= 1.0-smoothstep(8.55,9.70,t)
            var forward := (Vector3(0,3.30,0)-contact_camera).normalized()
            var palm_cover := Basis.looking_at(-forward,Vector3.UP,true)
            hand.global_basis = (aimed*Basis(Vector3.BACK,roll)).slerp(palm_cover,smoothstep(8.55,9.70,t))
        rig["solved"] = solved
        rig["target"] = target

# Authored offsets are in the armature's model space. Tangents carry motion through
# the intermediate poses; the IK solver only enforces link lengths and attachment.
const ARM_POSE_TIMES = [0.0,.60,1.10,1.65,2.30,3.0]
const ARM_POSES = {
 "LeftSideEye": [Vector3(-.15,-.14,-.12),Vector3(-.42,.12,.08),Vector3(-.30,.30,.22),Vector3(.22,.38,.40),Vector3(.36,.50,.52),Vector3(.24,.42,.48)],
 "RightSideEye": [Vector3(.12,.18,-.08),Vector3(.38,.04,.06),Vector3(.42,-.16,.18),Vector3(.52,-.24,.25),Vector3(.48,-.32,.35),Vector3(.40,-.30,.38)],
 "LeftEye": [Vector3(.12,.12,-.20),Vector3(.34,.28,.10),Vector3(.38,.36,.30),Vector3(.20,.43,.65),Vector3(.05,.52,.82),Vector3(-.10,.58,.90)],
 "RightEye": [Vector3(-.12,.16,-.10),Vector3(-.32,.30,.15),Vector3(-.30,.45,.35),Vector3(-.20,.65,.70),Vector3(.10,.58,.82),Vector3(.28,.42,.62)]
}
func dart(start: float, end: float, t: float) -> float:
    return 1.0-pow(1.0-clampf((t-start)/(end-start),0.0,1.0),3.0)

func arm_track(label: String,t: float) -> Vector3:
    var values: Array = ARM_POSES[label]
    var k := 0
    while k<ARM_POSE_TIMES.size()-2 and t>ARM_POSE_TIMES[k+1]:k+=1
    var before := maxi(0,k-1)
    var after := mini(values.size()-1,k+2)
    var span: float = ARM_POSE_TIMES[k+1]-ARM_POSE_TIMES[k]
    var u: float = clampf((t-ARM_POSE_TIMES[k])/span,0.0,1.0)
    var m0: Vector3 = (values[k+1]-values[before])/(ARM_POSE_TIMES[k+1]-ARM_POSE_TIMES[before])*span
    var m1: Vector3 = (values[after]-values[k])/(ARM_POSE_TIMES[after]-ARM_POSE_TIMES[k])*span
    return values[k]*(2*u*u*u-3*u*u+1)+m0*(u*u*u-2*u*u+u)+values[k+1]*(-2*u*u*u+3*u*u)+m1*(u*u*u-u*u)

# A repeated phase value is an intentional observation hold, not an interpolation key.
const ARM_RHYTHMS = {
 "LeftSideEye": [Vector2(0,0),Vector2(.42,.6),Vector2(.80,.6),Vector2(1.17,1.65),Vector2(1.67,1.65),Vector2(2.30,3),Vector2(3,3)],
 "RightSideEye": [Vector2(0,0),Vector2(.18,0),Vector2(.82,.6),Vector2(1.30,.6),Vector2(2.0,2.3),Vector2(2.38,2.3),Vector2(3,3)],
 "LeftEye": [Vector2(0,0),Vector2(.60,.6),Vector2(1.15,.6),Vector2(1.80,1.65),Vector2(2.30,1.65),Vector2(3,3)],
 "RightEye": [Vector2(0,0),Vector2(.25,0),Vector2(.72,.6),Vector2(1.05,.6),Vector2(1.58,1.65),Vector2(2.05,1.65),Vector2(2.70,3),Vector2(3,3)]
}
func rhythm_clock(label: String,t: float) -> float:
    var keys: Array = ARM_RHYTHMS[label]
    for i in range(keys.size()-1):
        if t<=keys[i+1].x:
            var u: float = clampf((t-keys[i].x)/(keys[i+1].x-keys[i].x),0.0,1.0)
            # Zero velocity and acceleration on entry/exit to an observation hold.
            var eased: float = u*u*u*(10.0-15.0*u+6.0*u*u)
            return lerpf(keys[i].y,keys[i+1].y,eased)
    return keys[-1].y

func observation_time(t: float) -> float:
    return clampf(t-1.35,0.0,3.0)
