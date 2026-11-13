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

// For the Inspector: what the page draws at a point. A device the page's contents (not its
// annotations) run through keeps the last glyph, image and path drawn there, which is the one on
// top: a glyph whose box holds the point, an image whose square holds it, and a path whose fill
// holds it (by its own fill rule) or whose stroke passes within half its width of it.

#include "MuPDFBridge.h"
#include <math.h>
#include <string.h>

typedef struct {
    fz_device base;
    fz_point p;
    float tolerance;
    mupdf_content_at_point *out;
} inspect_device;

static void copy_name(char *dst, size_t size, const char *src) {
    dst[0] = 0;
    if (src) fz_strlcpy(dst, src, size);
}

static void to_rgb(fz_context *ctx, fz_colorspace *cs, const float *color, fz_color_params params, float rgb[3]) {
    rgb[0] = rgb[1] = rgb[2] = 0;
    if (!cs || !color) return;
    fz_try(ctx)
        fz_convert_color(ctx, cs, color, fz_device_rgb(ctx), rgb, NULL, params);
    fz_catch(ctx) {
        fz_report_error(ctx);
        rgb[0] = rgb[1] = rgb[2] = 0;
    }
}

static void colorspace_name(fz_context *ctx, fz_colorspace *cs, char *dst, size_t size) {
    copy_name(dst, size, cs ? fz_colorspace_name(ctx, cs) : NULL);
}

// MARK: Paths

typedef struct {
    fz_matrix ctm;
    fz_point p;
    fz_point current, start;
    int has_current;
    float best;      /* closest distance to the outline, in device space */
    int crossings;   /* for even-odd */
    int winding;     /* for non-zero */
} path_hit;

static void hit_segment(path_hit *h, fz_point a, fz_point b) {
    a = fz_transform_point(a, h->ctm);
    b = fz_transform_point(b, h->ctm);
    float dx = b.x - a.x, dy = b.y - a.y;
    float len2 = dx * dx + dy * dy;
    float t = len2 > 0 ? ((h->p.x - a.x) * dx + (h->p.y - a.y) * dy) / len2 : 0;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    float cx = a.x + t * dx - h->p.x, cy = a.y + t * dy - h->p.y;
    float d = sqrtf(cx * cx + cy * cy);
    if (d < h->best) h->best = d;
    // A ray from the point to the right.
    if ((a.y <= h->p.y) != (b.y <= h->p.y)) {
        float x = a.x + (h->p.y - a.y) / (b.y - a.y) * dx;
        if (x > h->p.x) {
            h->crossings++;
            h->winding += (b.y > a.y) ? 1 : -1;
        }
    }
}

static void close_subpath(path_hit *h) {
    if (h->has_current && (h->current.x != h->start.x || h->current.y != h->start.y))
        hit_segment(h, h->current, h->start);
    h->current = h->start;
}

static void walk_moveto(fz_context *ctx, void *arg, float x, float y) {
    path_hit *h = arg;
    close_subpath(h);
    h->current = h->start = fz_make_point(x, y);
    h->has_current = 1;
}

static void walk_lineto(fz_context *ctx, void *arg, float x, float y) {
    path_hit *h = arg;
    fz_point to = fz_make_point(x, y);
    hit_segment(h, h->current, to);
    h->current = to;
}

static void walk_curveto(fz_context *ctx, void *arg, float x1, float y1, float x2, float y2, float x3, float y3) {
    path_hit *h = arg;
    fz_point p0 = h->current;
    enum { STEPS = 16 };
    for (int i = 1; i <= STEPS; i++) {
        float t = (float)i / STEPS, u = 1 - t;
        fz_point q = fz_make_point(
            u * u * u * p0.x + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3,
            u * u * u * p0.y + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3);
        hit_segment(h, h->current, q);
        h->current = q;
    }
}

static void walk_closepath(fz_context *ctx, void *arg) {
    close_subpath(arg);
}

static const fz_path_walker hit_walker = { walk_moveto, walk_lineto, walk_curveto, walk_closepath, NULL, NULL, NULL, NULL };

static path_hit test_path(fz_context *ctx, const fz_path *path, fz_matrix ctm, fz_point p) {
    path_hit h = { ctm, p, {0, 0}, {0, 0}, 0, INFINITY, 0, 0 };
    fz_walk_path(ctx, path, &hit_walker, &h);
    close_subpath(&h);
    return h;
}

static void record_path(fz_context *ctx, inspect_device *dev, const fz_path *path, fz_matrix ctm) {
    mupdf_content_at_point *out = dev->out;
    if (!out->has_path) {
        out->stroke_width = -1;
    }
    fz_rect box = fz_bound_path(ctx, path, NULL, ctm);
    out->path_x0 = box.x0; out->path_y0 = box.y0; out->path_x1 = box.x1; out->path_y1 = box.y1;
    out->has_path = 1;
}

static void inspect_fill_path(fz_context *ctx, fz_device *dev_, const fz_path *path, int even_odd, fz_matrix ctm,
                              fz_colorspace *cs, const float *color, float alpha, fz_color_params params) {
    inspect_device *dev = (inspect_device *)dev_;
    fz_rect box = fz_bound_path(ctx, path, NULL, ctm);
    if (!fz_is_point_inside_rect(dev->p, fz_expand_rect(box, dev->tolerance))) return;
    path_hit h = test_path(ctx, path, ctm, dev->p);
    int inside = even_odd ? (h.crossings & 1) : (h.winding != 0);
    if (!inside && h.best > dev->tolerance) return;
    mupdf_content_at_point *out = dev->out;
    record_path(ctx, dev, path, ctm);
    out->path_filled = 1;
    out->path_stroked = 0;
    out->stroke_width = -1;
    to_rgb(ctx, cs, color, params, out->fill_rgb);
    colorspace_name(ctx, cs, out->path_colorspace, sizeof out->path_colorspace);
    out->path_alpha = alpha;
}

static void inspect_stroke_path(fz_context *ctx, fz_device *dev_, const fz_path *path, const fz_stroke_state *stroke, fz_matrix ctm,
                                fz_colorspace *cs, const float *color, float alpha, fz_color_params params) {
    inspect_device *dev = (inspect_device *)dev_;
    float width = (stroke ? stroke->linewidth : 1) * fz_matrix_expansion(ctm);
    float reach = fmaxf(width / 2, 0) + dev->tolerance;
    fz_rect box = fz_bound_path(ctx, path, NULL, ctm);
    if (!fz_is_point_inside_rect(dev->p, fz_expand_rect(box, reach))) return;
    path_hit h = test_path(ctx, path, ctm, dev->p);
    if (h.best > reach) return;
    mupdf_content_at_point *out = dev->out;
    record_path(ctx, dev, path, ctm);
    out->path_stroked = 1;
    out->path_filled = 0;
    out->stroke_width = width;
    to_rgb(ctx, cs, color, params, out->stroke_rgb);
    colorspace_name(ctx, cs, out->path_colorspace, sizeof out->path_colorspace);
    out->path_alpha = alpha;
}

// MARK: Text

static void inspect_text(fz_context *ctx, inspect_device *dev, const fz_text *text, fz_matrix ctm,
                         fz_colorspace *cs, const float *color, float alpha, fz_color_params params, int stroked) {
    for (fz_text_span *span = text->head; span; span = span->next) {
        for (int i = 0; i < span->len; i++) {
            fz_text_item *item = &span->items[i];
            if (item->gid < 0) continue;
            fz_matrix trm = span->trm;
            trm.e = item->x;
            trm.f = item->y;
            fz_matrix m = fz_concat(trm, ctm);
            fz_rect box = fz_bound_glyph(ctx, span->font, item->gid, m);
            if (fz_is_empty_rect(box) || !fz_is_point_inside_rect(dev->p, fz_expand_rect(box, dev->tolerance))) continue;
            mupdf_content_at_point *out = dev->out;
            out->has_text = 1;
            copy_name(out->font_name, sizeof out->font_name, fz_font_name(ctx, span->font));
            out->font_size = fz_matrix_expansion(m);
            out->font_is_substitute = fz_font_flags(span->font)->ft_substitute ? 1 : 0;
            out->text_unicode = item->ucs;
            out->text_stroked = stroked;
            to_rgb(ctx, cs, color, params, out->text_rgb);
            colorspace_name(ctx, cs, out->text_colorspace, sizeof out->text_colorspace);
            out->text_alpha = alpha;
            out->text_x0 = box.x0; out->text_y0 = box.y0; out->text_x1 = box.x1; out->text_y1 = box.y1;
        }
    }
}

static void inspect_fill_text(fz_context *ctx, fz_device *dev, const fz_text *text, fz_matrix ctm,
                              fz_colorspace *cs, const float *color, float alpha, fz_color_params params) {
    inspect_text(ctx, (inspect_device *)dev, text, ctm, cs, color, alpha, params, 0);
}

static void inspect_stroke_text(fz_context *ctx, fz_device *dev, const fz_text *text, const fz_stroke_state *stroke, fz_matrix ctm,
                                fz_colorspace *cs, const float *color, float alpha, fz_color_params params) {
    inspect_text(ctx, (inspect_device *)dev, text, ctm, cs, color, alpha, params, 1);
}

// MARK: Images

static void record_image(fz_context *ctx, inspect_device *dev, fz_image *img, fz_matrix ctm, int is_mask) {
    // An image fills the unit square under its matrix.
    fz_matrix inverse = fz_invert_matrix(ctm);
    fz_point q = fz_transform_point(dev->p, inverse);
    if (q.x < 0 || q.x > 1 || q.y < 0 || q.y > 1) return;
    mupdf_content_at_point *out = dev->out;
    out->has_image = 1;
    out->image_width = img->w;
    out->image_height = img->h;
    out->image_bpc = img->bpc;
    out->image_is_mask = is_mask;
    colorspace_name(ctx, img->colorspace, out->image_colorspace, sizeof out->image_colorspace);
    // Pixels per inch along each of the image's sides, as placed.
    float across = sqrtf(ctm.a * ctm.a + ctm.b * ctm.b), down = sqrtf(ctm.c * ctm.c + ctm.d * ctm.d);
    out->image_dpi_x = across > 0 ? img->w * 72.0f / across : 0;
    out->image_dpi_y = down > 0 ? img->h * 72.0f / down : 0;
    fz_rect box = fz_transform_rect(fz_unit_rect, ctm);
    out->image_x0 = box.x0; out->image_y0 = box.y0; out->image_x1 = box.x1; out->image_y1 = box.y1;
}

static void inspect_fill_image(fz_context *ctx, fz_device *dev, fz_image *img, fz_matrix ctm, float alpha, fz_color_params params) {
    record_image(ctx, (inspect_device *)dev, img, ctm, 0);
}

static void inspect_fill_image_mask(fz_context *ctx, fz_device *dev, fz_image *img, fz_matrix ctm,
                                    fz_colorspace *cs, const float *color, float alpha, fz_color_params params) {
    record_image(ctx, (inspect_device *)dev, img, ctm, 1);
}

int mupdf_page_inspect_point(fz_context *ctx, fz_document *doc, int pageno, float x, float y, float tolerance,
                             mupdf_content_at_point *out, const char **out_error) {
    if (!ctx || !doc || !out) return -1;
    memset(out, 0, sizeof *out);
    out->stroke_width = -1;
    out->text_unicode = -1;
    fz_page *page = NULL;
    inspect_device *dev = NULL;
    fz_var(page);
    fz_var(dev);
    fz_try(ctx) {
        page = fz_load_page(ctx, doc, pageno);
        dev = fz_new_derived_device(ctx, inspect_device);
        dev->base.fill_path = inspect_fill_path;
        dev->base.stroke_path = inspect_stroke_path;
        dev->base.fill_text = inspect_fill_text;
        dev->base.stroke_text = inspect_stroke_text;
        dev->base.fill_image = inspect_fill_image;
        dev->base.fill_image_mask = inspect_fill_image_mask;
        dev->p = fz_make_point(x, y);
        dev->tolerance = tolerance;
        dev->out = out;
        fz_run_page_contents(ctx, page, &dev->base, fz_identity, NULL);
        fz_close_device(ctx, &dev->base);
    } fz_always(ctx) {
        fz_drop_device(ctx, dev ? &dev->base : NULL);
        fz_drop_page(ctx, page);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_pdf_annot_opacity(fz_context *ctx, fz_document *doc, int pageno, int objnum, float *out_opacity) {
    if (!ctx || !doc || !out_opacity) return -1;
    *out_opacity = 1;
    pdf_page *page = NULL;
    int found = 0;
    fz_var(page);
    fz_var(found);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        page = pdf_load_page(ctx, pdoc, pageno);
        for (pdf_annot *a = pdf_first_annot(ctx, page); a; a = pdf_next_annot(ctx, a)) {
            if (pdf_to_num(ctx, pdf_annot_obj(ctx, a)) == objnum) {
                *out_opacity = pdf_annot_opacity(ctx, a);
                found = 1;
                break;
            }
        }
    } fz_always(ctx) {
        fz_drop_page(ctx, (fz_page *)page);
    } fz_catch(ctx) {
        fz_report_error(ctx);
        return -1;
    }
    return found ? 0 : -1;
}
