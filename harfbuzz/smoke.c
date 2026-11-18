#include <harfbuzz/hb.h>
#include <harfbuzz/hb-ot.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2 || strcmp(hb_version_string(), HB_VERSION_STRING) != 0) {
        fputs("Expected a font path and a library matching the packaged header\n", stderr);
        return 1;
    }
    hb_blob_t *blob = hb_blob_create_from_file_or_fail(argv[1]);
    if (!blob) {
        fputs("Could not load the Bengali shaping fixture\n", stderr);
        return 1;
    }
    hb_face_t *face = hb_face_create(blob, 0);
    hb_font_t *font = hb_font_create(face);
    hb_ot_font_set_funcs(font);

    // The first conjunct from upstream's ligature-id.tests.
    static const uint32_t text[] = {0x0995, 0x09cd, 0x0995};
    static const char *const shapers[] = {"ot", NULL};
    hb_buffer_t *buffer = hb_buffer_create();
    hb_buffer_set_direction(buffer, HB_DIRECTION_LTR);
    hb_buffer_set_script(buffer, HB_SCRIPT_BENGALI);
    hb_buffer_set_language(buffer, hb_language_from_string("bn", -1));
    hb_buffer_add_utf32(buffer, text, 3, 0, 3);
    hb_bool_t shaped = hb_shape_full(font, buffer, NULL, 0, shapers);
    unsigned count = 0;
    hb_glyph_info_t *glyphs = hb_buffer_get_glyph_infos(buffer, &count);
    hb_glyph_position_t *positions = hb_buffer_get_glyph_positions(buffer, NULL);
    char name[64];
    hb_bool_t ok = shaped && hb_buffer_allocation_successful(buffer) &&
        count == 1 && glyphs[0].cluster == 0 && positions && positions[0].x_advance == 566 &&
        hb_font_get_glyph_name(font, glyphs[0].codepoint, name, sizeof(name)) &&
        strcmp(name, "u0995_u09CD.half_u0995.pres") == 0;
    hb_buffer_destroy(buffer);
    hb_font_destroy(font);
    hb_face_destroy(face);
    hb_blob_destroy(blob);
    if (!ok) fputs("Unexpected OpenType shaping result for the Bengali conjunct\n", stderr);
    return ok ? 0 : 1;
}
