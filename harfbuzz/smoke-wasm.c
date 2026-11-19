#include <harfbuzz/hb.h>
#include <harfbuzz/hb-features.h>
#include <harfbuzz/hb-ot.h>

int shape_bengali(const char *font_bytes, unsigned font_length) {
    unsigned major, minor, micro;
    hb_version(&major, &minor, &micro);
    if (major != HB_VERSION_MAJOR || minor != HB_VERSION_MINOR || micro != HB_VERSION_MICRO)
        return 0;

    hb_blob_t *blob = hb_blob_create(font_bytes, font_length, HB_MEMORY_MODE_READONLY, 0, 0);
    hb_face_t *face = hb_face_create(blob, 0);
    hb_font_t *font = hb_font_create(face);
    hb_ot_font_set_funcs(font);

    // Same pinned Bengali ligature fixture and expected advance as smoke.c.
    static const uint32_t text[] = {0x0995, 0x09cd, 0x0995};
    hb_buffer_t *buffer = hb_buffer_create();
    hb_buffer_set_direction(buffer, HB_DIRECTION_LTR);
    hb_buffer_set_script(buffer, HB_SCRIPT_BENGALI);
    hb_buffer_set_language(buffer, hb_language_from_string("bn", -1));
    hb_buffer_add_utf32(buffer, text, 3, 0, 3);
    hb_shape(font, buffer, 0, 0);

    unsigned count = 0;
    const hb_glyph_info_t *glyphs = hb_buffer_get_glyph_infos(buffer, &count);
    const hb_glyph_position_t *positions = hb_buffer_get_glyph_positions(buffer, 0);
    int ok = hb_buffer_allocation_successful(buffer) && count == 1 && glyphs &&
        glyphs[0].codepoint != 0 && glyphs[0].cluster == 0 && positions &&
        positions[0].x_advance == 566;

    hb_buffer_destroy(buffer);
    hb_font_destroy(font);
    hb_face_destroy(face);
    hb_blob_destroy(blob);
    return ok;
}
