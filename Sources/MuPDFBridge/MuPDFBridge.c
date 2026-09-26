#include "include/MuPDFBridge.h"
#include <string.h>
#include <strings.h>
#include <pthread.h>

// Thread Synchronization Locks for MuPDF context cloning
static pthread_mutex_t g_mupdf_locks[FZ_LOCK_MAX];
static pthread_once_t g_mupdf_locks_once = PTHREAD_ONCE_INIT;

static void mupdf_init_locks(void) {
    for (int i = 0; i < FZ_LOCK_MAX; i++) {
        pthread_mutex_init(&g_mupdf_locks[i], NULL);
    }
}

static void mupdf_lock(void *user, int lock) {
    if (lock >= 0 && lock < FZ_LOCK_MAX) {
        pthread_mutex_lock(&g_mupdf_locks[lock]);
    }
}

static void mupdf_unlock(void *user, int lock) {
    if (lock >= 0 && lock < FZ_LOCK_MAX) {
        pthread_mutex_unlock(&g_mupdf_locks[lock]);
    }
}

static void mupdf_quiet_warning(void *user, const char *message) {
    // Suppress benign PDF stream warnings (e.g. premature flate filter end, duplicate ICC links)
    (void)user;
    (void)message;
}

// Context Lifecycle
fz_context *mupdf_context_create(size_t max_store_bytes) {
    pthread_once(&g_mupdf_locks_once, mupdf_init_locks);
    
    fz_locks_context locks;
    locks.user = NULL;
    locks.lock = mupdf_lock;
    locks.unlock = mupdf_unlock;
    
    size_t store = (max_store_bytes > 0) ? max_store_bytes : (32 * 1024 * 1024);
    fz_context *ctx = fz_new_context(NULL, &locks, store);
    if (ctx) {
        fz_set_warning_callback(ctx, mupdf_quiet_warning, NULL);
        fz_register_document_handlers(ctx);
    }
    return ctx;
}

fz_context *mupdf_context_clone(fz_context *base) {
    if (!base) return NULL;
    fz_context *ctx = fz_clone_context(base);
    if (ctx) {
        fz_set_warning_callback(ctx, mupdf_quiet_warning, NULL);
    }
    return ctx;
}

void mupdf_context_drop(fz_context *ctx) {
    if (ctx) fz_drop_context(ctx);
}

// Document Lifecycle
int mupdf_document_open(fz_context *ctx, const char *path, fz_document **out_doc, const char **out_error) {
    if (!ctx || !path || !out_doc) return -1;
    fz_var(*out_doc);
    *out_doc = NULL;
    fz_try(ctx) {
        *out_doc = fz_open_document(ctx, path);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_document_count_pages(fz_context *ctx, fz_document *doc, int *out_count, const char **out_error) {
    if (!ctx || !doc || !out_count) return -1;
    *out_count = 0;
    fz_try(ctx) {
        *out_count = fz_count_pages(ctx, doc);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

void mupdf_document_drop(fz_context *ctx, fz_document *doc) {
    if (ctx && doc) fz_drop_document(ctx, doc);
}

// Password Authentication
int mupdf_document_needs_password(fz_context *ctx, fz_document *doc, int *out_needs_password, const char **out_error) {
    if (!ctx || !doc || !out_needs_password) return -1;
    *out_needs_password = 0;
    fz_try(ctx) {
        *out_needs_password = fz_needs_password(ctx, doc);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_document_authenticate_password(fz_context *ctx, fz_document *doc, const char *password, int *out_authenticated, const char **out_error) {
    if (!ctx || !doc || !password || !out_authenticated) return -1;
    *out_authenticated = 0;
    fz_try(ctx) {
        // Returns 0 for failure, non-zero for success (see fz_authenticate_password's own doc
        // comment for the per-bit meaning of a successful result) — callers here only care
        // whether it's zero or not.
        *out_authenticated = fz_authenticate_password(ctx, doc, password);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

// Outline (Table of Contents)
int mupdf_document_load_outline(fz_context *ctx, fz_document *doc, fz_outline **out_outline, const char **out_error) {
    if (!ctx || !doc || !out_outline) return -1;
    fz_var(*out_outline);
    *out_outline = NULL;
    fz_try(ctx) {
        *out_outline = fz_load_outline(ctx, doc);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

void mupdf_outline_drop(fz_context *ctx, fz_outline *outline) {
    if (ctx && outline) fz_drop_outline(ctx, outline);
}

const char *mupdf_outline_title(fz_outline *outline) {
    return outline ? outline->title : NULL;
}

const char *mupdf_outline_uri(fz_outline *outline) {
    return outline ? outline->uri : NULL;
}

int mupdf_outline_page(fz_outline *outline) {
    return outline ? outline->page.page : -1;
}

fz_outline *mupdf_outline_next(fz_outline *outline) {
    return outline ? outline->next : NULL;
}

fz_outline *mupdf_outline_down(fz_outline *outline) {
    return outline ? outline->down : NULL;
}

// Page Lifecycle
int mupdf_page_load(fz_context *ctx, fz_document *doc, int pageno, fz_page **out_page, const char **out_error) {
    if (!ctx || !doc || !out_page) return -1;
    fz_var(*out_page);
    *out_page = NULL;
    fz_try(ctx) {
        *out_page = fz_load_page(ctx, doc, pageno);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_page_bounds(fz_context *ctx, fz_page *page, fz_rect *out_rect, const char **out_error) {
    if (!ctx || !page || !out_rect) return -1;
    fz_try(ctx) {
        *out_rect = fz_bound_page(ctx, page);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

void mupdf_page_drop(fz_context *ctx, fz_page *page) {
    if (ctx && page) fz_drop_page(ctx, page);
}

// Display List
int mupdf_display_list_create(fz_context *ctx, fz_page *page, fz_display_list **out_list, const char **out_error) {
    if (!ctx || !page || !out_list) return -1;
    fz_var(*out_list);
    *out_list = NULL;
    fz_try(ctx) {
        *out_list = fz_new_display_list_from_page(ctx, page);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

void mupdf_display_list_drop(fz_context *ctx, fz_display_list *list) {
    if (ctx && list) fz_drop_display_list(ctx, list);
}

// Pixmap Rendering
int mupdf_render_display_list(fz_context *ctx, fz_display_list *list, float scale_x, float scale_y, fz_pixmap **out_pixmap, const char **out_error) {
    if (!ctx || !list || !out_pixmap) return -1;
    fz_var(*out_pixmap);
    *out_pixmap = NULL;
    fz_try(ctx) {
        fz_matrix ctm = fz_scale(scale_x, scale_y);
        *out_pixmap = fz_new_pixmap_from_display_list(ctx, list, ctm, fz_device_rgb(ctx), 0);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_render_page(fz_context *ctx, fz_page *page, float scale_x, float scale_y, fz_pixmap **out_pixmap, const char **out_error) {
    if (!ctx || !page || !out_pixmap) return -1;
    fz_var(*out_pixmap);
    *out_pixmap = NULL;
    fz_try(ctx) {
        fz_matrix ctm = fz_scale(scale_x, scale_y);
        *out_pixmap = fz_new_pixmap_from_page(ctx, page, ctm, fz_device_rgb(ctx), 0);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_render_page_rect(fz_context *ctx, fz_page *page, float scale_x, float scale_y,
                           float x0, float y0, float x1, float y1,
                           fz_pixmap **out_pixmap, const char **out_error) {
    if (!ctx || !page || !out_pixmap) return -1;
    fz_var(*out_pixmap);
    *out_pixmap = NULL;
    fz_device *dev = NULL;
    fz_var(dev);
    fz_try(ctx) {
        float min_x = fminf(x0, x1);
        float max_x = fmaxf(x0, x1);
        float min_y = fminf(y0, y1);
        float max_y = fmaxf(y0, y1);
        fz_rect prect = fz_make_rect(min_x, min_y, max_x, max_y);
        fz_matrix ctm = fz_scale(scale_x, scale_y);
        fz_rect trect = fz_transform_rect(prect, ctm);
        fz_irect ibbox = fz_round_rect(trect);
        *out_pixmap = fz_new_pixmap_with_bbox(ctx, fz_device_rgb(ctx), ibbox, NULL, 0);
        fz_clear_pixmap_with_value(ctx, *out_pixmap, 0xff);
        dev = fz_new_draw_device(ctx, ctm, *out_pixmap);
        fz_run_page(ctx, page, dev, fz_identity, NULL);
        fz_close_device(ctx, dev);
        fz_drop_device(ctx, dev);
        dev = NULL;
    } fz_always(ctx) {
        if (dev) {
            fz_try(ctx) { fz_close_device(ctx, dev); } fz_catch(ctx) {}
            fz_drop_device(ctx, dev);
        }
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

void mupdf_pixmap_drop(fz_context *ctx, fz_pixmap *pixmap) {
    if (ctx && pixmap) fz_drop_pixmap(ctx, pixmap);
}

int mupdf_pixmap_width(fz_pixmap *pixmap) {
    return pixmap ? pixmap->w : 0;
}

int mupdf_pixmap_height(fz_pixmap *pixmap) {
    return pixmap ? pixmap->h : 0;
}

ptrdiff_t mupdf_pixmap_stride(fz_pixmap *pixmap) {
    return pixmap ? pixmap->stride : 0;
}

unsigned char *mupdf_pixmap_samples(fz_pixmap *pixmap) {
    return pixmap ? pixmap->samples : NULL;
}

int mupdf_pixmap_n(fz_pixmap *pixmap) {
    return pixmap ? pixmap->n : 0;
}

// Structured Text
int mupdf_stext_page_load(fz_context *ctx, fz_page *page, fz_stext_page **out_stext, const char **out_error) {
    if (!ctx || !page || !out_stext) return -1;
    fz_var(*out_stext);
    *out_stext = NULL;
    fz_try(ctx) {
        fz_stext_options opts;
        memset(&opts, 0, sizeof(opts));
        opts.flags = FZ_STEXT_DEHYPHENATE | FZ_STEXT_PRESERVE_WHITESPACE;
        *out_stext = fz_new_stext_page_from_page(ctx, page, &opts);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_stext_page_load_from_display_list(fz_context *ctx, fz_display_list *list, fz_stext_page **out_stext, const char **out_error) {
    if (!ctx || !list || !out_stext) return -1;
    fz_var(*out_stext);
    *out_stext = NULL;
    fz_try(ctx) {
        fz_stext_options opts;
        memset(&opts, 0, sizeof(opts));
        opts.flags = FZ_STEXT_DEHYPHENATE | FZ_STEXT_PRESERVE_WHITESPACE;
        *out_stext = fz_new_stext_page_from_display_list(ctx, list, &opts);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

void mupdf_stext_page_drop(fz_context *ctx, fz_stext_page *stext) {
    if (ctx && stext) fz_drop_stext_page(ctx, stext);
}

fz_stext_block *mupdf_stext_first_block(fz_stext_page *page) {
    return page ? page->first_block : NULL;
}

fz_stext_block *mupdf_stext_next_block(fz_stext_block *block) {
    return block ? block->next : NULL;
}

int mupdf_stext_block_type(fz_stext_block *block) {
    return block ? block->type : -1;
}

fz_rect mupdf_stext_block_bbox(fz_stext_block *block) {
    return block ? block->bbox : fz_empty_rect;
}

fz_stext_line *mupdf_stext_block_first_line(fz_stext_block *block) {
    if (!block || block->type != FZ_STEXT_BLOCK_TEXT) return NULL;
    return block->u.t.first_line;
}

fz_stext_line *mupdf_stext_next_line(fz_stext_line *line) {
    return line ? line->next : NULL;
}

fz_rect mupdf_stext_line_bbox(fz_stext_line *line) {
    return line ? line->bbox : fz_empty_rect;
}

fz_stext_char *mupdf_stext_line_first_char(fz_stext_line *line) {
    return line ? line->first_char : NULL;
}

fz_stext_char *mupdf_stext_next_char(fz_stext_char *ch) {
    return ch ? ch->next : NULL;
}

int mupdf_stext_char_c(fz_stext_char *ch) {
    return ch ? ch->c : 0;
}

fz_quad mupdf_stext_char_quad(fz_stext_char *ch) {
    if (!ch) { fz_quad q = {0}; return q; } return ch->quad;
}

fz_point mupdf_stext_char_origin(fz_stext_char *ch) {
    if (!ch) { fz_point p = {0}; return p; } return ch->origin;
}

float mupdf_stext_char_size(fz_stext_char *ch) {
    return ch ? ch->size : 0.0f;
}

// Links & Cross-References
int mupdf_links_load(fz_context *ctx, fz_page *page, fz_link **out_links, const char **out_error) {
    if (!ctx || !page || !out_links) return -1;
    fz_var(*out_links);
    *out_links = NULL;
    fz_try(ctx) {
        *out_links = fz_load_links(ctx, page);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

void mupdf_links_drop(fz_context *ctx, fz_link *links) {
    if (ctx && links) fz_drop_link(ctx, links);
}

fz_link *mupdf_link_next(fz_link *link) {
    return link ? link->next : NULL;
}

fz_rect mupdf_link_rect(fz_link *link) {
    return link ? link->rect : fz_empty_rect;
}

const char *mupdf_link_uri(fz_link *link) {
    return link ? link->uri : NULL;
}

int mupdf_resolve_link_page(fz_context *ctx, fz_document *doc, const char *uri, int *out_page, float *out_x, float *out_y) {
    if (!ctx || !doc || !uri) return -1;
    float x = 0, y = 0;
    fz_location loc = fz_resolve_link(ctx, doc, uri, &x, &y);
    if (out_page) *out_page = loc.page;
    if (out_x) *out_x = x;
    if (out_y) *out_y = y;
    return (loc.page >= 0) ? 0 : -1;
}

// Annotations & PDF Saving
// Every guard below throws instead of returning directly from inside fz_try: fz_try/fz_catch's
// exception-stack frame (see fz_push_try/fz_do_catch in MuPDF's error.c) is only popped by
// fz_catch being reached, so a bare `return` from inside a try body leaves that frame permanently
// pushed on ctx's fixed-size exception stack (one leaked slot per call, on a context reused for
// the actor's whole lifetime). Page handles use fz_var + fz_always for the same reason: a normal
// local would be dropped in the try body's "success" tail, but skipped entirely if an exception
// fires partway through instead of jumping straight to fz_catch — fz_var preserves the pointer's
// value across that jump so fz_always can still drop it either way.
static void ensure_annot_appearance_resources(fz_context *ctx, pdf_document *pdoc, pdf_annot *annot) {
    if (!ctx || !pdoc || !annot) return;
    pdf_obj *obj = pdf_annot_obj(ctx, annot);
    if (!obj) return;
    pdf_obj *ap = pdf_dict_get(ctx, obj, PDF_NAME(AP));
    if (!ap) return;
    pdf_obj *n = pdf_dict_get(ctx, ap, PDF_NAME(N));
    if (!n) return;
    if (!pdf_dict_get(ctx, n, PDF_NAME(Resources))) {
        pdf_obj *res = pdf_new_dict(ctx, pdoc, 1);
        pdf_dict_put_drop(ctx, n, PDF_NAME(Resources), res);
    }
}

int mupdf_pdf_add_text_markup(fz_context *ctx, fz_document *doc, int pageno, int type, const fz_quad *quads, int n_quads, float r, float g, float b, const char **out_error) {
    if (!ctx || !doc || !quads || n_quads <= 0) return -1;
    pdf_page *ppage = NULL;
    pdf_annot *annot = NULL;
    fz_var(ppage);
    fz_var(annot);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page for annotation");
        enum pdf_annot_type atype = PDF_ANNOT_HIGHLIGHT;
        if (type == 1) {
            atype = PDF_ANNOT_UNDERLINE;
        } else if (type == 2) {
            atype = PDF_ANNOT_STRIKE_OUT;
        }
        annot = pdf_create_annot(ctx, ppage, atype);
        pdf_set_annot_quad_points(ctx, annot, n_quads, quads);
        float color[3] = {r, g, b};
        pdf_set_annot_color(ctx, annot, 3, color);
        pdf_update_annot(ctx, annot);
        ensure_annot_appearance_resources(ctx, pdoc, annot);
        pdf_set_annot_resynthesised(ctx, annot);
    } fz_always(ctx) {
        if (annot) pdf_drop_annot(ctx, annot);
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_add_highlight(fz_context *ctx, fz_document *doc, int pageno, const fz_quad *quads, int n_quads, float r, float g, float b, const char **out_error) {
    return mupdf_pdf_add_text_markup(ctx, doc, pageno, 0, quads, n_quads, r, g, b, out_error);
}

int mupdf_pdf_highlight_annot(fz_context *ctx, fz_document *doc, int pageno, fz_quad quad, float r, float g, float b, const char **out_error) {
    return mupdf_pdf_add_highlight(ctx, doc, pageno, &quad, 1, r, g, b, out_error);
}

int mupdf_pdf_add_ink_stroke(fz_context *ctx, fz_document *doc, int pageno, const fz_point *points, int n_points, float stroke_width, float r, float g, float b, const char **out_error) {
    if (!ctx || !doc || !points || n_points <= 0) return -1;
    pdf_page *ppage = NULL;
    pdf_annot *annot = NULL;
    fz_buffer *buf = NULL;
    fz_var(ppage);
    fz_var(annot);
    fz_var(buf);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page for ink annotation");
        annot = pdf_create_annot(ctx, ppage, PDF_ANNOT_INK);
        float width = stroke_width > 0.0f ? stroke_width : 2.0f;
        pdf_set_annot_border_width(ctx, annot, width);
        float color[3] = {r, g, b};
        pdf_set_annot_color(ctx, annot, 3, color);
        pdf_set_annot_ink_list(ctx, annot, 1, &n_points, points);
        pdf_update_annot(ctx, annot);

        pdf_obj *annot_obj = pdf_annot_obj(ctx, annot);
        if (annot_obj) {
            // Remove /RD (Rect Differences is illegal on Ink annotations per ISO 32000-1)
            pdf_dict_del(ctx, annot_obj, PDF_NAME(RD));

            pdf_obj *ink_list = pdf_dict_get(ctx, annot_obj, PDF_NAME(InkList));
            if (ink_list) {
                float min_x = 0, max_x = 0, min_y = 0, max_y = 0;
                int first_pt = 1;
                int n_paths = pdf_array_len(ctx, ink_list);
                for (int s = 0; s < n_paths; s++) {
                    pdf_obj *stroke = pdf_array_get(ctx, ink_list, s);
                    int n_coords = pdf_array_len(ctx, stroke);
                    for (int c = 0; c + 1 < n_coords; c += 2) {
                        float px = pdf_to_real(ctx, pdf_array_get(ctx, stroke, c));
                        float py = pdf_to_real(ctx, pdf_array_get(ctx, stroke, c + 1));
                        if (first_pt) {
                            min_x = max_x = px;
                            min_y = max_y = py;
                            first_pt = 0;
                        } else {
                            if (px < min_x) min_x = px;
                            if (px > max_x) max_x = px;
                            if (py < min_y) min_y = py;
                            if (py > max_y) max_y = py;
                        }
                    }
                }
                if (!first_pt) {
                    float pad = (width * 0.5f) + 1.0f;
                    if (pad < 2.0f) pad = 2.0f;
                    fz_rect rect = fz_make_rect(min_x - pad, min_y - pad, max_x + pad, max_y + pad);
                    pdf_dict_put_rect(ctx, annot_obj, PDF_NAME(Rect), rect);

                    pdf_obj *ap = pdf_dict_get(ctx, annot_obj, PDF_NAME(AP));
                    if (ap) {
                        pdf_obj *n = pdf_dict_get(ctx, ap, PDF_NAME(N));
                        if (n) {
                            float w = rect.x1 - rect.x0;
                            float h = rect.y1 - rect.y0;
                            fz_rect bbox = fz_make_rect(0, 0, w, h);
                            pdf_dict_put_rect(ctx, n, PDF_NAME(BBox), bbox);
                            pdf_dict_put_matrix(ctx, n, PDF_NAME(Matrix), fz_identity);

                            buf = fz_new_buffer(ctx, 256 + n_points * 32);
                            fz_append_printf(ctx, buf, "%g w\n1 J\n1 j\n%g %g %g RG\n", width, r, g, b);
                            fz_append_string(ctx, buf, "q\n");
                            fz_append_printf(ctx, buf, "1 0 0 1 %g %g cm\n", -rect.x0, -rect.y0);
                            for (int s = 0; s < n_paths; s++) {
                                pdf_obj *stroke = pdf_array_get(ctx, ink_list, s);
                                int n_coords = pdf_array_len(ctx, stroke);
                                if (n_coords >= 2) {
                                    float x0 = pdf_to_real(ctx, pdf_array_get(ctx, stroke, 0));
                                    float y0 = pdf_to_real(ctx, pdf_array_get(ctx, stroke, 1));
                                    if (n_coords == 2) {
                                        fz_append_printf(ctx, buf, "%g %g m\n%g %g l\n", x0, y0, x0 + 0.1f, y0);
                                    } else {
                                        fz_append_printf(ctx, buf, "%g %g m\n", x0, y0);
                                        for (int c = 2; c + 1 < n_coords; c += 2) {
                                            float cx = pdf_to_real(ctx, pdf_array_get(ctx, stroke, c));
                                            float cy = pdf_to_real(ctx, pdf_array_get(ctx, stroke, c + 1));
                                            fz_append_printf(ctx, buf, "%g %g l\n", cx, cy);
                                        }
                                    }
                                }
                            }
                            fz_append_string(ctx, buf, "S\nQ\n");
                            pdf_update_stream(ctx, pdoc, n, buf, 0);
                            fz_drop_buffer(ctx, buf);
                            buf = NULL;
                        }
                    }
                }
            }
        }
        ensure_annot_appearance_resources(ctx, pdoc, annot);
        pdf_set_annot_resynthesised(ctx, annot);
    } fz_always(ctx) {
        if (buf) fz_drop_buffer(ctx, buf);
        if (annot) pdf_drop_annot(ctx, annot);
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_add_free_text_annot(fz_context *ctx, fz_document *doc, int pageno, float x0, float y0, float x1, float y1, const char *text, float font_size, float r, float g, float b, const char **out_error) {
    if (!ctx || !doc || !text) return -1;
    pdf_page *ppage = NULL;
    pdf_annot *annot = NULL;
    fz_buffer *buf = NULL;
    fz_var(ppage);
    fz_var(annot);
    fz_var(buf);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page for free text annotation");
        float min_x = fminf(x0, x1);
        float max_x = fmaxf(x0, x1);
        float min_y = fminf(y0, y1);
        float max_y = fmaxf(y0, y1);
        fz_rect rect = fz_make_rect(min_x, min_y, max_x, max_y);
        annot = pdf_create_annot(ctx, ppage, PDF_ANNOT_FREE_TEXT);
        pdf_set_annot_rect(ctx, annot, rect);
        pdf_set_annot_border_width(ctx, annot, 0.0f);
        float color[3] = {r, g, b};
        float fs = font_size > 0.0f ? font_size : 13.0f;
        pdf_set_annot_default_appearance(ctx, annot, "Helv", fs, 3, color);
        pdf_set_annot_contents(ctx, annot, text);
        pdf_update_annot(ctx, annot);

        pdf_obj *annot_obj = pdf_annot_obj(ctx, annot);
        if (annot_obj) {
            // Delete /CL and /RD: in standard text annotations, spurious callout lines
            // or rect differences cause Apple Preview and PDFKit to misinterpret or hide the text
            pdf_dict_del(ctx, annot_obj, PDF_NAME(CL));
            pdf_dict_del(ctx, annot_obj, PDF_NAME(RD));
            pdf_dict_del(ctx, annot_obj, PDF_NAME(BS));

            pdf_obj *ap = pdf_dict_get(ctx, annot_obj, PDF_NAME(AP));
            if (ap) {
                pdf_obj *n = pdf_dict_get(ctx, ap, PDF_NAME(N));
                if (n) {
                    float w = rect.x1 - rect.x0;
                    float h = rect.y1 - rect.y0;
                    fz_rect bbox = fz_make_rect(0, 0, w, h);
                    pdf_dict_put_rect(ctx, n, PDF_NAME(BBox), bbox);
                    pdf_dict_put_matrix(ctx, n, PDF_NAME(Matrix), fz_identity);

                    buf = fz_new_buffer(ctx, 256);
                    fz_append_printf(ctx, buf, "0 0 %g %g re\nW\nn\nBT\n", w, h);
                    fz_append_printf(ctx, buf, "%g %g %g rg\n", r, g, b);
                    fz_append_printf(ctx, buf, "/Helv %g Tf\n", fs);
                    float leading = fs * 1.25f;
                    fz_append_printf(ctx, buf, "%g TL\n", leading);
                    float baseline_y = h - fs * 0.9f;
                    if (baseline_y < 2.0f) baseline_y = 2.0f;
                    fz_append_printf(ctx, buf, "2 %g Td\n", baseline_y);

                    const char *p = text;
                    int is_first_line = 1;
                    while (*p) {
                        const char *end = strchr(p, '\n');
                        size_t line_len = end ? (size_t)(end - p) : strlen(p);
                        if (line_len > 0 && p[line_len - 1] == '\r') line_len--;
                        if (!is_first_line) {
                            fz_append_string(ctx, buf, "T*\n");
                        }
                        char line_buf[1024];
                        if (line_len < sizeof(line_buf)) {
                            memcpy(line_buf, p, line_len);
                            line_buf[line_len] = '\0';
                            fz_append_pdf_string(ctx, buf, line_buf);
                        } else {
                            fz_append_string(ctx, buf, "(");
                            fz_append_string(ctx, buf, ")");
                        }
                        fz_append_string(ctx, buf, " Tj\n");
                        is_first_line = 0;
                        if (!end) break;
                        p = end + 1;
                    }
                    fz_append_string(ctx, buf, "ET\n");
                    pdf_update_stream(ctx, pdoc, n, buf, 0);
                    fz_drop_buffer(ctx, buf);
                    buf = NULL;
                }
            }
        }
        ensure_annot_appearance_resources(ctx, pdoc, annot);
        pdf_set_annot_resynthesised(ctx, annot);
    } fz_always(ctx) {
        if (buf) fz_drop_buffer(ctx, buf);
        if (annot) pdf_drop_annot(ctx, annot);
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_add_callout_annot(fz_context *ctx, fz_document *doc, int pageno,
                                float target_x, float target_y,
                                float knee_x, float knee_y,
                                float box_x0, float box_y0, float box_x1, float box_y1,
                                const char *text, float font_size,
                                float r, float g, float b,
                                const char **out_error) {
    if (!ctx || !doc || !text) return -1;
    pdf_page *ppage = NULL;
    pdf_annot *annot = NULL;
    fz_buffer *buf = NULL;
    fz_var(ppage);
    fz_var(annot);
    fz_var(buf);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page for callout annotation");

        float min_bx = fminf(box_x0, box_x1);
        float max_bx = fmaxf(box_x0, box_x1);
        float min_by = fminf(box_y0, box_y1);
        float max_by = fmaxf(box_y0, box_y1);
        fz_rect box_rect = fz_make_rect(min_bx, min_by, max_bx, max_by);

        // Attachment point on text box closest to knee point
        float attach_x = (knee_x <= min_bx) ? min_bx : ((knee_x >= max_bx) ? max_bx : knee_x);
        float attach_y = (knee_y <= min_by) ? min_by : ((knee_y >= max_by) ? max_by : (min_by + max_by) * 0.5f);
        fz_point target_pt = fz_make_point(target_x, target_y);
        fz_point knee_pt = fz_make_point(knee_x, knee_y);
        fz_point attach_pt = fz_make_point(attach_x, attach_y);

        // Enclosing rect
        fz_rect union_rect = box_rect;
        union_rect = fz_include_point_in_rect(union_rect, target_pt);
        union_rect = fz_include_point_in_rect(union_rect, knee_pt);
        union_rect = fz_include_point_in_rect(union_rect, attach_pt);
        union_rect = fz_expand_rect(union_rect, 6.0f);

        annot = pdf_create_annot(ctx, ppage, PDF_ANNOT_FREE_TEXT);
        pdf_set_annot_intent(ctx, annot, PDF_ANNOT_IT_FREETEXT_CALLOUT);
        pdf_set_annot_rect(ctx, annot, union_rect);

        fz_point cl[3] = { target_pt, knee_pt, attach_pt };
        pdf_set_annot_callout_line(ctx, annot, cl, 3);
        pdf_set_annot_callout_style(ctx, annot, PDF_ANNOT_LE_OPEN_ARROW);

        float color[3] = {r, g, b};
        float fs = font_size > 0.0f ? font_size : 11.0f;
        pdf_set_annot_default_appearance(ctx, annot, "Helv", fs, 3, color);
        pdf_set_annot_contents(ctx, annot, text);
        pdf_set_annot_border_width(ctx, annot, 1.0f);
        pdf_set_annot_color(ctx, annot, 3, color);
        pdf_update_annot(ctx, annot);

        // Build appearance stream /AP /N so all standard viewers render leader arrow and box
        pdf_obj *annot_obj = pdf_annot_obj(ctx, annot);
        if (annot_obj) {
            pdf_obj *ap = pdf_dict_get(ctx, annot_obj, PDF_NAME(AP));
            if (ap) {
                pdf_obj *n = pdf_dict_get(ctx, ap, PDF_NAME(N));
                if (n) {
                    float w = union_rect.x1 - union_rect.x0;
                    float h = union_rect.y1 - union_rect.y0;
                    fz_rect bbox = fz_make_rect(0, 0, w, h);
                    pdf_dict_put_rect(ctx, n, PDF_NAME(BBox), bbox);
                    pdf_dict_put_matrix(ctx, n, PDF_NAME(Matrix), fz_identity);

                    float ox = union_rect.x0;
                    float oy = union_rect.y0;

                    buf = fz_new_buffer(ctx, 512);
                    fz_append_printf(ctx, buf, "%g %g %g RG\n", r, g, b);
                    fz_append_printf(ctx, buf, "%g %g %g rg\n", r, g, b);
                    fz_append_printf(ctx, buf, "1 w 1 J 1 j\n");

                    // Leader line from target to knee to attach
                    fz_append_printf(ctx, buf, "%g %g m\n", target_x - ox, target_y - oy);
                    fz_append_printf(ctx, buf, "%g %g l\n", knee_x - ox, knee_y - oy);
                    fz_append_printf(ctx, buf, "%g %g l\nS\n", attach_x - ox, attach_y - oy);

                    // Arrow head at target_pt
                    float dx = knee_x - target_x;
                    float dy = knee_y - target_y;
                    float len = hypotf(dx, dy);
                    if (len > 0.001f) {
                        float ux = dx / len;
                        float uy = dy / len;
                        float arrow_len = 8.0f;
                        float arrow_w = 4.0f;
                        float ax = (target_x - ox) + ux * arrow_len;
                        float ay = (target_y - oy) + uy * arrow_len;
                        float px = -uy * arrow_w;
                        float py = ux * arrow_w;
                        fz_append_printf(ctx, buf, "%g %g m\n", target_x - ox, target_y - oy);
                        fz_append_printf(ctx, buf, "%g %g l\n", ax + px, ay + py);
                        fz_append_printf(ctx, buf, "%g %g l\n", ax - px, ay - py);
                        fz_append_printf(ctx, buf, "h\nf\n");
                    }

                    // Text box rectangle outline and white background
                    float bw = max_bx - min_bx;
                    float bh = max_by - min_by;
                    fz_append_printf(ctx, buf, "1 1 1 rg\n");
                    fz_append_printf(ctx, buf, "%g %g %g %g re\nB\n", min_bx - ox, min_by - oy, bw, bh);

                    // Text inside box
                    fz_append_printf(ctx, buf, "BT\n%g %g %g rg\n/Helv %g Tf\n", r, g, b, fs);
                    float leading = fs * 1.25f;
                    fz_append_printf(ctx, buf, "%g TL\n", leading);
                    float baseline_y = (min_by - oy) + bh - fs * 0.9f - 2.0f;
                    if (baseline_y < (min_by - oy) + 2.0f) baseline_y = (min_by - oy) + 2.0f;
                    fz_append_printf(ctx, buf, "%g %g Td\n", (min_bx - ox) + 3.0f, baseline_y);

                    const char *p = text;
                    int is_first_line = 1;
                    while (*p) {
                        const char *end = strchr(p, '\n');
                        size_t line_len = end ? (size_t)(end - p) : strlen(p);
                        if (line_len > 0 && p[line_len - 1] == '\r') line_len--;
                        if (!is_first_line) {
                            fz_append_string(ctx, buf, "T*\n");
                        }
                        char line_buf[1024];
                        if (line_len < sizeof(line_buf)) {
                            memcpy(line_buf, p, line_len);
                            line_buf[line_len] = '\0';
                            fz_append_pdf_string(ctx, buf, line_buf);
                        } else {
                            fz_append_string(ctx, buf, "(");
                            fz_append_string(ctx, buf, ")");
                        }
                        fz_append_string(ctx, buf, " Tj\n");
                        is_first_line = 0;
                        if (!end) break;
                        p = end + 1;
                    }
                    fz_append_string(ctx, buf, "ET\n");

                    pdf_update_stream(ctx, pdoc, n, buf, 0);
                    fz_drop_buffer(ctx, buf);
                    buf = NULL;
                }
            }
        }
        ensure_annot_appearance_resources(ctx, pdoc, annot);
        pdf_set_annot_resynthesised(ctx, annot);
    } fz_always(ctx) {
        if (buf) fz_drop_buffer(ctx, buf);
        if (annot) pdf_drop_annot(ctx, annot);
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_page_apply_redaction_rects(fz_context *ctx, fz_document *doc, int pageno, const fz_rect *rects, int n_rects, int black_boxes, const char **out_error) {
    if (!ctx || !doc) return -1;
    pdf_page *ppage = NULL;
    fz_var(ppage);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page for redaction");

        if (rects && n_rects > 0) {
            for (int i = 0; i < n_rects; i++) {
                fz_rect r = rects[i];
                float min_x = fminf(r.x0, r.x1);
                float max_x = fmaxf(r.x0, r.x1);
                float min_y = fminf(r.y0, r.y1);
                float max_y = fmaxf(r.y0, r.y1);
                fz_rect norm_rect = fz_make_rect(min_x, min_y, max_x, max_y);
                pdf_annot *annot = pdf_create_annot(ctx, ppage, PDF_ANNOT_REDACT);
                pdf_set_annot_rect(ctx, annot, norm_rect);
                pdf_update_annot(ctx, annot);
                pdf_drop_annot(ctx, annot);
            }
        }

        pdf_redact_options opts;
        memset(&opts, 0, sizeof(opts));
        opts.black_boxes = black_boxes ? 1 : 0;
        opts.image_method = PDF_REDACT_IMAGE_PIXELS;
        opts.line_art = PDF_REDACT_LINE_ART_REMOVE_IF_COVERED;
        opts.text = PDF_REDACT_TEXT_REMOVE;

        pdf_redact_page(ctx, pdoc, ppage, &opts);
    } fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_page_add_redact_annot(fz_context *ctx, fz_document *doc, int pageno, float x0, float y0, float x1, float y1, const char **out_error) {
    if (!ctx || !doc) return -1;
    pdf_page *ppage = NULL;
    pdf_annot *annot = NULL;
    fz_var(ppage);
    fz_var(annot);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page for redaction annotation");
        float min_x = fminf(x0, x1);
        float max_x = fmaxf(x0, x1);
        float min_y = fminf(y0, y1);
        float max_y = fmaxf(y0, y1);
        fz_rect rect = fz_make_rect(min_x, min_y, max_x, max_y);
        annot = pdf_create_annot(ctx, ppage, PDF_ANNOT_REDACT);
        pdf_set_annot_rect(ctx, annot, rect);
        float border_color[3] = {1.0f, 0.0f, 0.0f};
        pdf_set_annot_color(ctx, annot, 3, border_color);
        pdf_set_annot_border_width(ctx, annot, 1.5f);
        pdf_update_annot(ctx, annot);
    } fz_always(ctx) {
        if (annot) pdf_drop_annot(ctx, annot);
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_delete_annot_near_point(fz_context *ctx, fz_document *doc, int pageno, float x, float y, const char **out_error) {
    if (!ctx || !doc) return -1;
    pdf_page *ppage = NULL;
    int deleted = 0;
    fz_var(ppage);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page for annotation");
        for (pdf_annot *annot = pdf_first_annot(ctx, ppage); annot; annot = pdf_next_annot(ctx, annot)) {
            enum pdf_annot_type atype = pdf_annot_type(ctx, annot);
            int hit = 0;
            if (atype == PDF_ANNOT_HIGHLIGHT || atype == PDF_ANNOT_UNDERLINE || atype == PDF_ANNOT_STRIKE_OUT) {
                if (pdf_annot_has_quad_points(ctx, annot)) {
                    int n_quads = pdf_annot_quad_point_count(ctx, annot);
                    for (int i = 0; i < n_quads; i++) {
                        fz_quad q = pdf_annot_quad_point(ctx, annot, i);
                        float min_x = fminf(fminf(q.ul.x, q.ur.x), fminf(q.ll.x, q.lr.x));
                        float max_x = fmaxf(fmaxf(q.ul.x, q.ur.x), fmaxf(q.ll.x, q.lr.x));
                        float min_y = fminf(fminf(q.ul.y, q.ur.y), fminf(q.ll.y, q.lr.y));
                        float max_y = fmaxf(fmaxf(q.ul.y, q.ur.y), fmaxf(q.ll.y, q.lr.y));
                        float tol = 5.0f;
                        if (x >= min_x - tol && x <= max_x + tol && y >= min_y - tol && y <= max_y + tol) {
                            hit = 1;
                            break;
                        }
                    }
                } else {
                    fz_rect r = pdf_bound_annot(ctx, annot);
                    float tol = 5.0f;
                    if (x >= r.x0 - tol && x <= r.x1 + tol && y >= r.y0 - tol && y <= r.y1 + tol) {
                        hit = 1;
                    }
                }
            } else if (atype == PDF_ANNOT_FREE_TEXT || atype == PDF_ANNOT_REDACT || atype == PDF_ANNOT_STAMP) {
                fz_rect r = pdf_bound_annot(ctx, annot);
                fz_rect ar = pdf_annot_rect(ctx, annot);
                fz_rect dr = pdf_annot_display_rect(ctx, annot);
                fz_rect rr = pdf_dict_get_rect(ctx, pdf_annot_obj(ctx, annot), PDF_NAME(Rect));
                float tol = 8.0f;
                if ((x >= r.x0 - tol && x <= r.x1 + tol && y >= r.y0 - tol && y <= r.y1 + tol) ||
                    (x >= ar.x0 - tol && x <= ar.x1 + tol && y >= ar.y0 - tol && y <= ar.y1 + tol) ||
                    (x >= dr.x0 - tol && x <= dr.x1 + tol && y >= dr.y0 - tol && y <= dr.y1 + tol) ||
                    (x >= rr.x0 - tol && x <= rr.x1 + tol && y >= rr.y0 - tol && y <= rr.y1 + tol)) {
                    hit = 1;
                }
                if (!hit && pdf_annot_has_callout(ctx, annot)) {
                    fz_point cl[3];
                    int n_cl = 0;
                    pdf_annot_callout_line(ctx, annot, cl, &n_cl);
                    for (int i = 0; i < n_cl; i++) {
                        float dx = x - cl[i].x;
                        float dy = y - cl[i].y;
                        if (dx * dx + dy * dy <= tol * tol * 2.0f) {
                            hit = 1;
                            break;
                        }
                        if (i > 0) {
                            float seg_dx = cl[i].x - cl[i-1].x;
                            float seg_dy = cl[i].y - cl[i-1].y;
                            float l2 = seg_dx * seg_dx + seg_dy * seg_dy;
                            if (l2 > 0.0001f) {
                                float t = ((x - cl[i-1].x) * seg_dx + (y - cl[i-1].y) * seg_dy) / l2;
                                t = fmaxf(0.0f, fminf(1.0f, t));
                                float proj_x = cl[i-1].x + t * seg_dx;
                                float proj_y = cl[i-1].y + t * seg_dy;
                                float dpx = x - proj_x;
                                float dpy = y - proj_y;
                                if (dpx * dpx + dpy * dpy <= tol * tol * 2.0f) {
                                    hit = 1;
                                    break;
                                }
                            }
                        }
                    }
                }
            } else if (atype == PDF_ANNOT_INK) {
                if (pdf_annot_has_ink_list(ctx, annot)) {
                    int n_strokes = pdf_annot_ink_list_count(ctx, annot);
                    float tol = 8.0f;
                    for (int s = 0; s < n_strokes; s++) {
                        int n_verts = pdf_annot_ink_list_stroke_count(ctx, annot, s);
                        for (int v = 0; v < n_verts; v++) {
                            fz_point p = pdf_annot_ink_list_stroke_vertex(ctx, annot, s, v);
                            float dx = x - p.x;
                            float dy = y - p.y;
                            if (dx * dx + dy * dy <= tol * tol) {
                                hit = 1;
                                break;
                            }
                            if (v > 0) {
                                fz_point p_prev = pdf_annot_ink_list_stroke_vertex(ctx, annot, s, v - 1);
                                float seg_dx = p.x - p_prev.x;
                                float seg_dy = p.y - p_prev.y;
                                float l2 = seg_dx * seg_dx + seg_dy * seg_dy;
                                if (l2 > 0.0001f) {
                                    float t = ((x - p_prev.x) * seg_dx + (y - p_prev.y) * seg_dy) / l2;
                                    t = fmaxf(0.0f, fminf(1.0f, t));
                                    float proj_x = p_prev.x + t * seg_dx;
                                    float proj_y = p_prev.y + t * seg_dy;
                                    float dpx = x - proj_x;
                                    float dpy = y - proj_y;
                                    if (dpx * dpx + dpy * dpy <= tol * tol) {
                                        hit = 1;
                                        break;
                                    }
                                }
                            }
                        }
                        if (hit) break;
                    }
                }
            }
            if (hit) {
                pdf_delete_annot(ctx, ppage, annot);
                deleted = 1;
                break;
            }
        }
    } fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return deleted;
}

int mupdf_pdf_delete_highlight_near_point(fz_context *ctx, fz_document *doc, int pageno, float x, float y, const char **out_error) {
    return mupdf_pdf_delete_annot_near_point(ctx, doc, pageno, x, y, out_error);
}


// Stamps an image into a new PDF_ANNOT_STAMP annotation at the given rect — a purely visual
// signature overlay (see PDFFormControls.swift). Does not touch the AcroForm field's /V and isn't
// a cryptographic signature (no OpenSSL in this build).
int mupdf_pdf_stamp_image_annot(fz_context *ctx, fz_document *doc, int pageno,
                                 float x0, float y0, float x1, float y1,
                                 const unsigned char *image_data, size_t image_len,
                                 const char **out_error) {
    if (!ctx || !doc || !image_data || image_len == 0) return -1;
    pdf_page *ppage = NULL;
    pdf_annot *annot = NULL;
    fz_buffer *buf = NULL;
    fz_image *img = NULL;
    fz_var(ppage);
    fz_var(annot);
    fz_var(buf);
    fz_var(img);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page for annotation");
        buf = fz_new_buffer_from_copied_data(ctx, image_data, image_len);
        img = fz_new_image_from_buffer(ctx, buf);
        annot = pdf_create_annot(ctx, ppage, PDF_ANNOT_STAMP);
        fz_rect rect = fz_make_rect(x0, y0, x1, y1);
        pdf_set_annot_rect(ctx, annot, rect);
        pdf_set_annot_stamp_image(ctx, annot, img);
        pdf_update_annot(ctx, annot);
        ensure_annot_appearance_resources(ctx, pdoc, annot);
        // pdf_set_annot_stamp_image + pdf_update_annot saves /Rect mirrored vertically around the
        // page height, even though pdf_annot_rect's getter reports it correctly. Write it directly.
        pdf_dict_put_rect(ctx, pdf_annot_obj(ctx, annot), PDF_NAME(Rect), rect);
    } fz_always(ctx) {
        if (img) fz_drop_image(ctx, img);
        if (buf) fz_drop_buffer(ctx, buf);
        if (annot) pdf_drop_annot(ctx, annot);
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

// Reports whether a PDF_ANNOT_STAMP annotation already sits at (the center of) the given rect —
// lets a freshly (re)loaded PDFSignatureStampButton tell a field was already signed, instead of
// showing its "Sign" placeholder over the already-baked-in stamp.
int mupdf_pdf_page_has_stamp_near_rect(fz_context *ctx, fz_document *doc, int pageno,
                                        float x0, float y0, float x1, float y1,
                                        int *out_found, const char **out_error) {
    if (!ctx || !doc || !out_found) return -1;
    *out_found = 0;
    pdf_page *ppage = NULL;
    fz_var(ppage);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page for annotation");
        float target_cx = (x0 + x1) / 2.0f;
        float target_cy = (y0 + y1) / 2.0f;
        for (pdf_annot *annot = pdf_first_annot(ctx, ppage); annot; annot = pdf_next_annot(ctx, annot)) {
            if (pdf_annot_type(ctx, annot) != PDF_ANNOT_STAMP) continue;
            // pdf_annot_rect's getter reports this mirrored vertically for a Stamp annotation
            // loaded from an existing file (same mismatch as in mupdf_pdf_stamp_image_annot);
            // read the dictionary entry directly instead.
            fz_rect r = pdf_dict_get_rect(ctx, pdf_annot_obj(ctx, annot), PDF_NAME(Rect));
            float cx = (r.x0 + r.x1) / 2.0f;
            float cy = (r.y0 + r.y1) / 2.0f;
            float dx = cx - target_cx;
            float dy = cy - target_cy;
            if (dx < 0) dx = -dx;
            if (dy < 0) dy = -dy;
            if (dx < 2.0f && dy < 2.0f) {
                *out_found = 1;
                break;
            }
        }
    } fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_save(fz_context *ctx, fz_document *doc, const char *path, const char **out_error) {
    if (!ctx || !doc || !path) return -1;
    pdf_page *page = NULL;
    fz_var(page);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        pdf_calculate_form(ctx, pdoc);
        int page_count = pdf_count_pages(ctx, pdoc);
        for (int p = 0; p < page_count; p++) {
            page = pdf_load_page(ctx, pdoc, p);
            if (page) {
                pdf_update_page(ctx, page);
                for (pdf_annot *annot = pdf_first_annot(ctx, page); annot; annot = pdf_next_annot(ctx, annot)) {
                    ensure_annot_appearance_resources(ctx, pdoc, annot);
                    pdf_obj *annot_obj = pdf_annot_obj(ctx, annot);
                    if (annot_obj) {
                        pdf_dict_del(ctx, annot_obj, PDF_NAME(CL));
                        if (pdf_annot_type(ctx, annot) == PDF_ANNOT_INK) {
                            pdf_dict_del(ctx, annot_obj, PDF_NAME(RD));
                        }
                    }
                }
                pdf_drop_page(ctx, page);
                page = NULL;
            }
        }
        pdf_save_document(ctx, pdoc, path, &pdf_default_write_options);
    } fz_always(ctx) {
        if (page) pdf_drop_page(ctx, page);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_save_encrypted(fz_context *ctx, fz_document *doc, const char *path, const char *password, const char **out_error) {
    if (!ctx || !doc || !path) return -1;
    pdf_page *page = NULL;
    fz_var(page);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        pdf_calculate_form(ctx, pdoc);
        int page_count = pdf_count_pages(ctx, pdoc);
        for (int p = 0; p < page_count; p++) {
            page = pdf_load_page(ctx, pdoc, p);
            if (page) {
                pdf_update_page(ctx, page);
                for (pdf_annot *annot = pdf_first_annot(ctx, page); annot; annot = pdf_next_annot(ctx, annot)) {
                    ensure_annot_appearance_resources(ctx, pdoc, annot);
                    pdf_obj *annot_obj = pdf_annot_obj(ctx, annot);
                    if (annot_obj) {
                        pdf_dict_del(ctx, annot_obj, PDF_NAME(CL));
                        if (pdf_annot_type(ctx, annot) == PDF_ANNOT_INK) {
                            pdf_dict_del(ctx, annot_obj, PDF_NAME(RD));
                        }
                    }
                }
                pdf_drop_page(ctx, page);
                page = NULL;
            }
        }
        pdf_write_options opts = pdf_default_write_options;
        if (password && *password) {
            opts.do_encrypt = PDF_ENCRYPT_AES_256;
            strncpy(opts.upwd_utf8, password, sizeof(opts.upwd_utf8) - 1);
            opts.upwd_utf8[sizeof(opts.upwd_utf8) - 1] = '\0';
            strncpy(opts.opwd_utf8, password, sizeof(opts.opwd_utf8) - 1);
            opts.opwd_utf8[sizeof(opts.opwd_utf8) - 1] = '\0';
        }
        pdf_save_document(ctx, pdoc, path, &opts);
    } fz_always(ctx) {
        if (page) pdf_drop_page(ctx, page);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_rotate_page(fz_context *ctx, fz_document *doc, int pageno, int delta_degrees, const char **out_error) {
    if (!ctx || !doc) return -1;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        int count = pdf_count_pages(ctx, pdoc);
        if (pageno < 0 || pageno >= count) fz_throw(ctx, FZ_ERROR_GENERIC, "Page index out of bounds");
        pdf_obj *page_obj = pdf_lookup_page_obj(ctx, pdoc, pageno);
        if (!page_obj) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to lookup page object");
        int current_rot = pdf_dict_get_inheritable_int(ctx, page_obj, PDF_NAME(Rotate));
        int new_rot = (current_rot + delta_degrees) % 360;
        if (new_rot < 0) new_rot += 360;
        new_rot = (new_rot / 90) * 90;
        pdf_dict_put_int(ctx, page_obj, PDF_NAME(Rotate), new_rot);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_delete_page(fz_context *ctx, fz_document *doc, int pageno, const char **out_error) {
    if (!ctx || !doc) return -1;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        int count = pdf_count_pages(ctx, pdoc);
        if (count <= 1) fz_throw(ctx, FZ_ERROR_GENERIC, "Cannot delete the only page in the document");
        if (pageno < 0 || pageno >= count) fz_throw(ctx, FZ_ERROR_GENERIC, "Page index out of bounds");
        pdf_delete_page(ctx, pdoc, pageno);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_reorder_page(fz_context *ctx, fz_document *doc, int from_page, int to_page, const char **out_error) {
    if (!ctx || !doc) return -1;
    pdf_obj *page_obj = NULL;
    fz_var(page_obj);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        int count = pdf_count_pages(ctx, pdoc);
        if (from_page < 0 || from_page >= count || to_page < 0 || to_page >= count) {
            fz_throw(ctx, FZ_ERROR_GENERIC, "Page index out of bounds");
        }
        if (from_page == to_page) return 0;
        page_obj = pdf_lookup_page_obj(ctx, pdoc, from_page);
        if (!page_obj) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to lookup page object");
        pdf_keep_obj(ctx, page_obj);
        pdf_delete_page(ctx, pdoc, from_page);
        pdf_insert_page(ctx, pdoc, to_page, page_obj);
    } fz_always(ctx) {
        if (page_obj) pdf_drop_obj(ctx, page_obj);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_reorder_pages(fz_context *ctx, fz_document *doc, const int *page_indices, int count, int dest_slot, const char **out_error) {
    if (!ctx || !doc || !page_indices || count <= 0) return -1;
    pdf_obj **page_objs = NULL;
    int *sorted_indices = NULL;
    fz_var(page_objs);
    fz_var(sorted_indices);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        int total_pages = pdf_count_pages(ctx, pdoc);
        if (dest_slot < 0 || dest_slot > total_pages) {
            fz_throw(ctx, FZ_ERROR_GENERIC, "Destination slot out of bounds");
        }
        for (int i = 0; i < count; i++) {
            if (page_indices[i] < 0 || page_indices[i] >= total_pages) {
                fz_throw(ctx, FZ_ERROR_GENERIC, "Page index out of bounds");
            }
        }

        page_objs = (pdf_obj **)fz_malloc(ctx, count * sizeof(pdf_obj *));
        sorted_indices = (int *)fz_malloc(ctx, count * sizeof(int));
        for (int i = 0; i < count; i++) {
            page_objs[i] = NULL;
            sorted_indices[i] = page_indices[i];
        }

        // Retain page objects in requested selection order
        for (int i = 0; i < count; i++) {
            page_objs[i] = pdf_lookup_page_obj(ctx, pdoc, page_indices[i]);
            if (!page_objs[i]) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to lookup page object");
            pdf_keep_obj(ctx, page_objs[i]);
        }

        // Sort indices descending to delete from back to front without index shift
        for (int i = 0; i < count - 1; i++) {
            for (int j = i + 1; j < count; j++) {
                if (sorted_indices[i] < sorted_indices[j]) {
                    int tmp = sorted_indices[i];
                    sorted_indices[i] = sorted_indices[j];
                    sorted_indices[j] = tmp;
                }
            }
        }

        // Count how many selected pages were before dest_slot
        int before_slot = 0;
        for (int i = 0; i < count; i++) {
            if (page_indices[i] < dest_slot) {
                before_slot++;
            }
        }
        int insert_index = dest_slot - before_slot;

        // Delete from back to front
        for (int i = 0; i < count; i++) {
            pdf_delete_page(ctx, pdoc, sorted_indices[i]);
        }

        // Insert at target slot in original request order
        for (int i = 0; i < count; i++) {
            pdf_insert_page(ctx, pdoc, insert_index + i, page_objs[i]);
        }
    } fz_always(ctx) {
        if (page_objs) {
            for (int i = 0; i < count; i++) {
                if (page_objs[i]) pdf_drop_obj(ctx, page_objs[i]);
            }
            fz_free(ctx, page_objs);
        }
        if (sorted_indices) {
            fz_free(ctx, sorted_indices);
        }
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_delete_pages(fz_context *ctx, fz_document *doc, const int *page_indices, int count, const char **out_error) {
    if (!ctx || !doc || !page_indices || count <= 0) return -1;
    int *sorted_indices = NULL;
    fz_var(sorted_indices);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        int total_pages = pdf_count_pages(ctx, pdoc);
        if (count >= total_pages) {
            fz_throw(ctx, FZ_ERROR_GENERIC, "Cannot delete all pages in the document");
        }
        for (int i = 0; i < count; i++) {
            if (page_indices[i] < 0 || page_indices[i] >= total_pages) {
                fz_throw(ctx, FZ_ERROR_GENERIC, "Page index out of bounds");
            }
        }

        sorted_indices = (int *)fz_malloc(ctx, count * sizeof(int));
        for (int i = 0; i < count; i++) {
            sorted_indices[i] = page_indices[i];
        }

        // Sort indices descending to delete from back to front
        for (int i = 0; i < count - 1; i++) {
            for (int j = i + 1; j < count; j++) {
                if (sorted_indices[i] < sorted_indices[j]) {
                    int tmp = sorted_indices[i];
                    sorted_indices[i] = sorted_indices[j];
                    sorted_indices[j] = tmp;
                }
            }
        }

        // Delete from back to front
        for (int i = 0; i < count; i++) {
            pdf_delete_page(ctx, pdoc, sorted_indices[i]);
        }
    } fz_always(ctx) {
        if (sorted_indices) fz_free(ctx, sorted_indices);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_extract_pages(fz_context *ctx, fz_document *doc, const int *page_indices, int count, const char *out_path, const char **out_error) {
    if (!ctx || !doc || !page_indices || count <= 0 || !out_path) return -1;
    pdf_document *dst = NULL;
    fz_var(dst);
    fz_try(ctx) {
        pdf_document *src = pdf_document_from_fz_document(ctx, doc);
        if (!src) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        int src_count = pdf_count_pages(ctx, src);
        dst = pdf_create_document(ctx);
        if (!dst) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to create target PDF document");
        for (int i = 0; i < count; i++) {
            int p = page_indices[i];
            if (p < 0 || p >= src_count) {
                fz_throw(ctx, FZ_ERROR_GENERIC, "Page index out of bounds for extraction");
            }
            pdf_graft_page(ctx, dst, -1, src, p);
        }
        pdf_save_document(ctx, dst, out_path, &pdf_default_write_options);
    } fz_always(ctx) {
        if (dst) pdf_drop_document(ctx, dst);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_duplicate_pages(fz_context *ctx, fz_document *doc, const int *page_indices, int count, int *out_inserted_slot, const char **out_error) {
    if (!ctx || !doc || !page_indices || count <= 0) return -1;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        int total_pages = pdf_count_pages(ctx, pdoc);
        int max_index = -1;
        for (int i = 0; i < count; i++) {
            if (page_indices[i] < 0 || page_indices[i] >= total_pages) {
                fz_throw(ctx, FZ_ERROR_GENERIC, "Page index out of bounds for duplication");
            }
            if (page_indices[i] > max_index) {
                max_index = page_indices[i];
            }
        }
        int insert_slot = max_index + 1;
        for (int i = 0; i < count; i++) {
            pdf_graft_page(ctx, pdoc, insert_slot + i, pdoc, page_indices[i]);
        }
        if (out_inserted_slot) *out_inserted_slot = insert_slot;
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_import_pages(fz_context *ctx, fz_document *doc, const char *src_path, int insert_slot, int *out_imported_count, const char **out_error) {
    if (!ctx || !doc || !src_path) return -1;
    fz_document *src_doc = NULL;
    fz_var(src_doc);
    fz_try(ctx) {
        pdf_document *dst_pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!dst_pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Target document is not a PDF");
        int dst_count = pdf_count_pages(ctx, dst_pdoc);
        if (insert_slot < 0 || insert_slot > dst_count) {
            fz_throw(ctx, FZ_ERROR_GENERIC, "Insert slot out of bounds");
        }
        src_doc = fz_open_document(ctx, src_path);
        if (!src_doc) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to open source document");
        pdf_document *src_pdoc = pdf_document_from_fz_document(ctx, src_doc);
        if (!src_pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Source file is not a valid PDF");
        int src_count = pdf_count_pages(ctx, src_pdoc);
        for (int i = 0; i < src_count; i++) {
            pdf_graft_page(ctx, dst_pdoc, insert_slot + i, src_pdoc, i);
        }
        if (out_imported_count) *out_imported_count = src_count;
    } fz_always(ctx) {
        if (src_doc) fz_drop_document(ctx, src_doc);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

// Store & Memory Management
void mupdf_context_empty_store(fz_context *ctx) {
    if (ctx) fz_empty_store(ctx);
}

int mupdf_context_shrink_store(fz_context *ctx, unsigned int percent) {
    if (!ctx) return 0;
    return fz_shrink_store(ctx, percent);
}

void mupdf_free(fz_context *ctx, void *ptr) {
    if (ctx && ptr) fz_free(ctx, ptr);
}

char *mupdf_stext_page_text(fz_context *ctx, fz_stext_page *page) {
    if (!ctx || !page) return NULL;
    fz_buffer *buf = NULL;
    fz_output *out = NULL;
    char *result = NULL;
    fz_var(buf);
    fz_var(out);
    fz_try(ctx) {
        buf = fz_new_buffer(ctx, 1024);
        out = fz_new_output_with_buffer(ctx, buf);
        fz_print_stext_page_as_text(ctx, out, page);
        fz_close_output(ctx, out);
        fz_drop_output(ctx, out);
        out = NULL;
        
        size_t len = 0;
        unsigned char *data = NULL;
        len = fz_buffer_storage(ctx, buf, &data);
        result = (char *)fz_malloc(ctx, len + 1);
        memcpy(result, data, len);
        result[len] = '\0';
        fz_drop_buffer(ctx, buf);
        buf = NULL;
    } fz_catch(ctx) {
        if (out) fz_drop_output(ctx, out);
        if (buf) fz_drop_buffer(ctx, buf);
        if (result) fz_free(ctx, result);
        return NULL;
    }
    return result;
}

// AcroForms & Interactive Form Widgets

int mupdf_page_count_widgets(fz_context *ctx, fz_document *doc, int pageno, int *out_count, const char **out_error) {
    if (!ctx || !doc || !out_count) return -1;
    *out_count = 0;
    // Unlike the widget accessors below, "not a PDF" / "page failed to load" are treated as a
    // successful zero-widget count here, not an error — so this branches around the lookup instead
    // of throwing.
    pdf_page *ppage = NULL;
    fz_var(ppage);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (pdoc) {
            ppage = pdf_load_page(ctx, pdoc, pageno);
        }
        if (ppage) {
            pdf_annot *w = pdf_first_widget(ctx, ppage);
            int count = 0;
            while (w) {
                count++;
                w = pdf_next_widget(ctx, w);
            }
            *out_count = count;
        }
    } fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_page_get_widget_info(fz_context *ctx, fz_document *doc, int pageno, int widget_index,
                               int *out_type, fz_rect *out_rect, char **out_name, char **out_value,
                               int *out_flags, float *out_font_size,
                               int *out_max_len, int *out_text_align,
                               const char **out_error) {
    if (!ctx || !doc) return -1;
    if (out_type) *out_type = 0;
    if (out_rect) *out_rect = fz_empty_rect;
    if (out_name) *out_name = NULL;
    if (out_value) *out_value = NULL;
    if (out_flags) *out_flags = 0;
    if (out_font_size) *out_font_size = 0.0f;
    if (out_max_len) *out_max_len = 0;
    if (out_text_align) *out_text_align = 0;
    
    pdf_page *ppage = NULL;
    fz_var(ppage);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page");

        pdf_annot *w = pdf_first_widget(ctx, ppage);
        int idx = 0;
        while (w && idx < widget_index) {
            w = pdf_next_widget(ctx, w);
            idx++;
        }

        if (!w) fz_throw(ctx, FZ_ERROR_GENERIC, "Widget not found");

        if (out_type) {
            *out_type = (int)pdf_widget_type(ctx, w);
        }
        if (out_rect) {
            *out_rect = pdf_bound_widget(ctx, w);
        }
        if (out_font_size) {
            const char *da_font = NULL;
            float fsize = 0.0f;
            int da_n = 0;
            float da_color[4] = {0.0f, 0.0f, 0.0f, 0.0f};
            pdf_annot_default_appearance(ctx, w, &da_font, &fsize, &da_n, da_color);
            *out_font_size = fsize;
        }
        if (out_max_len) {
            if (pdf_widget_type(ctx, w) == PDF_WIDGET_TYPE_TEXT) {
                *out_max_len = pdf_text_widget_max_len(ctx, w);
            }
        }

        pdf_obj *field = pdf_annot_obj(ctx, w);
        if (field) {
            if (out_flags) {
                *out_flags = pdf_field_flags(ctx, field);
            }
            if (out_text_align) {
                pdf_obj *q_obj = pdf_dict_gets_inheritable(ctx, field, "Q");
                if (q_obj) {
                    *out_text_align = pdf_to_int(ctx, q_obj);
                }
            }
            if (out_name) {
                char *fname = pdf_load_field_name(ctx, field);
                if (fname) {
                    *out_name = strdup(fname);
                    fz_free(ctx, fname);
                }
            }
            if (out_value) {
                enum pdf_widget_type wtype = pdf_widget_type(ctx, w);
                if (wtype == PDF_WIDGET_TYPE_CHECKBOX || wtype == PDF_WIDGET_TYPE_RADIOBUTTON) {
                    // pdf_field_value reports the shared field's /V, which for a radio group is
                    // one kid's on-name — every sibling would wrongly report that same non-"Off"
                    // value as its own. /AS is each kid's own actual appearance state.
                    pdf_obj *as_obj = pdf_dict_get(ctx, field, PDF_NAME(AS));
                    const char *as_name = as_obj ? pdf_to_name(ctx, as_obj) : NULL;
                    *out_value = strdup(as_name && as_name[0] != '\0' ? as_name : "Off");
                } else {
                    const char *val = pdf_field_value(ctx, field);
                    if (val) {
                        *out_value = strdup(val);
                    }
                }
            }
        }
    } fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_page_set_widget_value(fz_context *ctx, fz_document *doc, int pageno, int widget_index,
                                const char *value, const char **out_error) {
    if (!ctx || !doc || !value) return -1;
    pdf_page *ppage = NULL;
    fz_var(ppage);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page");

        pdf_annot *w = pdf_first_widget(ctx, ppage);
        int idx = 0;
        while (w && idx < widget_index) {
            w = pdf_next_widget(ctx, w);
            idx++;
        }

        if (!w) fz_throw(ctx, FZ_ERROR_GENERIC, "Widget not found");

        enum pdf_widget_type wtype = pdf_widget_type(ctx, w);
        pdf_obj *field = pdf_annot_obj(ctx, w);
        
        if (wtype == PDF_WIDGET_TYPE_TEXT) {
            pdf_set_text_field_value(ctx, w, value);
        } else if (wtype == PDF_WIDGET_TYPE_COMBOBOX || wtype == PDF_WIDGET_TYPE_LISTBOX) {
            pdf_set_choice_field_value(ctx, w, value);
        } else if (wtype == PDF_WIDGET_TYPE_CHECKBOX || wtype == PDF_WIDGET_TYPE_RADIOBUTTON) {
            int is_off = (strcmp(value, "Off") == 0 || strcmp(value, "0") == 0 || strcmp(value, "") == 0 || strcasecmp(value, "false") == 0);
            pdf_obj *on_obj = field ? pdf_button_field_on_state(ctx, field) : NULL;
            const char *on_str = on_obj ? pdf_to_name(ctx, on_obj) : NULL;
            const char *target_state = is_off ? "Off" : (on_str && on_str[0] != '\0' ? on_str : (value && value[0] != '\0' ? value : "Yes"));
            
            // In PDF forms, radio button widgets belonging to a radio button group share a parent
            // field whose /FT is /Btn and has the PDF_BTN_FIELD_IS_RADIO flag. Only in that case does
            // setting the parent field value properly synchronize siblings (turning the previous one off).
            // For checkboxes or widgets under structural parents (like Page or Subform dictionaries in f1040.pdf),
            // the target must remain the widget's own field — otherwise setting the value on a parent
            // subform cascades and overwrites all descendant text fields with the button state!
            pdf_obj *valueField = field;
            if (field && wtype == PDF_WIDGET_TYPE_RADIOBUTTON) {
                pdf_obj *parent = pdf_dict_get(ctx, field, PDF_NAME(Parent));
                if (parent) {
                    int ptype = pdf_field_type(ctx, parent);
                    int pflags = pdf_field_flags(ctx, parent);
                    if (ptype == PDF_WIDGET_TYPE_RADIOBUTTON || (pflags & PDF_BTN_FIELD_IS_RADIO) != 0) {
                        valueField = parent;
                    }
                }
            }
            if (valueField) {
                pdf_set_field_value(ctx, pdoc, valueField, target_state, 0);
            }

            // If field value did not match desired state, fallback to native pdf_toggle_widget
            const char *new_val = field ? pdf_field_value(ctx, field) : NULL;
            int new_is_off = (!new_val || strcmp(new_val, "Off") == 0 || strcmp(new_val, "") == 0);
            if ((is_off && !new_is_off) || (!is_off && new_is_off)) {
                pdf_toggle_widget(ctx, w);
            }
            
            // Explicitly set /AS (Appearance State) on both the field and the widget annotation.
            // External PDF engines (e.g. Apple Quartz / PDFKit printing) render the /AP stream matching /AS.
            pdf_obj *state_name_obj = pdf_new_name(ctx, target_state);
            if (field) {
                pdf_dict_puts(ctx, field, "AS", state_name_obj);
            }
            pdf_obj *annot_obj = pdf_annot_obj(ctx, w);
            if (annot_obj && annot_obj != field) {
                pdf_dict_puts(ctx, annot_obj, "AS", state_name_obj);
            }
            pdf_drop_obj(ctx, state_name_obj);
        } else {
            if (field) {
                pdf_set_field_value(ctx, pdoc, field, value, 0);
            }
        }
        
        pdf_update_widget(ctx, w);
        pdf_update_annot(ctx, w);
        pdf_update_page(ctx, ppage);
        pdf_calculate_form(ctx, pdoc);
    } fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_document_reset_form(fz_context *ctx, fz_document *doc, const char **out_error) {
    if (!ctx || !doc) return -1;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        pdf_reset_form(ctx, pdoc, NULL, 0);
        pdf_calculate_form(ctx, pdoc);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_page_get_choice_options(fz_context *ctx, fz_document *doc, int pageno, int widget_index,
                                  char ***out_options, int *out_count, const char **out_error) {
    if (!ctx || !doc || !out_options || !out_count) return -1;
    *out_options = NULL;
    *out_count = 0;

    pdf_page *ppage = NULL;
    fz_var(ppage);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page");

        pdf_annot *w = pdf_first_widget(ctx, ppage);
        int idx = 0;
        while (w && idx < widget_index) {
            w = pdf_next_widget(ctx, w);
            idx++;
        }

        if (!w) fz_throw(ctx, FZ_ERROR_GENERIC, "Widget not found");

        int n = pdf_choice_widget_options(ctx, w, 0, NULL);
        if (n > 0) {
            const char **c_opts = malloc(n * sizeof(const char *));
            if (c_opts) {
                pdf_choice_widget_options(ctx, w, 0, c_opts);
                char **result = malloc(n * sizeof(char *));
                if (!result) {
                    free(c_opts);
                    fz_throw(ctx, FZ_ERROR_GENERIC, "Out of memory allocating choice options");
                }
                for (int i = 0; i < n; i++) {
                    result[i] = strdup(c_opts[i] ? c_opts[i] : "");
                }
                free(c_opts);
                *out_options = result;
                *out_count = n;
            }
        }
    } fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

void mupdf_free_choice_options(fz_context *ctx, char **options, int count) {
    (void)ctx;
    if (options) {
        for (int i = 0; i < count; i++) {
            if (options[i]) free(options[i]);
        }
        free(options);
    }
}

// Document Metadata, Encryption & Security Permissions
int mupdf_document_get_metadata(fz_context *ctx, fz_document *doc, mupdf_document_metadata *out_meta, const char **out_error) {
    if (!ctx || !doc || !out_meta) {
        if (out_error) *out_error = "Invalid parameters";
        return -1;
    }
    memset(out_meta, 0, sizeof(*out_meta));
    fz_try(ctx) {
        fz_lookup_metadata(ctx, doc, FZ_META_FORMAT, out_meta->format, sizeof(out_meta->format));
        fz_lookup_metadata(ctx, doc, FZ_META_ENCRYPTION, out_meta->encryption, sizeof(out_meta->encryption));
        fz_lookup_metadata(ctx, doc, FZ_META_INFO_TITLE, out_meta->title, sizeof(out_meta->title));
        fz_lookup_metadata(ctx, doc, FZ_META_INFO_AUTHOR, out_meta->author, sizeof(out_meta->author));
        fz_lookup_metadata(ctx, doc, FZ_META_INFO_SUBJECT, out_meta->subject, sizeof(out_meta->subject));
        fz_lookup_metadata(ctx, doc, FZ_META_INFO_KEYWORDS, out_meta->keywords, sizeof(out_meta->keywords));
        fz_lookup_metadata(ctx, doc, FZ_META_INFO_CREATOR, out_meta->creator, sizeof(out_meta->creator));
        fz_lookup_metadata(ctx, doc, FZ_META_INFO_PRODUCER, out_meta->producer, sizeof(out_meta->producer));
        fz_lookup_metadata(ctx, doc, FZ_META_INFO_CREATIONDATE, out_meta->creation_date, sizeof(out_meta->creation_date));
        fz_lookup_metadata(ctx, doc, FZ_META_INFO_MODIFICATIONDATE, out_meta->mod_date, sizeof(out_meta->mod_date));
        
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (pdoc) {
            out_meta->is_encrypted = (pdoc->crypt != NULL);
            out_meta->pdf_version = pdoc->version;
        }
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_document_get_permissions(fz_context *ctx, fz_document *doc, mupdf_document_permissions *out_perms, const char **out_error) {
    if (!ctx || !doc || !out_perms) {
        if (out_error) *out_error = "Invalid parameters";
        return -1;
    }
    memset(out_perms, 0, sizeof(*out_perms));
    fz_try(ctx) {
        out_perms->can_print = fz_has_permission(ctx, doc, FZ_PERMISSION_PRINT);
        out_perms->can_modify = fz_has_permission(ctx, doc, FZ_PERMISSION_EDIT);
        out_perms->can_copy = fz_has_permission(ctx, doc, FZ_PERMISSION_COPY);
        out_perms->can_annotate = fz_has_permission(ctx, doc, FZ_PERMISSION_ANNOTATE);
        out_perms->can_fill_forms = fz_has_permission(ctx, doc, FZ_PERMISSION_FORM);
        out_perms->can_accessibility = fz_has_permission(ctx, doc, FZ_PERMISSION_ACCESSIBILITY);
        out_perms->can_assemble = fz_has_permission(ctx, doc, FZ_PERMISSION_ASSEMBLE);
        out_perms->can_print_high_quality = fz_has_permission(ctx, doc, FZ_PERMISSION_PRINT_HQ);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_page_get_boxes(fz_context *ctx, fz_document *doc, int pageno, mupdf_page_boxes *out_boxes, const char **out_error) {
    if (!ctx || !doc || !out_boxes) {
        if (out_error) *out_error = "Invalid parameters";
        return -1;
    }
    memset(out_boxes, 0, sizeof(*out_boxes));
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) {
            fz_page *page = fz_load_page(ctx, doc, pageno);
            fz_rect r = fz_bound_page(ctx, page);
            fz_drop_page(ctx, page);
            out_boxes->media_box = r;
            out_boxes->crop_box = r;
            out_boxes->has_crop_box = 1;
            return 0;
        }

        pdf_obj *page_obj = pdf_lookup_page_obj(ctx, pdoc, pageno);
        if (!page_obj) {
            fz_throw(ctx, FZ_ERROR_GENERIC, "Page object not found");
        }

        pdf_obj *media_obj = pdf_dict_get_inheritable(ctx, page_obj, PDF_NAME(MediaBox));
        if (media_obj) {
            out_boxes->media_box = pdf_to_rect(ctx, media_obj);
        } else {
            out_boxes->media_box = fz_make_rect(0, 0, 612, 792);
        }

        pdf_obj *crop_obj = pdf_dict_get_inheritable(ctx, page_obj, PDF_NAME(CropBox));
        if (crop_obj) {
            out_boxes->crop_box = pdf_to_rect(ctx, crop_obj);
            out_boxes->has_crop_box = 1;
        } else {
            out_boxes->crop_box = out_boxes->media_box;
            out_boxes->has_crop_box = 0;
        }

        pdf_obj *bleed_obj = pdf_dict_get(ctx, page_obj, PDF_NAME(BleedBox));
        if (bleed_obj) {
            out_boxes->bleed_box = pdf_to_rect(ctx, bleed_obj);
            out_boxes->has_bleed_box = 1;
        } else {
            out_boxes->bleed_box = out_boxes->crop_box;
            out_boxes->has_bleed_box = 0;
        }

        pdf_obj *trim_obj = pdf_dict_get(ctx, page_obj, PDF_NAME(TrimBox));
        if (trim_obj) {
            out_boxes->trim_box = pdf_to_rect(ctx, trim_obj);
            out_boxes->has_trim_box = 1;
        } else {
            out_boxes->trim_box = out_boxes->crop_box;
            out_boxes->has_trim_box = 0;
        }

        pdf_obj *art_obj = pdf_dict_get(ctx, page_obj, PDF_NAME(ArtBox));
        if (art_obj) {
            out_boxes->art_box = pdf_to_rect(ctx, art_obj);
            out_boxes->has_art_box = 1;
        } else {
            out_boxes->art_box = out_boxes->crop_box;
            out_boxes->has_art_box = 0;
        }
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

static int is_subset_name(const char *name) {
    if (!name || strlen(name) < 7) return 0;
    if (name[6] != '+') return 0;
    for (int i = 0; i < 6; i++) {
        if (name[i] < 'A' || name[i] > 'Z') return 0;
    }
    return 1;
}

static void add_font_if_unique(mupdf_font_entry **entries, int *count, int *capacity,
                               const char *name, const char *subtype, const char *encoding,
                               int is_embedded, int is_subset) {
    if (!name || !*name) name = "Unnamed Font";
    if (!subtype || !*subtype) subtype = "Unknown";
    if (!encoding || !*encoding) encoding = "Standard";

    // Deduplicate
    for (int i = 0; i < *count; i++) {
        if (strcmp((*entries)[i].name, name) == 0 &&
            strcmp((*entries)[i].subtype, subtype) == 0) {
            if (is_embedded) (*entries)[i].is_embedded = 1;
            if (is_subset) (*entries)[i].is_subset = 1;
            return;
        }
    }

    if (*count >= *capacity) {
        int new_cap = (*capacity == 0) ? 16 : (*capacity * 2);
        mupdf_font_entry *new_arr = (mupdf_font_entry *)realloc(*entries, new_cap * sizeof(mupdf_font_entry));
        if (!new_arr) return;
        *entries = new_arr;
        *capacity = new_cap;
    }

    mupdf_font_entry *e = &(*entries)[*count];
    memset(e, 0, sizeof(*e));
    strncpy(e->name, name, sizeof(e->name) - 1);
    strncpy(e->subtype, subtype, sizeof(e->subtype) - 1);
    strncpy(e->encoding, encoding, sizeof(e->encoding) - 1);
    e->is_embedded = is_embedded;
    e->is_subset = is_subset;
    (*count)++;
}

static void inspect_font_dict(fz_context *ctx, pdf_obj *font_obj,
                              mupdf_font_entry **entries, int *count, int *capacity) {
    if (!font_obj) return;
    const char *base_font = pdf_dict_get_name(ctx, font_obj, PDF_NAME(BaseFont));
    const char *subtype = pdf_dict_get_name(ctx, font_obj, PDF_NAME(Subtype));
    pdf_obj *enc_obj = pdf_dict_get(ctx, font_obj, PDF_NAME(Encoding));
    const char *encoding = NULL;
    if (pdf_is_name(ctx, enc_obj)) {
        encoding = pdf_to_name(ctx, enc_obj);
    }

    pdf_obj *desc = pdf_dict_get(ctx, font_obj, PDF_NAME(FontDescriptor));

    if (subtype && strcmp(subtype, "Type0") == 0) {
        pdf_obj *descendants = pdf_dict_get(ctx, font_obj, PDF_NAME(DescendantFonts));
        if (pdf_is_array(ctx, descendants) && pdf_array_len(ctx, descendants) > 0) {
            pdf_obj *cid = pdf_array_get(ctx, descendants, 0);
            if (!base_font || !*base_font) {
                base_font = pdf_dict_get_name(ctx, cid, PDF_NAME(BaseFont));
            }
            if (!desc) {
                desc = pdf_dict_get(ctx, cid, PDF_NAME(FontDescriptor));
            }
        }
    }

    int is_embedded = 0;
    int is_subset = is_subset_name(base_font);
    if (is_subset) is_embedded = 1;

    if (desc) {
        if (pdf_dict_get(ctx, desc, PDF_NAME(FontFile)) ||
            pdf_dict_get(ctx, desc, PDF_NAME(FontFile2)) ||
            pdf_dict_get(ctx, desc, PDF_NAME(FontFile3))) {
            is_embedded = 1;
        }
    }

    add_font_if_unique(entries, count, capacity, base_font, subtype, encoding, is_embedded, is_subset);
}

int mupdf_document_get_fonts(fz_context *ctx, fz_document *doc, mupdf_font_list *out_fonts, const char **out_error) {
    if (!ctx || !doc || !out_fonts) {
        if (out_error) *out_error = "Invalid parameters";
        return -1;
    }
    out_fonts->fonts = NULL;
    out_fonts->count = 0;

    mupdf_font_entry *entries = NULL;
    int count = 0;
    int capacity = 0;

    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) {
            out_fonts->fonts = NULL;
            out_fonts->count = 0;
            return 0;
        }

        int num_pages = pdf_count_pages(ctx, pdoc);
        for (int p = 0; p < num_pages; p++) {
            pdf_obj *page_obj = pdf_lookup_page_obj(ctx, pdoc, p);
            if (!page_obj) continue;
            pdf_obj *res = pdf_dict_get_inheritable(ctx, page_obj, PDF_NAME(Resources));
            if (!res) continue;
            pdf_obj *fonts = pdf_dict_get(ctx, res, PDF_NAME(Font));
            if (!fonts) continue;

            int n = pdf_dict_len(ctx, fonts);
            for (int i = 0; i < n; i++) {
                pdf_obj *font_obj = pdf_dict_get_val(ctx, fonts, i);
                inspect_font_dict(ctx, font_obj, &entries, &count, &capacity);
            }
        }

        out_fonts->fonts = entries;
        out_fonts->count = count;
    } fz_catch(ctx) {
        if (entries) free(entries);
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

void mupdf_free_font_list(fz_context *ctx, mupdf_font_list *fonts) {
    (void)ctx;
    if (fonts) {
        if (fonts->fonts) {
            free(fonts->fonts);
            fonts->fonts = NULL;
        }
        fonts->count = 0;
    }
}


