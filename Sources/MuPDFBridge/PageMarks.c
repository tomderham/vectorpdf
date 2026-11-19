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

// Headers, footers (with page and Bates numbers) and watermarks, drawn into pages so that they
// can be changed or taken off again: each is a content stream of its own, added to the page's
// /Contents and tagged /VPPageMark, so removing it is dropping those streams. What's drawn is
// marked as a pagination artifact (/Artifact << /Type /Pagination /Subtype /Header >>), as
// Acrobat marks its own, so screen readers and tagged-PDF tools leave it out of the text.

#include "MuPDFBridge.h"
#include <math.h>
#include <string.h>
#include <time.h>

static const char *font_names[] = { "Helvetica", "Times-Roman", "Courier", "Helvetica-Bold" };
static const char *font_keys[] = { "VPMarkF0", "VPMarkF1", "VPMarkF2", "VPMarkF3" };

static int clamp_font(int font) {
    return font >= 0 && font < (int)(sizeof font_names / sizeof *font_names) ? font : 0;
}

// The page's own resources, made if it inherits them or has none, so adding to them changes only
// pages that share them.
static pdf_obj *own_resources(fz_context *ctx, pdf_document *doc, pdf_obj *page) {
    pdf_obj *res = pdf_dict_get(ctx, page, PDF_NAME(Resources));
    if (res) return res;
    pdf_obj *inherited = pdf_dict_get_inheritable(ctx, page, PDF_NAME(Resources));
    res = inherited ? pdf_copy_dict(ctx, inherited) : pdf_new_dict(ctx, doc, 2);
    pdf_dict_put_drop(ctx, page, PDF_NAME(Resources), res);
    return res;
}

static pdf_obj *resource_dict(fz_context *ctx, pdf_document *doc, pdf_obj *res, pdf_obj *name) {
    pdf_obj *dict = pdf_dict_get(ctx, res, name);
    if (!pdf_is_dict(ctx, dict)) {
        dict = pdf_new_dict(ctx, doc, 2);
        pdf_dict_put_drop(ctx, res, name, dict);
    }
    return dict;
}

static void add_font_resource(fz_context *ctx, pdf_document *doc, pdf_obj *res, int font) {
    pdf_obj *fonts = resource_dict(ctx, doc, res, PDF_NAME(Font));
    if (pdf_dict_gets(ctx, fonts, font_keys[font])) return;
    pdf_obj *dict = pdf_new_dict(ctx, doc, 4);
    fz_try(ctx) {
        pdf_dict_put(ctx, dict, PDF_NAME(Type), PDF_NAME(Font));
        pdf_dict_put(ctx, dict, PDF_NAME(Subtype), PDF_NAME(Type1));
        pdf_dict_put_name(ctx, dict, PDF_NAME(BaseFont), font_names[font]);
        pdf_dict_put(ctx, dict, PDF_NAME(Encoding), PDF_NAME(WinAnsiEncoding));
        pdf_dict_puts_drop(ctx, fonts, font_keys[font], pdf_add_object(ctx, doc, dict));
    } fz_always(ctx) {
        pdf_drop_obj(ctx, dict);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
}

// The text in Windows-1252 (the font's encoding), characters it lacks as '?'.
static void append_text_string(fz_context *ctx, fz_buffer *buf, const char *utf8) {
    fz_append_byte(ctx, buf, '(');
    while (*utf8) {
        int rune;
        utf8 += fz_chartorune(&rune, utf8);
        int c = fz_windows_1252_from_unicode(rune);
        if (c < 0) c = '?';
        if (c == '(' || c == ')' || c == '\\') fz_append_byte(ctx, buf, '\\');
        if (c < 32) c = ' ';
        fz_append_byte(ctx, buf, c);
    }
    fz_append_byte(ctx, buf, ')');
}

// Width of the text at size 1, as the standard font draws it.
static float text_width(fz_context *ctx, fz_font *font, const char *utf8) {
    float width = 0;
    while (*utf8) {
        int rune;
        utf8 += fz_chartorune(&rune, utf8);
        int c = fz_windows_1252_from_unicode(rune);
        if (c < 0) c = '?';
        int unicode = c < 256 ? fz_unicode_from_windows_1252[c] : c;
        width += fz_advance_glyph(ctx, font, fz_encode_character(ctx, font, unicode), 0);
    }
    return width;
}

// The matrix from a drawing space the size of the page as shown (bottom-up, origin bottom left,
// whatever the page's rotation and crop) to the page's own space, and that size.
static fz_matrix shown_page_space(fz_context *ctx, pdf_page *page, float *width, float *height) {
    fz_rect mediabox;
    fz_matrix ctm;
    pdf_page_transform(ctx, page, &mediabox, &ctm);
    fz_rect shown = fz_transform_rect(mediabox, ctm);
    *width = shown.x1 - shown.x0;
    *height = shown.y1 - shown.y0;
    // Shown space is top-down from the box's corner; turn it up and move it to the origin.
    fz_matrix flip = fz_make_matrix(1, 0, 0, -1, shown.x0, shown.y1);
    return fz_concat(flip, fz_invert_matrix(ctm));
}

static void append_matrix(fz_context *ctx, fz_buffer *buf, fz_matrix m) {
    fz_append_printf(ctx, buf, "%g %g %g %g %g %g cm\n", m.a, m.b, m.c, m.d, m.e, m.f);
}

static pdf_obj *new_mark_stream(fz_context *ctx, pdf_document *doc, fz_buffer *buf, const char *kind) {
    pdf_obj *dict = pdf_new_dict(ctx, doc, 2);
    pdf_obj *stream = NULL;
    fz_try(ctx) {
        pdf_dict_puts_drop(ctx, dict, "VPPageMark", pdf_new_name(ctx, kind));
        stream = pdf_add_stream(ctx, doc, buf, dict, 0);
    } fz_always(ctx) {
        pdf_drop_obj(ctx, dict);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
    return stream;
}

static const char *mark_kind(fz_context *ctx, pdf_obj *stream) {
    pdf_obj *kind = pdf_dict_gets(ctx, stream, "VPPageMark");
    return pdf_is_name(ctx, kind) ? pdf_to_name(ctx, kind) : NULL;
}

// The page's /Contents as an array (made one if it's a single stream).
static pdf_obj *contents_array(fz_context *ctx, pdf_document *doc, pdf_obj *page) {
    pdf_obj *contents = pdf_dict_get(ctx, page, PDF_NAME(Contents));
    if (pdf_is_array(ctx, contents)) return contents;
    pdf_obj *array = pdf_new_array(ctx, doc, 4);
    if (contents) pdf_array_push(ctx, array, contents);
    pdf_dict_put_drop(ctx, page, PDF_NAME(Contents), array);
    return array;
}

// Puts the page's own content in q ... Q, once, so a mark drawn after it starts from the
// graphics state a page starts with, whatever the content left changed.
static void wrap_contents(fz_context *ctx, pdf_document *doc, pdf_obj *contents) {
    int n = pdf_array_len(ctx, contents);
    for (int i = 0; i < n; i++) {
        const char *kind = mark_kind(ctx, pdf_array_get(ctx, contents, i));
        if (kind && !strcmp(kind, "Wrap")) return;
    }
    fz_buffer *open = fz_new_buffer_from_copied_data(ctx, (const unsigned char *)"q\n", 2);
    fz_buffer *close = NULL;
    fz_var(close);
    fz_try(ctx) {
        close = fz_new_buffer_from_copied_data(ctx, (const unsigned char *)"\nQ\n", 3);
        // After any watermarks drawn behind the content, which come first.
        int first = 0;
        while (first < n) {
            const char *kind = mark_kind(ctx, pdf_array_get(ctx, contents, first));
            if (!kind || strcmp(kind, "WatermarkBehind")) break;
            first++;
        }
        int last = n;
        while (last > first && mark_kind(ctx, pdf_array_get(ctx, contents, last - 1))) last--;
        pdf_array_insert_drop(ctx, contents, new_mark_stream(ctx, doc, close, "Wrap"), last);
        pdf_array_insert_drop(ctx, contents, new_mark_stream(ctx, doc, open, "Wrap"), first);
    } fz_always(ctx) {
        fz_drop_buffer(ctx, open);
        fz_drop_buffer(ctx, close);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
}

// An ExtGState in `res` drawing at `opacity` (to the nearest 1%), named into `name`.
static void alpha_state(fz_context *ctx, pdf_document *doc, pdf_obj *res, float opacity, char *name, size_t cap) {
    int alpha = (int)lroundf(fminf(fmaxf(opacity, 0), 1) * 100);
    fz_snprintf(name, cap, "VPMarkGS%d", alpha);
    pdf_obj *states = resource_dict(ctx, doc, res, PDF_NAME(ExtGState));
    if (pdf_dict_gets(ctx, states, name)) return;
    pdf_obj *gs = pdf_new_dict(ctx, doc, 3);
    fz_try(ctx) {
        pdf_dict_put(ctx, gs, PDF_NAME(Type), PDF_NAME(ExtGState));
        pdf_dict_put_real(ctx, gs, PDF_NAME(ca), alpha / 100.0);
        pdf_dict_put_real(ctx, gs, PDF_NAME(CA), alpha / 100.0);
        pdf_dict_puts_drop(ctx, states, name, pdf_add_object(ctx, doc, gs));
    } fz_always(ctx) {
        pdf_drop_obj(ctx, gs);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
}

// Adds the mark's (or another) content stream to the page: behind its content, first; or
// over it, with its content wrapped so it starts from a clean graphics state.
static void add_mark_stream(fz_context *ctx, pdf_document *doc, pdf_page *page, fz_buffer *buf, int behind, const char *over_kind) {
    pdf_obj *contents = contents_array(ctx, doc, page->obj);
    if (behind) {
        pdf_array_insert_drop(ctx, contents, new_mark_stream(ctx, doc, buf, "WatermarkBehind"), 0);
    } else {
        wrap_contents(ctx, doc, contents);
        pdf_array_push_drop(ctx, contents, new_mark_stream(ctx, doc, buf, over_kind));
    }
}

int mupdf_pdf_add_mark_image(fz_context *ctx, fz_document *doc, const unsigned char *data, size_t len, int *out_objnum, const char **out_error) {
    if (!ctx || !doc || !data || !len || !out_objnum) return -1;
    fz_buffer *buf = NULL;
    fz_image *image = NULL;
    pdf_obj *ref = NULL;
    fz_var(buf);
    fz_var(image);
    fz_var(ref);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        buf = fz_new_buffer_from_copied_data(ctx, data, len);
        image = fz_new_image_from_buffer(ctx, buf);
        ref = pdf_add_image(ctx, pdoc, image);
        *out_objnum = pdf_to_num(ctx, ref);
    } fz_always(ctx) {
        pdf_drop_obj(ctx, ref);
        fz_drop_image(ctx, image);
        fz_drop_buffer(ctx, buf);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_page_add_image_watermark(fz_context *ctx, fz_document *doc, int pageno, int image_objnum, float scale, const mupdf_watermark *wm, const char **out_error) {
    if (!ctx || !doc || !wm || image_objnum <= 0) return -1;
    pdf_page *page = NULL;
    fz_buffer *buf = NULL;
    pdf_obj *image = NULL;
    fz_var(page);
    fz_var(buf);
    fz_var(image);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        image = pdf_new_indirect(ctx, pdoc, image_objnum, 0);
        float iw = pdf_dict_get_real(ctx, image, PDF_NAME(Width)), ih = pdf_dict_get_real(ctx, image, PDF_NAME(Height));
        if (iw <= 0 || ih <= 0) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Not an image");
        page = pdf_load_page(ctx, pdoc, pageno);
        float width, height;
        fz_matrix m = shown_page_space(ctx, page, &width, &height);
        // `scale` of the page's width, kept inside it when turned.
        float w = width * (scale > 0 && scale <= 1 ? scale : 0.5f), h = w * ih / iw;
        float angle = wm->rotation * (float)M_PI / 180, c = fabsf(cosf(angle)), sn = fabsf(sinf(angle));
        float fit = fminf(width / (c * w + sn * h), height / (sn * w + c * h));
        if (fit < 1) { w *= fit; h *= fit; }

        pdf_obj *res = own_resources(ctx, pdoc, page->obj);
        char gs_name[32], im_name[32];
        alpha_state(ctx, pdoc, res, wm->opacity, gs_name, sizeof gs_name);
        fz_snprintf(im_name, sizeof im_name, "VPMarkIm%d", image_objnum);
        pdf_dict_puts(ctx, resource_dict(ctx, pdoc, res, PDF_NAME(XObject)), im_name, image);

        buf = fz_new_buffer(ctx, 256);
        fz_append_string(ctx, buf, "/Artifact <</Type /Pagination /Subtype /Watermark>> BDC\nq\n");
        append_matrix(ctx, buf, m);
        fz_append_printf(ctx, buf, "/%s gs\n", gs_name);
        append_matrix(ctx, buf, fz_concat(fz_rotate(wm->rotation), fz_translate(width / 2, height / 2)));
        fz_append_printf(ctx, buf, "%g 0 0 %g %g %g cm\n/%s Do\nQ\nEMC\n", w, h, -w / 2, -h / 2, im_name);
        add_mark_stream(ctx, pdoc, page, buf, wm->behind, "Watermark");
    } fz_always(ctx) {
        pdf_drop_obj(ctx, image);
        fz_drop_buffer(ctx, buf);
        fz_drop_page(ctx, (fz_page *)page);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_page_add_header_footer(fz_context *ctx, fz_document *doc, int pageno, const mupdf_header_footer *hf, const char **out_error) {
    if (!ctx || !doc || !hf) return -1;
    pdf_page *page = NULL;
    fz_buffer *buf = NULL;
    fz_font *font = NULL;
    fz_var(page);
    fz_var(buf);
    fz_var(font);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        int font_index = clamp_font(hf->font);
        float size = hf->size > 0 ? hf->size : 10;
        page = pdf_load_page(ctx, pdoc, pageno);
        float width, height;
        fz_matrix m = shown_page_space(ctx, page, &width, &height);
        font = fz_new_base14_font(ctx, font_names[font_index]);
        buf = fz_new_buffer(ctx, 256);
        int any = 0;
        for (int row = 0; row < 2; row++) {
            int started = 0;
            for (int col = 0; col < 3; col++) {
                const char *text = hf->text[row * 3 + col];
                if (!text || !*text) continue;
                if (!started) {
                    fz_append_printf(ctx, buf, "/Artifact <</Type /Pagination /Subtype /%s>> BDC\nq\n", row == 0 ? "Header" : "Footer");
                    append_matrix(ctx, buf, m);
                    fz_append_printf(ctx, buf, "%g %g %g rg\n", hf->color[0], hf->color[1], hf->color[2]);
                    started = 1;
                }
                float w = text_width(ctx, font, text) * size;
                float x = col == 0 ? hf->margin_left : col == 1 ? (width - w) / 2 : width - hf->margin_right - w;
                // The text's top at the top margin; its baseline at the bottom margin.
                float y = row == 0 ? height - hf->margin_top - size * 0.75f : hf->margin_bottom;
                fz_append_printf(ctx, buf, "BT /%s %g Tf %g %g Td ", font_keys[font_index], size, x, y);
                append_text_string(ctx, buf, text);
                fz_append_string(ctx, buf, " Tj ET\n");
            }
            if (started) {
                fz_append_string(ctx, buf, "Q\nEMC\n");
                any = 1;
            }
        }
        if (any) {
            pdf_obj *page_obj = page->obj;
            add_font_resource(ctx, pdoc, own_resources(ctx, pdoc, page_obj), font_index);
            pdf_obj *contents = contents_array(ctx, pdoc, page_obj);
            wrap_contents(ctx, pdoc, contents);
            pdf_array_push_drop(ctx, contents, new_mark_stream(ctx, pdoc, buf, "HeaderFooter"));
        }
    } fz_always(ctx) {
        fz_drop_buffer(ctx, buf);
        fz_drop_font(ctx, font);
        fz_drop_page(ctx, (fz_page *)page);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_page_add_watermark(fz_context *ctx, fz_document *doc, int pageno, const mupdf_watermark *wm, const char **out_error) {
    if (!ctx || !doc || !wm || !wm->text || !*wm->text) return -1;
    pdf_page *page = NULL;
    fz_buffer *buf = NULL;
    fz_font *font = NULL;
    fz_var(page);
    fz_var(buf);
    fz_var(font);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        int font_index = clamp_font(wm->font);
        page = pdf_load_page(ctx, pdoc, pageno);
        float width, height;
        fz_matrix m = shown_page_space(ctx, page, &width, &height);
        font = fz_new_base14_font(ctx, font_names[font_index]);

        // Lines, split at line breaks.
        char lines[16][512];
        int count = 0;
        for (const char *p = wm->text; *p && count < 16;) {
            const char *end = strchr(p, '\n');
            size_t len = end ? (size_t)(end - p) : strlen(p);
            if (len >= sizeof lines[0]) len = sizeof lines[0] - 1;
            memcpy(lines[count], p, len);
            lines[count][len] = 0;
            count++;
            if (!end) break;
            p = end + 1;
        }
        float widest = 0;
        for (int i = 0; i < count; i++) {
            float w = text_width(ctx, font, lines[i]);
            if (w > widest) widest = w;
        }
        float angle = wm->rotation * (float)M_PI / 180;
        float size = wm->size;
        if (size <= 0) {
            // As large as fits: the block's width along the angle, its height across it, inside
            // 80% of the page.
            float c = fabsf(cosf(angle)), s = fabsf(sinf(angle));
            float block_w = widest > 0 ? widest : 1, block_h = count * 1.2f;
            float fit_w = (c * block_w + s * block_h), fit_h = (s * block_w + c * block_h);
            size = fminf(width * 0.8f / fit_w, height * 0.8f / fit_h);
            if (size > 400) size = 400;
        }

        pdf_obj *res = own_resources(ctx, pdoc, page->obj);
        add_font_resource(ctx, pdoc, res, font_index);
        char gs_name[32];
        alpha_state(ctx, pdoc, res, wm->opacity, gs_name, sizeof gs_name);

        buf = fz_new_buffer(ctx, 256);
        fz_append_string(ctx, buf, "/Artifact <</Type /Pagination /Subtype /Watermark>> BDC\nq\n");
        append_matrix(ctx, buf, m);
        fz_append_printf(ctx, buf, "/%s gs\n%g %g %g rg\n", gs_name, wm->color[0], wm->color[1], wm->color[2]);
        // Centred on the page, turned about its centre.
        fz_matrix place = fz_concat(fz_rotate(wm->rotation), fz_translate(width / 2, height / 2));
        append_matrix(ctx, buf, place);
        float leading = size * 1.2f;
        float top = (count - 1) * leading / 2 - size * 0.35f;
        for (int i = 0; i < count; i++) {
            float w = text_width(ctx, font, lines[i]) * size;
            fz_append_printf(ctx, buf, "BT /%s %g Tf %g %g Td ", font_keys[font_index], size, -w / 2, top - i * leading);
            append_text_string(ctx, buf, lines[i]);
            fz_append_string(ctx, buf, " Tj ET\n");
        }
        fz_append_string(ctx, buf, "Q\nEMC\n");

        pdf_obj *contents = contents_array(ctx, pdoc, page->obj);
        if (wm->behind) {
            pdf_array_insert_drop(ctx, contents, new_mark_stream(ctx, pdoc, buf, "WatermarkBehind"), 0);
        } else {
            wrap_contents(ctx, pdoc, contents);
            pdf_array_push_drop(ctx, contents, new_mark_stream(ctx, pdoc, buf, "Watermark"));
        }
    } fz_always(ctx) {
        fz_drop_buffer(ctx, buf);
        fz_drop_font(ctx, font);
        fz_drop_page(ctx, (fz_page *)page);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

static int kind_in_mask(const char *kind, int mask) {
    if (!kind) return 0;
    if (!strcmp(kind, "HeaderFooter")) return mask & MUPDF_PAGE_MARK_HEADER_FOOTER;
    if (!strcmp(kind, "Watermark") || !strcmp(kind, "WatermarkBehind")) return mask & MUPDF_PAGE_MARK_WATERMARK;
    return 0;
}

int mupdf_pdf_page_marks(fz_context *ctx, fz_document *doc) {
    if (!ctx || !doc) return 0;
    int found = 0;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        for (int p = 0, n = pdoc ? pdf_count_pages(ctx, pdoc) : 0; p < n; p++) {
            pdf_obj *contents = pdf_dict_get(ctx, pdf_lookup_page_obj(ctx, pdoc, p), PDF_NAME(Contents));
            for (int i = 0, m = pdf_array_len(ctx, contents); i < m; i++) {
                const char *kind = mark_kind(ctx, pdf_array_get(ctx, contents, i));
                if (kind_in_mask(kind, MUPDF_PAGE_MARK_HEADER_FOOTER)) found |= MUPDF_PAGE_MARK_HEADER_FOOTER;
                if (kind_in_mask(kind, MUPDF_PAGE_MARK_WATERMARK)) found |= MUPDF_PAGE_MARK_WATERMARK;
            }
        }
    } fz_catch(ctx) {
        fz_report_error(ctx);
    }
    return found;
}

int mupdf_pdf_remove_page_marks(fz_context *ctx, fz_document *doc, int mask, const char **out_error) {
    if (!ctx || !doc) return -1;
    int removed = 0;
    fz_var(removed);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        for (int p = 0, n = pdf_count_pages(ctx, pdoc); p < n; p++) {
            pdf_obj *page = pdf_lookup_page_obj(ctx, pdoc, p);
            pdf_obj *contents = pdf_dict_get(ctx, page, PDF_NAME(Contents));
            if (!pdf_is_array(ctx, contents)) continue;
            int marks_left = 0;
            for (int i = pdf_array_len(ctx, contents) - 1; i >= 0; i--) {
                const char *kind = mark_kind(ctx, pdf_array_get(ctx, contents, i));
                if (kind_in_mask(kind, mask)) {
                    pdf_array_delete(ctx, contents, i);
                    removed++;
                } else if (kind && strcmp(kind, "Wrap")) {
                    marks_left = 1;
                }
            }
            // With no marks drawn after the content, the q ... Q around it isn't needed.
            if (!marks_left) {
                for (int i = pdf_array_len(ctx, contents) - 1; i >= 0; i--) {
                    const char *kind = mark_kind(ctx, pdf_array_get(ctx, contents, i));
                    if (kind && !strcmp(kind, "Wrap")) pdf_array_delete(ctx, contents, i);
                }
            }
        }
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return removed;
}

// The settings the marks were made with, kept in the catalog's page-piece dictionary
// (/PieceInfo /VectorPDF /Private /PageMarks), to change them later.
char *mupdf_pdf_page_marks_settings(fz_context *ctx, fz_document *doc) {
    if (!ctx || !doc) return NULL;
    char *result = NULL;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (pdoc) {
            pdf_obj *settings = pdf_dict_getp(ctx, pdf_dict_get(ctx, pdf_trailer(ctx, pdoc), PDF_NAME(Root)), "PieceInfo/VectorPDF/Private/PageMarks");
            if (pdf_is_string(ctx, settings)) result = fz_strdup(ctx, pdf_to_text_string(ctx, settings));
        }
    } fz_catch(ctx) {
        fz_report_error(ctx);
    }
    return result;
}

int mupdf_pdf_set_page_marks_settings(fz_context *ctx, fz_document *doc, const char *json, const char **out_error) {
    if (!ctx || !doc) return -1;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        pdf_obj *root = pdf_dict_get(ctx, pdf_trailer(ctx, pdoc), PDF_NAME(Root));
        pdf_obj *pieces = resource_dict(ctx, pdoc, root, PDF_NAME(PieceInfo));
        pdf_obj *ours = pdf_dict_gets(ctx, pieces, "VectorPDF");
        if (json && *json) {
            if (!pdf_is_dict(ctx, ours)) {
                ours = pdf_new_dict(ctx, pdoc, 2);
                pdf_dict_puts_drop(ctx, pieces, "VectorPDF", ours);
            }
            pdf_obj *key = pdf_new_name(ctx, "LastModified");
            fz_try(ctx)
                pdf_dict_put_date(ctx, ours, key, time(NULL));
            fz_always(ctx)
                pdf_drop_obj(ctx, key);
            fz_catch(ctx)
                fz_rethrow(ctx);
            pdf_obj *private = resource_dict(ctx, pdoc, ours, PDF_NAME(Private));
            pdf_dict_puts_drop(ctx, private, "PageMarks", pdf_new_text_string(ctx, json));
        } else if (pdf_is_dict(ctx, ours)) {
            pdf_dict_dels(ctx, pdf_dict_get(ctx, ours, PDF_NAME(Private)), "PageMarks");
            if (pdf_dict_len(ctx, pdf_dict_get(ctx, ours, PDF_NAME(Private))) == 0) pdf_dict_dels(ctx, pieces, "VectorPDF");
            if (pdf_dict_len(ctx, pieces) == 0) pdf_dict_del(ctx, root, PDF_NAME(PieceInfo));
        }
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}
