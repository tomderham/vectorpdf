//
// VectorPDF
// Copyright (c) 2026 Thomas Derham
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// This application links to and incorporates the MuPDF framework, which is
// Copyright (c) 2006-2026 Artifex Software, Inc.
//
// VECTORPDF IS PROVIDED "AS IS" WITHOUT ANY WARRANTY, AND ALL
// WARRANTIES, WHETHER EXPRESSED OR IMPLIED, INCLUDING WARRANTY OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, ARE DISCLAIMED.
//

// Recognized (OCR) text written into a scanned page as invisible text (render mode 3), so other
// apps can search, select and copy it. As Tesseract and MuPDF's PDFOCR writer do: a "glyphless"
// Type 0 font whose every code is a blank glyph half an em wide, coded as UTF-16 with an identity
// ToUnicode map, and each word stretched (Tz) over the box it was recognized in.

#include "MuPDFBridge.h"
#include <math.h>
#include <string.h>

// The glyphless TrueType font from MuPDF's source/fitz/output-pdfocr.c (originally Tesseract's
// pdf.ttf): one empty glyph, 500 units wide on a 1000-unit em.
static const unsigned char glyphless_ttf[572] = {
    0x00,0x01,0x00,0x00,0x00,0x0a,0x00,0x80,0x00,0x03,0x00,0x20,0x4f,0x53,0x2f,0x32,
    0x56,0xde,0xc8,0x94,0x00,0x00,0x01,0x28,0x00,0x00,0x00,0x60,0x63,0x6d,0x61,0x70,
    0x00,0x0a,0x00,0x34,0x00,0x00,0x01,0x90,0x00,0x00,0x00,0x1e,0x67,0x6c,0x79,0x66,
    0x15,0x22,0x41,0x24,0x00,0x00,0x01,0xb8,0x00,0x00,0x00,0x18,0x68,0x65,0x61,0x64,
    0x0b,0x78,0xf1,0x65,0x00,0x00,0x00,0xac,0x00,0x00,0x00,0x36,0x68,0x68,0x65,0x61,
    0x0c,0x02,0x04,0x02,0x00,0x00,0x00,0xe4,0x00,0x00,0x00,0x24,0x68,0x6d,0x74,0x78,
    0x04,0x00,0x00,0x00,0x00,0x00,0x01,0x88,0x00,0x00,0x00,0x08,0x6c,0x6f,0x63,0x61,
    0x00,0x0c,0x00,0x00,0x00,0x00,0x01,0xb0,0x00,0x00,0x00,0x06,0x6d,0x61,0x78,0x70,
    0x00,0x04,0x00,0x05,0x00,0x00,0x01,0x08,0x00,0x00,0x00,0x20,0x6e,0x61,0x6d,0x65,
    0xf2,0xeb,0x16,0xda,0x00,0x00,0x01,0xd0,0x00,0x00,0x00,0x4b,0x70,0x6f,0x73,0x74,
    0x00,0x01,0x00,0x01,0x00,0x00,0x02,0x1c,0x00,0x00,0x00,0x20,0x00,0x01,0x00,0x00,
    0x00,0x01,0x00,0x00,0xb0,0x94,0x71,0x10,0x5f,0x0f,0x3c,0xf5,0x04,0x07,0x08,0x00,
    0x00,0x00,0x00,0x00,0xcf,0x9a,0xfc,0x6e,0x00,0x00,0x00,0x00,0xd4,0xc3,0xa7,0xf2,
    0x00,0x00,0x00,0x00,0x04,0x00,0x08,0x00,0x00,0x00,0x00,0x10,0x00,0x02,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x01,0x00,0x00,0x08,0x00,0xff,0xff,0x00,0x00,0x04,0x00,
    0x00,0x00,0x00,0x00,0x04,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x02,0x00,0x01,0x00,0x00,0x00,0x02,0x00,0x04,
    0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x03,0x00,0x00,0x01,0x90,0x00,0x05,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x05,0x00,0x01,0x00,0x01,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x47,0x4f,0x4f,0x47,0x00,0x40,0x00,0x00,0x00,0x00,0x00,0x01,0xff,0xff,
    0x00,0x00,0x00,0x01,0x00,0x01,0x80,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x04,0x00,0x00,0x00,
    0x00,0x00,0x00,0x02,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x14,0x00,0x03,0x00,0x00,
    0x00,0x00,0x00,0x14,0x00,0x06,0x00,0x0a,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x0c,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x04,0x00,
    0x08,0x00,0x00,0x03,0x00,0x00,0x31,0x21,0x11,0x21,0x04,0x00,0xfc,0x00,0x08,0x00,
    0x00,0x00,0x00,0x03,0x00,0x2a,0x00,0x00,0x00,0x03,0x00,0x00,0x00,0x05,0x00,0x16,
    0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x05,0x00,0x0b,0x00,0x16,0x00,0x03,
    0x00,0x01,0x04,0x09,0x00,0x05,0x00,0x16,0x00,0x00,0x00,0x56,0x00,0x65,0x00,0x72,
    0x00,0x73,0x00,0x69,0x00,0x6f,0x00,0x6e,0x00,0x20,0x00,0x31,0x00,0x2e,0x00,0x30,
    0x56,0x65,0x72,0x73,0x69,0x6f,0x6e,0x20,0x31,0x2e,0x30,0x00,0x00,0x01,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
};

static const char identity_to_unicode[] =
    "/CIDInit /ProcSet findresource begin\n"
    "12 dict begin\n"
    "begincmap\n"
    "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n"
    "/CMapName /Adobe-Identity-UCS def\n"
    "/CMapType 2 def\n"
    "1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n"
    "1 beginbfrange\n<0000> <FFFF> <0000>\nendbfrange\n"
    "endcmap\n"
    "CMapName currentdict /CMap defineresource pop\n"
    "end\n"
    "end\n";

// The font's name in each page's /Font resources.
#define OCR_FONT_KEY "VPOCRText"

/* Adds `buf` as a Flate-compressed stream (saves don't compress streams by default). */
static pdf_obj *add_compressed_stream(fz_context *ctx, pdf_document *doc, fz_buffer *buf) {
    unsigned char *data = NULL;
    size_t len = 0;
    fz_buffer *compressed = NULL;
    pdf_obj *dict = NULL, *stream = NULL;
    fz_var(data); fz_var(compressed); fz_var(dict);
    fz_try(ctx) {
        unsigned char *source;
        size_t source_len = fz_buffer_storage(ctx, buf, &source);
        data = fz_new_deflated_data(ctx, &len, source, source_len, FZ_DEFLATE_DEFAULT);
        compressed = fz_new_buffer_from_data(ctx, data, len);
        data = NULL;
        dict = pdf_new_dict(ctx, doc, 1);
        pdf_dict_put(ctx, dict, PDF_NAME(Filter), PDF_NAME(FlateDecode));
        stream = pdf_add_stream(ctx, doc, compressed, dict, 1);
    } fz_always(ctx) {
        fz_free(ctx, data);
        fz_drop_buffer(ctx, compressed);
        pdf_drop_obj(ctx, dict);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
    return stream;
}

/* Adds the glyphless font to the document and returns it (an indirect reference to drop). */
static pdf_obj *add_glyphless_font(fz_context *ctx, pdf_document *doc) {
    fz_buffer *buf = NULL;
    pdf_obj *font_file = NULL, *descriptor = NULL, *cid_to_gid = NULL, *to_unicode = NULL;
    pdf_obj *cid_font = NULL, *font = NULL, *dict = NULL;
    fz_var(buf); fz_var(font_file); fz_var(descriptor); fz_var(cid_to_gid);
    fz_var(to_unicode); fz_var(cid_font); fz_var(font); fz_var(dict);
    fz_try(ctx) {
        buf = fz_new_buffer_from_copied_data(ctx, glyphless_ttf, sizeof glyphless_ttf);
        dict = pdf_new_dict(ctx, doc, 1);
        pdf_dict_put_int(ctx, dict, PDF_NAME(Length1), sizeof glyphless_ttf);
        font_file = pdf_add_stream(ctx, doc, buf, dict, 0);
        pdf_drop_obj(ctx, dict); dict = NULL;
        fz_drop_buffer(ctx, buf); buf = NULL;

        dict = pdf_new_dict(ctx, doc, 10);
        pdf_dict_put(ctx, dict, PDF_NAME(Type), PDF_NAME(FontDescriptor));
        pdf_dict_put_name(ctx, dict, PDF_NAME(FontName), "GlyphLessFont");
        pdf_dict_put_int(ctx, dict, PDF_NAME(Flags), 5);
        pdf_dict_put_rect(ctx, dict, PDF_NAME(FontBBox), fz_make_rect(0, 0, 500, 1000));
        pdf_dict_put_int(ctx, dict, PDF_NAME(ItalicAngle), 0);
        pdf_dict_put_int(ctx, dict, PDF_NAME(Ascent), 1000);
        pdf_dict_put_int(ctx, dict, PDF_NAME(Descent), -1);
        pdf_dict_put_int(ctx, dict, PDF_NAME(CapHeight), 1000);
        pdf_dict_put_int(ctx, dict, PDF_NAME(StemV), 80);
        pdf_dict_put(ctx, dict, PDF_NAME(FontFile2), font_file);
        descriptor = pdf_add_object(ctx, doc, dict);
        pdf_drop_obj(ctx, dict); dict = NULL;

        // Every code draws glyph 1, the font's blank glyph.
        buf = fz_new_buffer(ctx, 2 * 65536);
        for (int i = 0; i < 65536; i++) {
            fz_append_byte(ctx, buf, 0);
            fz_append_byte(ctx, buf, 1);
        }
        cid_to_gid = add_compressed_stream(ctx, doc, buf);
        fz_drop_buffer(ctx, buf); buf = NULL;

        buf = fz_new_buffer_from_copied_data(ctx, (const unsigned char *)identity_to_unicode, strlen(identity_to_unicode));
        to_unicode = pdf_add_stream(ctx, doc, buf, NULL, 0);
        fz_drop_buffer(ctx, buf); buf = NULL;

        dict = pdf_new_dict(ctx, doc, 8);
        pdf_dict_put(ctx, dict, PDF_NAME(Type), PDF_NAME(Font));
        pdf_dict_put(ctx, dict, PDF_NAME(Subtype), PDF_NAME(CIDFontType2));
        pdf_dict_put_name(ctx, dict, PDF_NAME(BaseFont), "GlyphLessFont");
        pdf_obj *info = pdf_dict_put_dict(ctx, dict, PDF_NAME(CIDSystemInfo), 3);
        pdf_dict_put_string(ctx, info, PDF_NAME(Registry), "Adobe", 5);
        pdf_dict_put_string(ctx, info, PDF_NAME(Ordering), "Identity", 8);
        pdf_dict_put_int(ctx, info, PDF_NAME(Supplement), 0);
        pdf_dict_put(ctx, dict, PDF_NAME(FontDescriptor), descriptor);
        pdf_dict_put_int(ctx, dict, PDF_NAME(DW), 500);
        pdf_dict_put(ctx, dict, PDF_NAME(CIDToGIDMap), cid_to_gid);
        cid_font = pdf_add_object(ctx, doc, dict);
        pdf_drop_obj(ctx, dict); dict = NULL;

        dict = pdf_new_dict(ctx, doc, 6);
        pdf_dict_put(ctx, dict, PDF_NAME(Type), PDF_NAME(Font));
        pdf_dict_put(ctx, dict, PDF_NAME(Subtype), PDF_NAME(Type0));
        pdf_dict_put_name(ctx, dict, PDF_NAME(BaseFont), "GlyphLessFont");
        pdf_dict_put(ctx, dict, PDF_NAME(Encoding), PDF_NAME(Identity_H));
        pdf_obj *descendants = pdf_dict_put_array(ctx, dict, PDF_NAME(DescendantFonts), 1);
        pdf_array_push(ctx, descendants, cid_font);
        pdf_dict_put(ctx, dict, PDF_NAME(ToUnicode), to_unicode);
        font = pdf_add_object(ctx, doc, dict);
    } fz_always(ctx) {
        fz_drop_buffer(ctx, buf);
        pdf_drop_obj(ctx, dict);
        pdf_drop_obj(ctx, font_file);
        pdf_drop_obj(ctx, descriptor);
        pdf_drop_obj(ctx, cid_to_gid);
        pdf_drop_obj(ctx, to_unicode);
        pdf_drop_obj(ctx, cid_font);
    } fz_catch(ctx) {
        pdf_drop_obj(ctx, font);
        fz_rethrow(ctx);
    }
    return font;
}

/* The page's own /Font resources, made so that adding to them changes no other page: inherited
   or shared dictionaries are copied onto the page first. */
static pdf_obj *own_font_resources(fz_context *ctx, pdf_document *doc, pdf_obj *page_obj) {
    pdf_obj *resources = pdf_dict_get(ctx, page_obj, PDF_NAME(Resources));
    if (!resources || pdf_is_indirect(ctx, resources)) {
        pdf_obj *inherited = resources ? resources : pdf_dict_get_inheritable(ctx, page_obj, PDF_NAME(Resources));
        pdf_obj *copy = inherited ? pdf_copy_dict(ctx, inherited) : pdf_new_dict(ctx, doc, 2);
        pdf_dict_put_drop(ctx, page_obj, PDF_NAME(Resources), copy);
        resources = copy;
    }
    pdf_obj *fonts = pdf_dict_get(ctx, resources, PDF_NAME(Font));
    if (!fonts) {
        fonts = pdf_dict_put_dict(ctx, resources, PDF_NAME(Font), 1);
    } else if (pdf_is_indirect(ctx, fonts)) {
        pdf_obj *copy = pdf_copy_dict(ctx, fonts);
        pdf_dict_put_drop(ctx, resources, PDF_NAME(Font), copy);
        fonts = copy;
    }
    return fonts;
}

/* Appends `text` as UTF-16 code units in hex, returning how many units. */
static int append_utf16_hex(fz_context *ctx, fz_buffer *buf, const char *text) {
    int units = 0;
    while (*text) {
        int c;
        text += fz_chartorune(&c, text);
        if (c < 0 || c == 0xFFFD) c = 0xFFFD;
        if (c > 0xFFFF) {
            c -= 0x10000;
            fz_append_printf(ctx, buf, "%04x%04x", 0xD800 + (c >> 10), 0xDC00 + (c & 0x3FF));
            units += 2;
        } else {
            fz_append_printf(ctx, buf, "%04x", c);
            units += 1;
        }
    }
    return units;
}

static int utf16_length(const char *text) {
    int units = 0;
    while (*text) {
        int c;
        text += fz_chartorune(&c, text);
        units += c > 0xFFFF ? 2 : 1;
    }
    return units;
}

/* Adds a content stream to the page, after its own contents, which are put inside q/Q first so
   whatever graphics state they leave doesn't apply to it. */
static void append_page_contents(fz_context *ctx, pdf_document *doc, pdf_obj *page_obj, fz_buffer *ours) {
    pdf_obj *existing = pdf_dict_get(ctx, page_obj, PDF_NAME(Contents));
    pdf_obj *list = NULL, *before = NULL, *after = NULL;
    fz_buffer *q = NULL, *tail = NULL;
    fz_var(list); fz_var(before); fz_var(after); fz_var(q); fz_var(tail);
    fz_try(ctx) {
        list = pdf_new_array(ctx, doc, 4);
        if (existing) {
            q = fz_new_buffer_from_copied_data(ctx, (const unsigned char *)"q\n", 2);
            before = pdf_add_stream(ctx, doc, q, NULL, 0);
            pdf_array_push(ctx, list, before);
            if (pdf_is_array(ctx, existing)) {
                int n = pdf_array_len(ctx, existing);
                for (int i = 0; i < n; i++) pdf_array_push(ctx, list, pdf_array_get(ctx, existing, i));
            } else {
                pdf_array_push(ctx, list, existing);
            }
            tail = fz_new_buffer(ctx, fz_buffer_storage(ctx, ours, NULL) + 4);
            fz_append_string(ctx, tail, "\nQ\n");
            fz_append_buffer(ctx, tail, ours);
            after = add_compressed_stream(ctx, doc, tail);
        } else {
            after = add_compressed_stream(ctx, doc, ours);
        }
        pdf_array_push(ctx, list, after);
        pdf_dict_put(ctx, page_obj, PDF_NAME(Contents), list);
    } fz_always(ctx) {
        fz_drop_buffer(ctx, q);
        fz_drop_buffer(ctx, tail);
        pdf_drop_obj(ctx, before);
        pdf_drop_obj(ctx, after);
        pdf_drop_obj(ctx, list);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
}

int mupdf_pdf_add_ocr_text(fz_context *ctx, fz_document *doc, int pageno, const mupdf_ocr_word *words, int count, int *font_num, const char **out_error) {
    if (!ctx || !doc || (!words && count > 0) || !font_num) {
        if (out_error) *out_error = "Invalid parameters";
        return -1;
    }
    if (count == 0) return 0;
    pdf_page *page = NULL;
    pdf_obj *font = NULL;
    fz_buffer *buf = NULL;
    fz_var(page); fz_var(font); fz_var(buf);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        page = pdf_load_page(ctx, pdoc, pageno);

        if (*font_num > 0) {
            font = pdf_new_indirect(ctx, pdoc, *font_num, 0);
        } else {
            font = add_glyphless_font(ctx, pdoc);
            *font_num = pdf_to_num(ctx, font);
        }

        // Words are in page space; the content stream is in the page's user space.
        fz_matrix ctm;
        pdf_page_transform(ctx, page, NULL, &ctm);
        fz_matrix to_user = fz_invert_matrix(ctm);

        buf = fz_new_buffer(ctx, 64 + count * 64);
        fz_append_string(ctx, buf, "BT\n3 Tr\n");
        int written = 0;
        for (int i = 0; i < count; i++) {
            const mupdf_ocr_word *w = &words[i];
            if (!w->text || !*w->text) continue;
            fz_point ll = fz_transform_point(fz_make_point(w->llx, w->lly), to_user);
            fz_point lr = fz_transform_point(fz_make_point(w->lrx, w->lry), to_user);
            fz_point ul = fz_transform_point(fz_make_point(w->ulx, w->uly), to_user);
            float bx = lr.x - ll.x, by = lr.y - ll.y;
            float width = sqrtf(bx * bx + by * by);
            if (width < 0.01f) continue;
            float ux = bx / width, uy = by / width;
            // Height across the baseline, upward (a quarter turn anticlockwise from it).
            float size = (ul.x - ll.x) * -uy + (ul.y - ll.y) * ux;
            if (size < 0.5f) continue;
            int units = utf16_length(w->text);
            if (units == 0) continue;
            // Each code is half an em wide: stretch them so the word spans its box.
            float scale = width / (units * 0.5f * size) * 100.0f;
            fz_append_printf(ctx, buf, "/" OCR_FONT_KEY " %g Tf %g Tz %g %g %g %g %g %g Tm <",
                size, scale, ux, uy, -uy, ux, ll.x, ll.y);
            append_utf16_hex(ctx, buf, w->text);
            fz_append_string(ctx, buf, "> Tj\n");
            written++;
        }
        fz_append_string(ctx, buf, "ET\n");

        if (written > 0) {
            pdf_obj *fonts = own_font_resources(ctx, pdoc, page->obj);
            pdf_dict_puts(ctx, fonts, OCR_FONT_KEY, font);
            append_page_contents(ctx, pdoc, page->obj, buf);
        }
    } fz_always(ctx) {
        fz_drop_buffer(ctx, buf);
        pdf_drop_obj(ctx, font);
        if (page) fz_drop_page(ctx, (fz_page *)page);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}
