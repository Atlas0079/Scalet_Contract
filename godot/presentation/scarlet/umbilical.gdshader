shader_type spatial;
uniform float head_pitch = 0.0;
uniform float head_yaw = 0.0;
uniform vec3 head_pivot_world = vec3(0.0, 3.9, -0.98);
uniform float model_origin_y = 3.7;
void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float follow = 1.0 - smoothstep(1.5, 2.8, world.y - model_origin_y);
    float angle = head_pitch * follow;
    float c = cos(angle);
    float s = sin(angle);
    mat3 rotation = mat3(vec3(1,0,0), vec3(0,c,s), vec3(0,-s,c));
    float yaw = head_yaw * follow;
    mat3 turn = mat3(vec3(cos(yaw),0,-sin(yaw)),vec3(0,1,0),vec3(sin(yaw),0,cos(yaw)));
    rotation = turn * rotation;
    world = head_pivot_world + rotation * (world - head_pivot_world);
    VERTEX = (inverse(MODEL_MATRIX) * vec4(world,1.0)).xyz;
    NORMAL = normalize(inverse(mat3(MODEL_MATRIX)) * rotation * mat3(MODEL_MATRIX) * NORMAL);
}
void fragment() {
    ALBEDO = vec3(.018,.023,.024);
    ROUGHNESS = .93;
}
