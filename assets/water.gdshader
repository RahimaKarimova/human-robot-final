shader_type spatial;
varying vec3 world;
void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    float band = sin(world.x * 0.23 + world.z * 0.4 + TIME * 0.6);
    float detail = sin(world.x * 0.65 - world.z * 0.2 - TIME * 0.5);
    float coast = 1.0 - smoothstep(39.0, 68.0, length(vec2(world.x, (world.z + 5.0) / 1.15)));
    ALBEDO = mix(vec3(0.09, 0.29, 0.43), vec3(0.19, 0.58, 0.59), coast);
    ALBEDO += smoothstep(0.94, 1.0, band * 0.7 + detail * 0.3) * 0.12;
    ROUGHNESS = 0.25;
    METALLIC = 0.15;
}
