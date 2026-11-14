shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color = vec4(0.35, 0.53, 0.29, 1.0);
void vertex() {
    float top = max(VERTEX.y, 0.0);
    VERTEX.x += sin(TIME * 1.6 + MODEL_MATRIX[3].x * 0.55 + MODEL_MATRIX[3].z * 0.35) * top * 0.2;
    VERTEX.z += cos(TIME * 1.1 + MODEL_MATRIX[3].z * 0.4) * top * 0.11;
}
void fragment() { ALBEDO = tint.rgb; ROUGHNESS = 1.0; }
