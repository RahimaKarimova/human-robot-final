shader_type spatial;
render_mode diffuse_burley;
varying vec3 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
    vec2 cell = floor(world.xz * 1.2);
    float n = hash(cell);
    float patch = sin(world.x * 0.19) * cos(world.z * 0.24) * 0.5 + 0.5;
    ALBEDO = mix(vec3(0.23, 0.40, 0.29), vec3(0.42, 0.57, 0.31), patch) + (n - 0.5) * 0.018;
    ROUGHNESS = 0.95;
}
