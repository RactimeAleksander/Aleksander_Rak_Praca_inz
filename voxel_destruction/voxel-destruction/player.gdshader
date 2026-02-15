shader_type canvas_item;

// Pobiera obraz tego, co jest pod spodem
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
    // Odczytujemy kolor z ekranu w miejscu, gdzie jest pixel celownika
    vec4 screen_color = texture(screen_texture, SCREEN_UV);
    // Odwracamy kolory (1.0 - kolor)
    COLOR = vec4(1.0 - screen_color.rgb, 1.0);
}