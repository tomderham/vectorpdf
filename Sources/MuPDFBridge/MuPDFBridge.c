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

#include "include/MuPDFBridge.h"
#include "TextClipFilter.h"
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <os/lock.h>
#include <time.h>

// Thread Synchronization Locks for MuPDF context cloning. Every fz_malloc, fz_free and reference
// count takes FZ_LOCK_ALLOC, so it is contended whenever several threads work at once;
// os_unfair_lock hands it over much faster than a default pthread mutex, whose fair hand-off
// policy suspends a thread on every contended lock.
static os_unfair_lock g_mupdf_locks[FZ_LOCK_MAX];

static void mupdf_lock(void *user, int lock) {
    if (lock >= 0 && lock < FZ_LOCK_MAX) {
        os_unfair_lock_lock(&g_mupdf_locks[lock]);
    }
}

static void mupdf_unlock(void *user, int lock) {
    if (lock >= 0 && lock < FZ_LOCK_MAX) {
        os_unfair_lock_unlock(&g_mupdf_locks[lock]);
    }
}

static void mupdf_quiet_warning(void *user, const char *message) {
    // Suppress benign PDF stream warnings (e.g. premature flate filter end, duplicate ICC links)
    (void)user;
    (void)message;
}

// Context Lifecycle
fz_context *mupdf_context_create(size_t max_store_bytes) {
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

static void mupdf_independent_lock(void *user, int lock);

fz_context *mupdf_context_clone(fz_context *base) {
    if (!base) return NULL;
    // Independent contexts must not be cloned: see mupdf_context_drop_independent.
    if (base->locks.lock == mupdf_independent_lock) return NULL;
    fz_context *ctx = fz_clone_context(base);
    if (ctx) {
        fz_set_warning_callback(ctx, mupdf_quiet_warning, NULL);
    }
    return ctx;
}

void mupdf_context_drop(fz_context *ctx) {
    if (ctx) fz_drop_context(ctx);
}

// Independent contexts: their own store, fonts and ALLOC/GLYPHCACHE locks, so threads using them
// don't wait on each other's allocations and reference counts as cloned contexts do. FREETYPE stays
// shared with every other context, because MuPDF hands HarfBuzz and OpenJPEG their context through
// globals guarded by it. Mixing own and shared locks can't deadlock because MuPDF only takes them in
// increasing lock-number order; never map two lock numbers onto one os_unfair_lock (not recursive).
static void mupdf_independent_lock(void *user, int lock) {
    if (lock == FZ_LOCK_FREETYPE) {
        mupdf_lock(NULL, lock);
    } else if (lock >= 0 && lock < FZ_LOCK_MAX) {
        os_unfair_lock_lock(&((os_unfair_lock *)user)[lock]);
    }
}

static void mupdf_independent_unlock(void *user, int lock) {
    if (lock == FZ_LOCK_FREETYPE) {
        mupdf_unlock(NULL, lock);
    } else if (lock >= 0 && lock < FZ_LOCK_MAX) {
        os_unfair_lock_unlock(&((os_unfair_lock *)user)[lock]);
    }
}

fz_context *mupdf_context_create_independent(size_t max_store_bytes) {
    os_unfair_lock *own = calloc(FZ_LOCK_MAX, sizeof(os_unfair_lock));
    if (!own) return NULL;

    fz_locks_context locks;
    locks.user = own;
    locks.lock = mupdf_independent_lock;
    locks.unlock = mupdf_independent_unlock;

    size_t store = (max_store_bytes > 0) ? max_store_bytes : (32 * 1024 * 1024);
    fz_context *ctx = fz_new_context(NULL, &locks, store);
    if (!ctx) {
        free(own);
        return NULL;
    }
    fz_set_warning_callback(ctx, mupdf_quiet_warning, NULL);
    fz_register_document_handlers(ctx);
    return ctx;
}

// Frees the context's own locks with it, so a clone (which would share them) would be left using
// freed memory, and its threads would contend on ALLOC again, which these contexts exist to avoid.
void mupdf_context_drop_independent(fz_context *ctx) {
    if (!ctx) return;
    void *own = ctx->locks.user;
    fz_drop_context(ctx);
    free(own);
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

int mupdf_document_is_pdf(fz_context *ctx, fz_document *doc) {
    if (!ctx || !doc) return 0;
    return pdf_document_from_fz_document(ctx, doc) != NULL;
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

/* The same, leaving out the annotations numbered in `hidden`: the canvas draws those itself
 * while they're being edited. */
int mupdf_display_list_create_hiding(fz_context *ctx, fz_page *page, const int *hidden, int hidden_count, fz_display_list **out_list, const char **out_error) {
    if (hidden_count <= 0) return mupdf_display_list_create(ctx, page, out_list, out_error);
    if (!ctx || !page || !out_list) return -1;
    *out_list = NULL;
    fz_display_list *list = NULL;
    fz_device *dev = NULL;
    fz_var(list);
    fz_var(dev);
    fz_try(ctx) {
        list = fz_new_display_list(ctx, fz_bound_page(ctx, page));
        dev = fz_new_list_device(ctx, list);
        fz_run_page_contents(ctx, page, dev, fz_identity, NULL);
        pdf_page *ppage = pdf_page_from_fz_page(ctx, page);
        if (ppage) {
            for (pdf_annot *a = pdf_first_annot(ctx, ppage); a; a = pdf_next_annot(ctx, a)) {
                int num = pdf_to_num(ctx, pdf_annot_obj(ctx, a));
                int skip = 0;
                for (int i = 0; i < hidden_count && !skip; i++) skip = hidden[i] == num;
                if (!skip) pdf_run_annot(ctx, a, dev, fz_identity, NULL);
            }
        } else {
            fz_run_page_annots(ctx, page, dev, fz_identity, NULL);
        }
        fz_run_page_widgets(ctx, page, dev, fz_identity, NULL);
        fz_close_device(ctx, dev);
        *out_list = list;
        list = NULL;
    } fz_always(ctx) {
        fz_drop_device(ctx, dev);
        fz_drop_display_list(ctx, list);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
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
    *out_pixmap = NULL;
    fz_pixmap *pix = NULL;
    fz_device *dev = NULL;
    fz_var(pix);
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
        pix = fz_new_pixmap_with_bbox(ctx, fz_device_rgb(ctx), ibbox, NULL, 0);
        fz_clear_pixmap_with_value(ctx, pix, 0xff);
        dev = fz_new_draw_device(ctx, ctm, pix);
        fz_run_page(ctx, page, dev, fz_identity, NULL);
        fz_close_device(ctx, dev);
        fz_drop_device(ctx, dev);
        dev = NULL;
        *out_pixmap = pix;
        pix = NULL;
    } fz_always(ctx) {
        if (dev) {
            fz_try(ctx) { fz_close_device(ctx, dev); } fz_catch(ctx) {}
            fz_drop_device(ctx, dev);
        }
    } fz_catch(ctx) {
        if (pix) fz_drop_pixmap(ctx, pix);
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_render_display_list_rect(fz_context *ctx, fz_display_list *list, float scale,
                                   float x0, float y0, float x1, float y1,
                                   fz_pixmap **out_pixmap, const char **out_error) {
    if (!ctx || !list || !out_pixmap) return -1;
    *out_pixmap = NULL;
    fz_pixmap *pix = NULL;
    fz_device *dev = NULL;
    fz_var(pix);
    fz_var(dev);
    fz_try(ctx) {
        fz_matrix ctm = fz_scale(scale, scale);
        fz_rect trect = fz_transform_rect(fz_make_rect(fminf(x0, x1), fminf(y0, y1), fmaxf(x0, x1), fmaxf(y0, y1)), ctm);
        pix = fz_new_pixmap_with_bbox(ctx, fz_device_rgb(ctx), fz_round_rect(trect), NULL, 0);
        fz_clear_pixmap_with_value(ctx, pix, 0xff);
        dev = fz_new_draw_device(ctx, fz_identity, pix);
        // The scissor rect lets the display list skip everything outside the region.
        fz_run_display_list(ctx, list, dev, ctm, trect, NULL);
        fz_close_device(ctx, dev);
        fz_drop_device(ctx, dev);
        dev = NULL;
        *out_pixmap = pix;
        pix = NULL;
    } fz_always(ctx) {
        if (dev) {
            fz_try(ctx) { fz_close_device(ctx, dev); } fz_catch(ctx) {}
            fz_drop_device(ctx, dev);
        }
    } fz_catch(ctx) {
        if (pix) fz_drop_pixmap(ctx, pix);
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
        /* No FZ_STEXT_DEHYPHENATE: hyphenated words are joined in Swift (LineJoin), which skips
         * margin line numbers; MuPDF's plain text would glue the next line number on ("divi4"). */
        opts.flags = FZ_STEXT_PRESERVE_WHITESPACE | FZ_STEXT_PRESERVE_IMAGES | FZ_STEXT_COLLECT_VECTORS | FZ_STEXT_LAZY_VECTORS;
        /* Without the text the page's clipping paths hide, which MuPDF would include. */
        *out_stext = vp_new_stext_page_clipped(ctx, page, NULL, &opts);
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
        opts.flags = FZ_STEXT_PRESERVE_WHITESPACE | FZ_STEXT_PRESERVE_IMAGES | FZ_STEXT_COLLECT_VECTORS | FZ_STEXT_LAZY_VECTORS;
        *out_stext = vp_new_stext_page_clipped(ctx, NULL, list, &opts);
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

uint32_t mupdf_stext_block_vector_flags(fz_stext_block *block) {
    if (!block || block->type != FZ_STEXT_BLOCK_VECTOR) return 0;
    return block->u.v.flags;
}

uint32_t mupdf_stext_block_vector_argb(fz_stext_block *block) {
    if (!block || block->type != FZ_STEXT_BLOCK_VECTOR) return 0;
    return block->u.v.argb;
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

int mupdf_stext_char_is_bold(fz_context *ctx, fz_stext_char *ch) {
    if (!ch) return 0;
    if (ch->flags & FZ_STEXT_BOLD) return 1;
    if (ctx && ch->font) {
        return fz_font_is_bold(ctx, ch->font);
    }
    return 0;
}

int mupdf_stext_char_is_italic(fz_context *ctx, fz_stext_char *ch) {
    if (!ch) return 0;
    if (ctx && ch->font) {
        return fz_font_is_italic(ctx, ch->font);
    }
    return 0;
}

const char *mupdf_stext_char_font_name(fz_context *ctx, fz_stext_char *ch) {
    if (!ch || !ch->font || !ctx) return "";
    return fz_font_name(ctx, ch->font);
}

uint32_t mupdf_stext_char_color(fz_stext_char *ch) {
    return ch ? ch->argb : 0xff000000;
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
    fz_location loc = fz_make_location(-1, -1);
    fz_try(ctx) {
        // fz_resolve_link resolves the #fragment of any URI in this document, so a web link like
        // https://…/rfc9110#section-2 would land on this document's own section 2.
        if (!fz_is_external_link(ctx, uri))
            loc = fz_resolve_link(ctx, doc, uri, &x, &y);
    } fz_catch(ctx) {
        loc = fz_make_location(-1, -1);
    }
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

// ---------------------------------------------------------------------------------------------
// Shared helpers for hand-built annotation appearance streams.
//
// Callers of the mupdf_pdf_add_* functions pass points in MuPDF's page space (top-down, origin at
// the top-left of the page). An appearance stream, though, lives in PDF default user space
// (bottom-up). Every point written into a stream therefore goes through `inv` (the inverse of
// pdf_page_transform), and /BBox is pinned to exactly the same rectangle as /Rect so a viewer maps
// the stream 1:1 onto the page, with no scaling and no offset.
// ---------------------------------------------------------------------------------------------

static fz_matrix pdf_inverse_page_ctm(fz_context *ctx, pdf_page *ppage) {
    fz_matrix ctm = fz_identity;
    pdf_page_transform(ctx, ppage, NULL, &ctm);
    return fz_invert_matrix(ctm);
}

static fz_point to_pdf_pt(fz_matrix inv, float x, float y) {
    return fz_transform_point(fz_make_point(x, y), inv);
}

// Pins /Rect (and the normal appearance's /BBox) to `union_rect` (page space) and returns the
// annotation's /AP /N stream dictionary, or NULL if the annotation has no appearance.
static pdf_obj *begin_custom_ap(fz_context *ctx, pdf_annot *annot, fz_rect union_rect, fz_matrix inv, fz_rect *out_pdf_rect) {
    pdf_obj *obj = pdf_annot_obj(ctx, annot);
    if (!obj) return NULL;
    pdf_obj *ap = pdf_dict_get(ctx, obj, PDF_NAME(AP));
    if (!ap) return NULL;
    pdf_obj *n = pdf_dict_get(ctx, ap, PDF_NAME(N));
    if (!n) return NULL;
    fz_rect r = fz_transform_rect(union_rect, inv);
    pdf_dict_put_rect(ctx, obj, PDF_NAME(Rect), r);
    pdf_dict_put_rect(ctx, n, PDF_NAME(BBox), r);
    pdf_dict_put_matrix(ctx, n, PDF_NAME(Matrix), fz_identity);
    if (out_pdf_rect) *out_pdf_rect = r;
    return n;
}

static pdf_obj *ensure_dict_entry(fz_context *ctx, pdf_document *pdoc, pdf_obj *parent, pdf_obj *key) {
    pdf_obj *d = pdf_dict_get(ctx, parent, key);
    if (!d) {
        pdf_dict_put_drop(ctx, parent, key, pdf_new_dict(ctx, pdoc, 2));
        d = pdf_dict_get(ctx, parent, key);
    }
    return d;
}

// Makes sure the stream's own /Resources lists a /Helv font — MuPDF only adds one for annotations
// that carry a /DA, so PolyLine/Polygon streams that draw a label would otherwise reference a font
// that doesn't exist.
static void ensure_helv_font(fz_context *ctx, pdf_document *pdoc, pdf_obj *n) {
    pdf_obj *res = ensure_dict_entry(ctx, pdoc, n, PDF_NAME(Resources));
    pdf_obj *fonts = ensure_dict_entry(ctx, pdoc, res, PDF_NAME(Font));
    if (!pdf_dict_gets(ctx, fonts, "Helv")) {
        pdf_obj *f = pdf_new_dict(ctx, pdoc, 4);
        fz_try(ctx) {
            pdf_dict_put(ctx, f, PDF_NAME(Type), PDF_NAME(Font));
            pdf_dict_put(ctx, f, PDF_NAME(Subtype), PDF_NAME(Type1));
            pdf_dict_put_name(ctx, f, PDF_NAME(BaseFont), "Helvetica");
            pdf_dict_put(ctx, f, PDF_NAME(Encoding), PDF_NAME(WinAnsiEncoding));
            pdf_dict_puts_drop(ctx, fonts, "Helv", pdf_add_object_drop(ctx, pdoc, f));
        } fz_catch(ctx) {
            fz_rethrow(ctx);
        }
    }
}

// Registers an ExtGState named /GSa that makes fills `alpha`-translucent while leaving strokes
// opaque, so an area's outline stays crisp over its tinted interior.
static void ensure_alpha_gs(fz_context *ctx, pdf_document *pdoc, pdf_obj *n, float alpha) {
    pdf_obj *res = ensure_dict_entry(ctx, pdoc, n, PDF_NAME(Resources));
    pdf_obj *egs = ensure_dict_entry(ctx, pdoc, res, PDF_NAME(ExtGState));
    pdf_obj *gs = pdf_new_dict(ctx, pdoc, 3);
    fz_try(ctx) {
        pdf_dict_put(ctx, gs, PDF_NAME(Type), PDF_NAME(ExtGState));
        pdf_dict_put_real(ctx, gs, PDF_NAME(CA), 1.0);
        pdf_dict_put_real(ctx, gs, PDF_NAME(ca), alpha);
        pdf_dict_puts_drop(ctx, egs, "GSa", gs);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
}

static void ap_move(fz_context *ctx, fz_buffer *b, fz_matrix inv, float x, float y) {
    fz_point p = to_pdf_pt(inv, x, y);
    fz_append_printf(ctx, b, "%g %g m\n", p.x, p.y);
}

static void ap_line(fz_context *ctx, fz_buffer *b, fz_matrix inv, float x, float y) {
    fz_point p = to_pdf_pt(inv, x, y);
    fz_append_printf(ctx, b, "%g %g l\n", p.x, p.y);
}

static void ap_rect(fz_context *ctx, fz_buffer *b, fz_matrix inv, float x0, float y0, float x1, float y1) {
    fz_rect r = fz_transform_rect(fz_make_rect(fminf(x0, x1), fminf(y0, y1), fmaxf(x0, x1), fmaxf(y0, y1)), inv);
    fz_append_printf(ctx, b, "%g %g %g %g re\n", r.x0, r.y0, r.x1 - r.x0, r.y1 - r.y0);
}

// Draws a line ending with its tip at (x, y), for a line running from there along (dx, dy). The
// sizes match the callout overlay in PDFLineEnding.path so saved and on-screen callouts agree.
static void ap_line_ending(fz_context *ctx, fz_buffer *b, fz_matrix inv, float x, float y, float dx, float dy, int style) {
    float len = hypotf(dx, dy);
    if (len <= 0.001f) return;
    float ux = dx / len, uy = dy / len;  // along the line
    float px = -uy, py = ux;             // across it
    const float L = 8.0f, W = 4.0f;
    switch (style) {
    case PDF_ANNOT_LE_OPEN_ARROW:
        ap_move(ctx, b, inv, x + ux * L + px * W, y + uy * L + py * W);
        ap_line(ctx, b, inv, x, y);
        ap_line(ctx, b, inv, x + ux * L - px * W, y + uy * L - py * W);
        fz_append_string(ctx, b, "S\n");
        break;
    case PDF_ANNOT_LE_CLOSED_ARROW:
        ap_move(ctx, b, inv, x, y);
        ap_line(ctx, b, inv, x + ux * L + px * W, y + uy * L + py * W);
        ap_line(ctx, b, inv, x + ux * L - px * W, y + uy * L - py * W);
        fz_append_string(ctx, b, "h\nf\n");
        break;
    case PDF_ANNOT_LE_BUTT:
        ap_move(ctx, b, inv, x + px * W, y + py * W);
        ap_line(ctx, b, inv, x - px * W, y - py * W);
        fz_append_string(ctx, b, "S\n");
        break;
    case PDF_ANNOT_LE_SLASH:
        ap_move(ctx, b, inv, x + (px + ux * 0.5f) * W, y + (py + uy * 0.5f) * W);
        ap_line(ctx, b, inv, x - (px + ux * 0.5f) * W, y - (py + uy * 0.5f) * W);
        fz_append_string(ctx, b, "S\n");
        break;
    case PDF_ANNOT_LE_DIAMOND:
        ap_move(ctx, b, inv, x + ux * W, y + uy * W);
        ap_line(ctx, b, inv, x + px * W, y + py * W);
        ap_line(ctx, b, inv, x - ux * W, y - uy * W);
        ap_line(ctx, b, inv, x - px * W, y - py * W);
        fz_append_string(ctx, b, "h\nf\n");
        break;
    case PDF_ANNOT_LE_SQUARE:
        ap_move(ctx, b, inv, x + (ux + px) * W * 0.75f, y + (uy + py) * W * 0.75f);
        ap_line(ctx, b, inv, x + (ux - px) * W * 0.75f, y + (uy - py) * W * 0.75f);
        ap_line(ctx, b, inv, x - (ux + px) * W * 0.75f, y - (uy + py) * W * 0.75f);
        ap_line(ctx, b, inv, x + (px - ux) * W * 0.75f, y + (py - uy) * W * 0.75f);
        fz_append_string(ctx, b, "h\nf\n");
        break;
    case PDF_ANNOT_LE_CIRCLE:
        for (int i = 0; i < 16; i++) {
            float a = (float)i * 3.14159265f / 8.0f;
            float cx = x + cosf(a) * W, cy = y + sinf(a) * W;
            if (i == 0) ap_move(ctx, b, inv, cx, cy); else ap_line(ctx, b, inv, cx, cy);
        }
        fz_append_string(ctx, b, "h\nf\n");
        break;
    default:
        break;
    }
}

// A circle needs four Bézier segments — PDF has no `arc` operator.
static void ap_circle(fz_context *ctx, fz_buffer *b, fz_matrix inv, float cx, float cy, float radius) {
    const float k = 0.5522847498f * radius;
    fz_point c = to_pdf_pt(inv, cx, cy);
    fz_append_printf(ctx, b, "%g %g m\n", c.x + radius, c.y);
    fz_append_printf(ctx, b, "%g %g %g %g %g %g c\n", c.x + radius, c.y + k, c.x + k, c.y + radius, c.x, c.y + radius);
    fz_append_printf(ctx, b, "%g %g %g %g %g %g c\n", c.x - k, c.y + radius, c.x - radius, c.y + k, c.x - radius, c.y);
    fz_append_printf(ctx, b, "%g %g %g %g %g %g c\n", c.x - radius, c.y - k, c.x - k, c.y - radius, c.x, c.y - radius);
    fz_append_printf(ctx, b, "%g %g %g %g %g %g c\nh\n", c.x + k, c.y - radius, c.x + radius, c.y - k, c.x + radius, c.y);
}

// Appends `p[0..len)` (UTF-8) as a PDF literal string in WinAnsi (Helvetica's encoding). Characters
// WinAnsi can't represent become '?'. Written byte-by-byte, so there is no line-length limit and no
// allocation that an exception could leak.
static int utf8_to_winansi(const unsigned char *p, size_t len, size_t *advance) {
    unsigned int cp = '?';
    size_t adv = 1;
    unsigned char c = p[0];
    if (c < 0x80) {
        cp = c;
    } else if ((c & 0xE0) == 0xC0 && len >= 2) {
        cp = ((c & 0x1Fu) << 6) | (p[1] & 0x3Fu);
        adv = 2;
    } else if ((c & 0xF0) == 0xE0 && len >= 3) {
        cp = ((c & 0x0Fu) << 12) | ((p[1] & 0x3Fu) << 6) | (p[2] & 0x3Fu);
        adv = 3;
    } else if ((c & 0xF8) == 0xF0 && len >= 4) {
        cp = '?';
        adv = 4;
    }
    *advance = adv;
    switch (cp) {
        case 0x20AC: return 0x80;
        case 0x2026: return 0x85;
        case 0x2018: return 0x91;
        case 0x2019: return 0x92;
        case 0x201C: return 0x93;
        case 0x201D: return 0x94;
        case 0x2022: return 0x95;
        case 0x2013: return 0x96;
        case 0x2014: return 0x97;
        default: break;
    }
    if (cp >= 0x80 && cp < 0xA0) return '?';
    if (cp > 0xFF) return '?';
    return (int)cp;
}

static void append_pdf_text_string(fz_context *ctx, fz_buffer *buf, const char *text, size_t len) {
    fz_append_byte(ctx, buf, '(');
    size_t i = 0;
    while (i < len) {
        size_t adv = 1;
        int c = utf8_to_winansi((const unsigned char *)text + i, len - i, &adv);
        i += adv;
        if (c == '(' || c == ')' || c == '\\') {
            fz_append_byte(ctx, buf, '\\');
            fz_append_byte(ctx, buf, c);
        } else if (c < 32 || c > 126) {
            fz_append_byte(ctx, buf, '\\');
            fz_append_byte(ctx, buf, '0' + ((c >> 6) & 7));
            fz_append_byte(ctx, buf, '0' + ((c >> 3) & 7));
            fz_append_byte(ctx, buf, '0' + (c & 7));
        } else {
            fz_append_byte(ctx, buf, c);
        }
    }
    fz_append_byte(ctx, buf, ')');
}

// Emits one `(line) Tj` per text line, moving down with T* between lines. Expects /TL already set.
static void append_text_lines(fz_context *ctx, fz_buffer *buf, const char *text) {
    const char *p = text;
    int first = 1;
    while (*p) {
        const char *end = strchr(p, '\n');
        size_t line_len = end ? (size_t)(end - p) : strlen(p);
        size_t shown = line_len;
        if (shown > 0 && p[shown - 1] == '\r') shown--;
        if (!first) fz_append_string(ctx, buf, "T*\n");
        append_pdf_text_string(ctx, buf, p, shown);
        fz_append_string(ctx, buf, " Tj\n");
        first = 0;
        if (!end) break;
        p = end + 1;
    }
}

static int count_text_lines(const char *text) {
    int n = 1;
    for (const char *p = text; *p; p++) {
        if (*p == '\n' && p[1] != '\0') n++;
    }
    return n;
}

// Longest line, in bytes — used to size text boxes.
static size_t longest_text_line(const char *text) {
    size_t best = 0, cur = 0;
    for (const char *p = text; ; p++) {
        if (*p == '\n' || *p == '\0') {
            if (cur > best) best = cur;
            cur = 0;
            if (*p == '\0') break;
        } else if (((unsigned char)*p & 0xC0) != 0x80) {
            cur++;
        }
    }
    return best;
}

// A small white label with a thin outline, centred on (cx, cy) in page space.
static void ap_label_pill(fz_context *ctx, fz_buffer *buf, fz_matrix inv, const char *text,
                          float cx, float cy, float r, float g, float b) {
    float text_w = (float)longest_text_line(text) * 6.5f + 10.0f;
    float text_h = 14.0f;
    float px0 = cx - text_w * 0.5f;
    float py0 = cy - text_h * 0.5f;
    fz_append_printf(ctx, buf, "%g %g %g RG\n1 1 1 rg\n0.8 w\n", r, g, b);
    ap_rect(ctx, buf, inv, px0, py0, px0 + text_w, py0 + text_h);
    fz_append_string(ctx, buf, "B\n");
    fz_point t = to_pdf_pt(inv, px0 + 5.0f, py0 + text_h - 3.5f);
    fz_append_printf(ctx, buf, "BT\n%g %g %g rg\n/Helv 9 Tf\n1 0 0 1 %g %g Tm\n", r, g, b, t.x, t.y);
    append_pdf_text_string(ctx, buf, text, strlen(text));
    fz_append_string(ctx, buf, " Tj\nET\n");
}

static pdf_write_options default_save_options(void) {
    pdf_write_options opts = pdf_default_write_options;
    // Without garbage collection, objects orphaned by an edit stay in the file: after a redaction
    // the original, un-redacted content stream would still be sitting in the saved PDF.
    opts.do_garbage = 1;
    return opts;
}

// Brings every page/annotation up to date before a save, then strips the few entries MuPDF writes
// that other viewers mishandle.
static void prepare_document_for_save(fz_context *ctx, pdf_document *pdoc) {
    pdf_page *page = NULL;
    fz_var(page);
    fz_try(ctx) {
        pdf_calculate_form(ctx, pdoc);
        int page_count = pdf_count_pages(ctx, pdoc);
        for (int p = 0; p < page_count; p++) {
            page = pdf_load_page(ctx, pdoc, p);
            pdf_update_page(ctx, page);
            for (pdf_annot *annot = pdf_first_annot(ctx, page); annot; annot = pdf_next_annot(ctx, annot)) {
                ensure_annot_appearance_resources(ctx, pdoc, annot);
                pdf_obj *annot_obj = pdf_annot_obj(ctx, annot);
                if (!annot_obj) continue;
                enum pdf_annot_type atype = pdf_annot_type(ctx, annot);
                // /CL is what makes a FreeText a callout — only a plain text box must not carry one.
                if (atype == PDF_ANNOT_FREE_TEXT && pdf_annot_intent(ctx, annot) != PDF_ANNOT_IT_FREETEXT_CALLOUT) {
                    pdf_dict_del(ctx, annot_obj, PDF_NAME(CL));
                }
                if (atype == PDF_ANNOT_INK) {
                    pdf_dict_del(ctx, annot_obj, PDF_NAME(RD));
                }
            }
            pdf_drop_page(ctx, page);
            page = NULL;
        }
    } fz_always(ctx) {
        if (page) pdf_drop_page(ctx, page);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
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
        fz_matrix inv = pdf_inverse_page_ctm(ctx, ppage);
        float min_x = fminf(x0, x1);
        float max_x = fmaxf(x0, x1);
        float min_y = fminf(y0, y1);
        float max_y = fmaxf(y0, y1);
        fz_rect rect = fz_make_rect(min_x, min_y, max_x, max_y);
        float fs = font_size > 0.0f ? font_size : 13.0f;
        annot = pdf_create_annot(ctx, ppage, PDF_ANNOT_FREE_TEXT);
        pdf_set_annot_rect(ctx, annot, rect);
        pdf_set_annot_border_width(ctx, annot, 0.0f);
        float color[3] = {r, g, b};
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
        }

        // Grow the box to fit the text, then pin the appearance to the final rect.
        int lines = count_text_lines(text);
        float w = rect.x1 - rect.x0;
        float h = rect.y1 - rect.y0;
        float est_w = (float)longest_text_line(text) * fs * 0.75f + 12.0f;
        if (est_w > w) w = est_w;
        float min_h = fs * 1.25f * (float)lines;
        if (h < min_h) h = min_h;
        rect.x1 = rect.x0 + w;
        rect.y1 = rect.y0 + h;
        pdf_set_annot_rect(ctx, annot, rect);

        fz_rect pr = rect;
        pdf_obj *n = begin_custom_ap(ctx, annot, rect, inv, &pr);
        if (n) {
            ensure_helv_font(ctx, pdoc, n);
            float leading = fs * 1.25f;
            float baseline_y;
            if (lines == 1) {
                baseline_y = pr.y0 + (h - fs) * 0.5f;
                if (baseline_y < pr.y0 + 2.0f) baseline_y = pr.y0 + 2.0f;
            } else {
                baseline_y = pr.y1 - fs * 0.95f - 2.0f;
            }
            buf = fz_new_buffer(ctx, 256);
            fz_append_printf(ctx, buf, "BT\n%g %g %g rg\n/Helv %g Tf\n%g TL\n1 0 0 1 %g %g Tm\n",
                             r, g, b, fs, leading, pr.x0 + 1.0f, baseline_y);
            append_text_lines(ctx, buf, text);
            fz_append_string(ctx, buf, "ET\n");
            pdf_update_stream(ctx, pdoc, n, buf, 0);
            fz_drop_buffer(ctx, buf);
            buf = NULL;
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
                                const char *text, float font_size, int line_ending,
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
        fz_matrix inv = pdf_inverse_page_ctm(ctx, ppage);

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
        pdf_set_annot_callout_style(ctx, annot, (enum pdf_line_ending)line_ending);

        float color[3] = {r, g, b};
        float fs = font_size > 0.0f ? font_size : 11.0f;
        pdf_set_annot_default_appearance(ctx, annot, "Helv", fs, 3, color);
        pdf_set_annot_contents(ctx, annot, text);
        pdf_set_annot_border_width(ctx, annot, 1.0f);
        pdf_set_annot_color(ctx, annot, 3, color);
        pdf_update_annot(ctx, annot);

        // Build appearance stream /AP /N so all standard viewers render leader arrow and box
        pdf_obj *n = begin_custom_ap(ctx, annot, union_rect, inv, NULL);
        if (n) {
            ensure_helv_font(ctx, pdoc, n);
            buf = fz_new_buffer(ctx, 512);
            fz_append_printf(ctx, buf, "%g %g %g RG\n", r, g, b);
            fz_append_printf(ctx, buf, "%g %g %g rg\n", r, g, b);
            fz_append_string(ctx, buf, "1 w 1 J 1 j\n");

            // Leader line from target to knee to attach
            ap_move(ctx, buf, inv, target_x, target_y);
            ap_line(ctx, buf, inv, knee_x, knee_y);
            ap_line(ctx, buf, inv, attach_x, attach_y);
            fz_append_string(ctx, buf, "S\n");

            // Line ending at target_pt, the same style /CL's /LE names for viewers that regenerate it
            ap_line_ending(ctx, buf, inv, target_x, target_y, knee_x - target_x, knee_y - target_y, line_ending);

            // Text box rectangle outline and white background
            fz_append_string(ctx, buf, "1 1 1 rg\n");
            ap_rect(ctx, buf, inv, min_bx, min_by, max_bx, max_by);
            fz_append_string(ctx, buf, "B\n");

            // Text inside box, top-aligned (page space is top-down, so the first baseline sits
            // fs*0.9 below the box's top edge)
            fz_point t = to_pdf_pt(inv, min_bx + 3.0f, min_by + fs * 0.9f + 2.0f);
            fz_append_printf(ctx, buf, "BT\n%g %g %g rg\n/Helv %g Tf\n%g TL\n1 0 0 1 %g %g Tm\n",
                             r, g, b, fs, fs * 1.25f, t.x, t.y);
            append_text_lines(ctx, buf, text);
            fz_append_string(ctx, buf, "ET\n");

            pdf_update_stream(ctx, pdoc, n, buf, 0);
            fz_drop_buffer(ctx, buf);
            buf = NULL;
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

// Grows `rect` so it fully contains the label pill that ap_label_pill will draw at (cx, cy).
static fz_rect include_label_pill(fz_rect rect, const char *text, float cx, float cy) {
    float text_w = (float)longest_text_line(text) * 6.5f + 10.0f;
    rect = fz_include_point_in_rect(rect, fz_make_point(cx - text_w * 0.5f - 2.0f, cy - 9.0f));
    rect = fz_include_point_in_rect(rect, fz_make_point(cx + text_w * 0.5f + 2.0f, cy + 9.0f));
    return rect;
}

int mupdf_pdf_add_line_dimension_annot(fz_context *ctx, fz_document *doc, int pageno,
                                       float x0, float y0, float x1, float y1,
                                       float leader_offset, const char *text,
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
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page for line dimension");
        fz_matrix inv = pdf_inverse_page_ctm(ctx, ppage);

        float dx = x1 - x0;
        float dy = y1 - y0;
        float len = sqrtf(dx * dx + dy * dy);
        if (len < 0.001f) len = 0.001f;

        // Unit-normal scaled by the leader offset (page space, top-down)
        float nx = (-dy / len) * leader_offset;
        float ny = (dx / len) * leader_offset;

        float off0_x = x0 + nx;
        float off0_y = y0 + ny;
        float off1_x = x1 + nx;
        float off1_y = y1 + ny;
        float mid_x = (off0_x + off1_x) * 0.5f;
        float mid_y = (off0_y + off1_y) * 0.5f;

        float min_x = fminf(fminf(x0, x1), fminf(off0_x, off1_x));
        float max_x = fmaxf(fmaxf(x0, x1), fmaxf(off0_x, off1_x));
        float min_y = fminf(fminf(y0, y1), fminf(off0_y, off1_y));
        float max_y = fmaxf(fmaxf(y0, y1), fmaxf(off0_y, off1_y));

        fz_rect union_rect = fz_make_rect(min_x - 14.0f, min_y - 14.0f, max_x + 14.0f, max_y + 14.0f);
        union_rect = include_label_pill(union_rect, text, mid_x, mid_y);

        annot = pdf_create_annot(ctx, ppage, PDF_ANNOT_LINE);
        pdf_set_annot_intent(ctx, annot, PDF_ANNOT_IT_LINE_DIMENSION);
        // Note: pdf_set_annot_rect is intentionally omitted for PDF_ANNOT_LINE.
        // MuPDF rejects it ("Line annotations have no Rect property"); the rect
        // is synthesised automatically from /L endpoints by pdf_update_annot.
        //
        // /L holds the *measured* endpoints; with /LL present the dimension line itself is drawn
        // offset from them by the leader length. (The appearance stream below draws the offset line
        // explicitly, so a viewer that regenerates it from /L + /LL must land in the same place —
        // hence the measured points here, not the offset ones, and a negated /LL because page space
        // is top-down while PDF's "positive" side is counter-clockwise in bottom-up space.)
        pdf_set_annot_line(ctx, annot, fz_make_point(x0, y0), fz_make_point(x1, y1));
        pdf_set_annot_line_ending_styles(ctx, annot, PDF_ANNOT_LE_SLASH, PDF_ANNOT_LE_SLASH);
        pdf_set_annot_line_leader(ctx, annot, -leader_offset);
        pdf_set_annot_line_leader_extension(ctx, annot, 4.0f);
        pdf_set_annot_line_leader_offset(ctx, annot, 2.0f);
        pdf_set_annot_line_caption(ctx, annot, 1);
        pdf_set_annot_contents(ctx, annot, text);

        float color[3] = {r, g, b};
        pdf_set_annot_color(ctx, annot, 3, color);
        pdf_set_annot_border_width(ctx, annot, 1.5f);
        pdf_update_annot(ctx, annot);

        // Build appearance stream /AP /N so all viewers render dimension lines and labels
        pdf_obj *n = begin_custom_ap(ctx, annot, union_rect, inv, NULL);
        if (n) {
            ensure_helv_font(ctx, pdoc, n);
            buf = fz_new_buffer(ctx, 512);
            fz_append_printf(ctx, buf, "1.5 w\n0 J\n0 j\n%g %g %g RG\n", r, g, b);

            // Witness leader lines
            if (fabsf(leader_offset) > 1.0f) {
                float ext = leader_offset + (leader_offset > 0 ? 4.0f : -4.0f);
                float ext_x = (nx / leader_offset) * ext;
                float ext_y = (ny / leader_offset) * ext;
                ap_move(ctx, buf, inv, x0, y0);
                ap_line(ctx, buf, inv, x0 + ext_x, y0 + ext_y);
                fz_append_string(ctx, buf, "S\n");
                ap_move(ctx, buf, inv, x1, y1);
                ap_line(ctx, buf, inv, x1 + ext_x, y1 + ext_y);
                fz_append_string(ctx, buf, "S\n");
            }

            // Main dimension line
            ap_move(ctx, buf, inv, off0_x, off0_y);
            ap_line(ctx, buf, inv, off1_x, off1_y);
            fz_append_string(ctx, buf, "S\n");

            // 45° Architectural tick marks at ends
            float tick_len = 5.0f;
            float ux = dx / len;
            float uy = dy / len;
            float tx = (ux - uy) * 0.7071f * tick_len;
            float ty = (ux + uy) * 0.7071f * tick_len;

            fz_append_string(ctx, buf, "2.0 w\n");
            ap_move(ctx, buf, inv, off0_x - tx, off0_y - ty);
            ap_line(ctx, buf, inv, off0_x + tx, off0_y + ty);
            fz_append_string(ctx, buf, "S\n");
            ap_move(ctx, buf, inv, off1_x - tx, off1_y - ty);
            ap_line(ctx, buf, inv, off1_x + tx, off1_y + ty);
            fz_append_string(ctx, buf, "S\n");

            // Dimension text badge centered along dimension line
            ap_label_pill(ctx, buf, inv, text, mid_x, mid_y, r, g, b);

            pdf_update_stream(ctx, pdoc, n, buf, 0);
            fz_drop_buffer(ctx, buf);
            buf = NULL;
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

// Shared by the polyline-dimension and angle annotations: an open vertex chain with a circle at
// each vertex and a label. `is_angle` puts the label beside the middle vertex (the apex) instead
// of midway between the two end vertices.
static int add_polyline_common(fz_context *ctx, fz_document *doc, int pageno,
                               const fz_point *vertices, int n_vertices, const char *text,
                               float r, float g, float b, int is_angle, const char **out_error) {
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
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page for polyline annotation");
        fz_matrix inv = pdf_inverse_page_ctm(ctx, ppage);

        float min_x = vertices[0].x, max_x = vertices[0].x;
        float min_y = vertices[0].y, max_y = vertices[0].y;
        for (int i = 1; i < n_vertices; i++) {
            min_x = fminf(min_x, vertices[i].x);
            max_x = fmaxf(max_x, vertices[i].x);
            min_y = fminf(min_y, vertices[i].y);
            max_y = fmaxf(max_y, vertices[i].y);
        }
        fz_rect union_rect = fz_make_rect(min_x - 12.0f, min_y - 12.0f, max_x + 12.0f, max_y + 12.0f);

        float label_x, label_y;
        if (is_angle && n_vertices >= 3) {
            // Outside the angle, opposite its bisector, so the label doesn't sit on either ray.
            float ax = vertices[0].x - vertices[1].x, ay = vertices[0].y - vertices[1].y;
            float bx = vertices[2].x - vertices[1].x, by = vertices[2].y - vertices[1].y;
            float al = hypotf(ax, ay), bl = hypotf(bx, by);
            float dir_x = 0.0f, dir_y = -1.0f;
            if (al > 0.001f && bl > 0.001f) {
                float sx = ax / al + bx / bl, sy = ay / al + by / bl;
                float sl = hypotf(sx, sy);
                if (sl > 0.001f) {
                    dir_x = -sx / sl;
                    dir_y = -sy / sl;
                }
            }
            label_x = vertices[1].x + dir_x * 22.0f;
            label_y = vertices[1].y + dir_y * 22.0f;
        } else {
            label_x = (vertices[0].x + vertices[n_vertices - 1].x) * 0.5f;
            label_y = (vertices[0].y + vertices[n_vertices - 1].y) * 0.5f;
        }
        union_rect = include_label_pill(union_rect, text, label_x, label_y);

        annot = pdf_create_annot(ctx, ppage, PDF_ANNOT_POLY_LINE);
        if (!is_angle) {
            pdf_set_annot_intent(ctx, annot, PDF_ANNOT_IT_POLYLINE_DIMENSION);
        } else {
            // No standard intent exists for an angle; /Subj lets it be recognised when read back.
            pdf_dict_put_drop(ctx, pdf_annot_obj(ctx, annot), PDF_NAME(Subj), pdf_new_text_string(ctx, "Angle"));
        }
        // Note: pdf_set_annot_rect omitted — MuPDF rejects it for PolyLine;
        // rect is synthesised from /Vertices by pdf_update_annot.
        pdf_set_annot_vertices(ctx, annot, n_vertices, vertices);
        pdf_set_annot_contents(ctx, annot, text);

        float color[3] = {r, g, b};
        pdf_set_annot_color(ctx, annot, 3, color);
        pdf_set_annot_border_width(ctx, annot, 2.0f);
        pdf_update_annot(ctx, annot);

        // Build appearance stream /AP /N
        pdf_obj *n = begin_custom_ap(ctx, annot, union_rect, inv, NULL);
        if (n) {
            ensure_helv_font(ctx, pdoc, n);
            buf = fz_new_buffer(ctx, 512);
            fz_append_printf(ctx, buf, "2.0 w\n1 J\n1 j\n%g %g %g RG\n", r, g, b);
            ap_move(ctx, buf, inv, vertices[0].x, vertices[0].y);
            for (int i = 1; i < n_vertices; i++) {
                ap_line(ctx, buf, inv, vertices[i].x, vertices[i].y);
            }
            fz_append_string(ctx, buf, "S\n");

            // Small circle markers at vertices
            for (int i = 0; i < n_vertices; i++) {
                fz_append_string(ctx, buf, "1 1 1 rg\n");
                ap_circle(ctx, buf, inv, vertices[i].x, vertices[i].y, 2.5f);
                fz_append_string(ctx, buf, "B\n");
            }

            ap_label_pill(ctx, buf, inv, text, label_x, label_y, r, g, b);

            pdf_update_stream(ctx, pdoc, n, buf, 0);
            fz_drop_buffer(ctx, buf);
            buf = NULL;
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

int mupdf_pdf_add_polyline_dimension_annot(fz_context *ctx, fz_document *doc, int pageno,
                                           const fz_point *vertices, int n_vertices,
                                           const char *text,
                                           float r, float g, float b,
                                           const char **out_error) {
    if (!ctx || !doc || !vertices || n_vertices < 2 || !text) return -1;
    return add_polyline_common(ctx, doc, pageno, vertices, n_vertices, text, r, g, b, 0, out_error);
}

int mupdf_pdf_add_angle_annot(fz_context *ctx, fz_document *doc, int pageno,
                              const fz_point *vertices, int n_vertices,
                              const char *text,
                              float r, float g, float b,
                              const char **out_error) {
    if (!ctx || !doc || !vertices || n_vertices != 3 || !text) return -1;
    return add_polyline_common(ctx, doc, pageno, vertices, n_vertices, text, r, g, b, 1, out_error);
}

int mupdf_pdf_add_polygon_dimension_annot(fz_context *ctx, fz_document *doc, int pageno,
                                          const fz_point *vertices, int n_vertices,
                                          const char *text,
                                          float r, float g, float b, float fill_alpha,
                                          const char **out_error) {
    if (!ctx || !doc || !vertices || n_vertices < 3 || !text) return -1;
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
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page for polygon dimension");
        fz_matrix inv = pdf_inverse_page_ctm(ctx, ppage);

        float min_x = vertices[0].x, max_x = vertices[0].x;
        float min_y = vertices[0].y, max_y = vertices[0].y;
        float sum_x = vertices[0].x, sum_y = vertices[0].y;
        for (int i = 1; i < n_vertices; i++) {
            min_x = fminf(min_x, vertices[i].x);
            max_x = fmaxf(max_x, vertices[i].x);
            min_y = fminf(min_y, vertices[i].y);
            max_y = fmaxf(max_y, vertices[i].y);
            sum_x += vertices[i].x;
            sum_y += vertices[i].y;
        }
        float cent_x = sum_x / (float)n_vertices;
        float cent_y = sum_y / (float)n_vertices;
        fz_rect union_rect = fz_make_rect(min_x - 12.0f, min_y - 12.0f, max_x + 12.0f, max_y + 12.0f);
        union_rect = include_label_pill(union_rect, text, cent_x, cent_y);

        annot = pdf_create_annot(ctx, ppage, PDF_ANNOT_POLYGON);
        pdf_set_annot_intent(ctx, annot, PDF_ANNOT_IT_POLYGON_DIMENSION);
        // Note: pdf_set_annot_rect omitted — MuPDF rejects it for Polygon;
        // rect is synthesised from /Vertices by pdf_update_annot.
        pdf_set_annot_vertices(ctx, annot, n_vertices, vertices);
        pdf_set_annot_contents(ctx, annot, text);

        float color[3] = {r, g, b};
        pdf_set_annot_color(ctx, annot, 3, color);
        pdf_set_annot_interior_color(ctx, annot, 3, color);
        float alpha = fill_alpha > 0.05f ? fill_alpha : 0.22f;
        pdf_set_annot_opacity(ctx, annot, alpha);
        pdf_set_annot_border_width(ctx, annot, 1.8f);
        pdf_update_annot(ctx, annot);

        // Build appearance stream /AP /N
        pdf_obj *n = begin_custom_ap(ctx, annot, union_rect, inv, NULL);
        if (n) {
            ensure_helv_font(ctx, pdoc, n);
            ensure_alpha_gs(ctx, pdoc, n, alpha);
            buf = fz_new_buffer(ctx, 512);
            // The translucent fill is scoped to q…Q so the label pill below stays opaque.
            fz_append_string(ctx, buf, "q\n/GSa gs\n");
            fz_append_printf(ctx, buf, "1.8 w\n1 J\n1 j\n%g %g %g RG\n", r, g, b);
            fz_append_printf(ctx, buf, "%g %g %g rg\n", r, g, b);
            ap_move(ctx, buf, inv, vertices[0].x, vertices[0].y);
            for (int i = 1; i < n_vertices; i++) {
                ap_line(ctx, buf, inv, vertices[i].x, vertices[i].y);
            }
            fz_append_string(ctx, buf, "b\nQ\n");

            ap_label_pill(ctx, buf, inv, text, cent_x, cent_y, r, g, b);

            pdf_update_stream(ctx, pdoc, n, buf, 0);
            fz_drop_buffer(ctx, buf);
            buf = NULL;
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

#define VP_SCALE_NAME "Drawing Scale"

// Records the drawing scale as an ISO 32000 /VP viewport on the page. Replaces this app's own
// previous "Drawing Scale" viewport rather than stacking another one on every call; viewports
// authored by other software are left alone.
int mupdf_pdf_set_page_scale(fz_context *ctx, fz_document *doc, int pageno,
                             const char *ratio_str, const char *unit_str,
                             float pts_per_unit, const char **out_error) {
    if (!ctx || !doc || !ratio_str) return -1;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");

        pdf_obj *page_obj = pdf_lookup_page_obj(ctx, pdoc, pageno);
        if (!page_obj) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to lookup page object for scale configuration");

        pdf_obj *vp_arr = pdf_dict_gets(ctx, page_obj, "VP");
        if (!vp_arr || !pdf_is_array(ctx, vp_arr)) {
            vp_arr = pdf_new_array(ctx, pdoc, 1);
            pdf_dict_puts_drop(ctx, page_obj, "VP", vp_arr);
            vp_arr = pdf_dict_gets(ctx, page_obj, "VP");
        }
        for (int i = pdf_array_len(ctx, vp_arr) - 1; i >= 0; i--) {
            pdf_obj *existing = pdf_array_get(ctx, vp_arr, i);
            pdf_obj *name = existing ? pdf_dict_gets(ctx, existing, "Name") : NULL;
            if (name && pdf_is_string(ctx, name) && strcmp(pdf_to_str_buf(ctx, name), VP_SCALE_NAME) == 0) {
                pdf_array_delete(ctx, vp_arr, i);
            }
        }

        pdf_obj *vp_dict = pdf_new_dict(ctx, pdoc, 4);
        pdf_dict_puts_drop(ctx, vp_dict, "Type", pdf_new_name(ctx, "Viewport"));

        pdf_obj *media_obj = pdf_dict_get_inheritable(ctx, page_obj, PDF_NAME(MediaBox));
        fz_rect mediabox = pdf_to_rect(ctx, media_obj);
        pdf_dict_put_rect(ctx, vp_dict, PDF_NAME(BBox), mediabox);
        pdf_dict_puts_drop(ctx, vp_dict, "Name", pdf_new_string(ctx, VP_SCALE_NAME, strlen(VP_SCALE_NAME)));

        pdf_obj *meas_dict = pdf_new_dict(ctx, pdoc, 6);
        pdf_dict_puts_drop(ctx, meas_dict, "Type", pdf_new_name(ctx, "Measure"));
        pdf_dict_puts_drop(ctx, meas_dict, "Subtype", pdf_new_name(ctx, "RL"));
        pdf_dict_puts_drop(ctx, meas_dict, "R", pdf_new_string(ctx, ratio_str, strlen(ratio_str)));

        float c_factor = pts_per_unit > 0.00001f ? (1.0f / pts_per_unit) : 1.0f;
        pdf_obj *num_fmt = pdf_new_dict(ctx, pdoc, 4);
        pdf_dict_puts_drop(ctx, num_fmt, "Type", pdf_new_name(ctx, "NumberFormat"));
        const char *u = unit_str ? unit_str : "ft";
        pdf_dict_puts_drop(ctx, num_fmt, "U", pdf_new_string(ctx, u, strlen(u)));
        pdf_dict_puts_drop(ctx, num_fmt, "C", pdf_new_real(ctx, c_factor));

        pdf_obj *fmt_arr = pdf_new_array(ctx, pdoc, 1);
        pdf_array_push(ctx, fmt_arr, num_fmt);
        pdf_dict_puts(ctx, meas_dict, "D", fmt_arr);
        pdf_dict_puts(ctx, meas_dict, "X", fmt_arr);
        pdf_dict_puts_drop(ctx, meas_dict, "Y", fmt_arr);
        pdf_drop_obj(ctx, num_fmt);

        pdf_dict_puts_drop(ctx, vp_dict, "Measure", meas_dict);
        pdf_array_push_drop(ctx, vp_arr, vp_dict);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

// Reads back what mupdf_pdf_set_page_scale wrote. *out_found is 1 if the page carries one of this
// app's "Drawing Scale" viewports (in which case the other outputs are filled in), else 0.
int mupdf_pdf_get_page_scale(fz_context *ctx, fz_document *doc, int pageno,
                             char *out_ratio, size_t ratio_cap,
                             char *out_unit, size_t unit_cap,
                             float *out_pts_per_unit, int *out_found,
                             const char **out_error) {
    if (!ctx || !doc || !out_found) return -1;
    *out_found = 0;
    if (out_ratio && ratio_cap) out_ratio[0] = '\0';
    if (out_unit && unit_cap) out_unit[0] = '\0';
    if (out_pts_per_unit) *out_pts_per_unit = 0.0f;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (pdoc && pageno >= 0 && pageno < pdf_count_pages(ctx, pdoc)) {
            pdf_obj *page_obj = pdf_lookup_page_obj(ctx, pdoc, pageno);
            pdf_obj *vp_arr = page_obj ? pdf_dict_gets(ctx, page_obj, "VP") : NULL;
            if (vp_arr && pdf_is_array(ctx, vp_arr)) {
                for (int i = pdf_array_len(ctx, vp_arr) - 1; i >= 0; i--) {
                    pdf_obj *vp = pdf_array_get(ctx, vp_arr, i);
                    pdf_obj *name = vp ? pdf_dict_gets(ctx, vp, "Name") : NULL;
                    if (!name || !pdf_is_string(ctx, name) || strcmp(pdf_to_str_buf(ctx, name), VP_SCALE_NAME) != 0) continue;
                    pdf_obj *meas = pdf_dict_gets(ctx, vp, "Measure");
                    pdf_obj *d = meas ? pdf_dict_gets(ctx, meas, "D") : NULL;
                    pdf_obj *fmt = (d && pdf_is_array(ctx, d)) ? pdf_array_get(ctx, d, 0) : NULL;
                    pdf_obj *c = fmt ? pdf_dict_gets(ctx, fmt, "C") : NULL;
                    float c_val = c ? pdf_to_real(ctx, c) : 0.0f;
                    if (c_val <= 0.0f) continue;
                    pdf_obj *u = pdf_dict_gets(ctx, fmt, "U");
                    pdf_obj *ratio = pdf_dict_gets(ctx, meas, "R");
                    if (out_unit && unit_cap && u && pdf_is_string(ctx, u)) {
                        strncpy(out_unit, pdf_to_str_buf(ctx, u), unit_cap - 1);
                        out_unit[unit_cap - 1] = '\0';
                    }
                    if (out_ratio && ratio_cap && ratio && pdf_is_string(ctx, ratio)) {
                        strncpy(out_ratio, pdf_to_str_buf(ctx, ratio), ratio_cap - 1);
                        out_ratio[ratio_cap - 1] = '\0';
                    }
                    if (out_pts_per_unit) *out_pts_per_unit = 1.0f / c_val;
                    *out_found = 1;
                    break;
                }
            }
        }
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

static int rect_touches_any(fz_rect area, const fz_rect *rects, int n_rects) {
    for (int i = 0; i < n_rects; i++) {
        fz_rect r = fz_make_rect(fminf(rects[i].x0, rects[i].x1), fminf(rects[i].y0, rects[i].y1),
                                 fmaxf(rects[i].x0, rects[i].x1), fmaxf(rects[i].y0, rects[i].y1));
        if (!fz_is_empty_rect(fz_intersect_rect(area, r))) return 1;
    }
    return 0;
}

// A reply (/IRT) is part of the annotation it answers, and another viewer can't show one whose
// parent has gone, so deleting an annotation deletes its thread too.
static void delete_annot_and_replies(fz_context *ctx, pdf_page *page, pdf_annot *annot) {
    int num = pdf_to_num(ctx, pdf_annot_obj(ctx, annot));
    pdf_delete_annot(ctx, page, annot);
    int found;
    do {
        found = 0;
        for (pdf_annot *a = pdf_first_annot(ctx, page); a; a = pdf_next_annot(ctx, a)) {
            if (pdf_to_num(ctx, pdf_dict_get(ctx, pdf_annot_obj(ctx, a), PDF_NAME(IRT))) == num) {
                delete_annot_and_replies(ctx, page, a);
                found = 1;
                break;
            }
        }
    } while (found);
}

// pdf_redact_page only removes FreeText annotations and links under a redaction. Highlights and
// notes often repeat the covered text in /Contents, and a form field keeps its value in /V, so
// any annotation or widget touching a redacted area goes too (popups are removed with their parent).
static void delete_annots_touching_rects(fz_context *ctx, pdf_page *page, const fz_rect *rects, int n_rects) {
    int deleted;
    do {
        deleted = 0;
        for (pdf_annot *annot = pdf_first_annot(ctx, page); annot; annot = pdf_next_annot(ctx, annot)) {
            enum pdf_annot_type type = pdf_annot_type(ctx, annot);
            if (type == PDF_ANNOT_POPUP || type == PDF_ANNOT_LINK || type == PDF_ANNOT_REDACT) continue;
            if (rect_touches_any(pdf_bound_annot(ctx, annot), rects, n_rects)) {
                delete_annot_and_replies(ctx, page, annot);
                deleted = 1;
                break;
            }
        }
        if (deleted) continue;
        for (pdf_annot *widget = pdf_first_widget(ctx, page); widget; widget = pdf_next_widget(ctx, widget)) {
            if (rect_touches_any(pdf_bound_annot(ctx, widget), rects, n_rects)) {
                pdf_delete_annot(ctx, page, widget);
                deleted = 1;
                break;
            }
        }
    } while (deleted);
}

// pdf_redact_page only touches the page. The text it removes can also be anywhere in the document's
// own data, and there's no way to match it there: a region can cover a scan, so the text isn't
// known, and the metadata can spell a name differently. So all of it goes. Bookmarks are the
// exception, since a reader navigates by them: mupdf_pdf_rename_outline_items edits their titles.
static void strip_object_data(fz_context *ctx, pdf_obj *obj) {
    if (!pdf_is_dict(ctx, obj)) return;
    // Any object can carry XMP or an application's private copy of the content (/PieceInfo), and
    // /Thumb is a picture of the unredacted page.
    pdf_dict_del(ctx, obj, PDF_NAME(Metadata));
    pdf_dict_del(ctx, obj, PDF_NAME(PieceInfo));
    pdf_dict_del(ctx, obj, PDF_NAME(Thumb));
    pdf_dict_del(ctx, obj, PDF_NAME(AF));
    pdf_dict_del(ctx, obj, PDF_NAME(EF));
    // A structure element (/Type is optional) keeps its tags for reading order, but not their text.
    if (pdf_is_name(ctx, pdf_dict_get(ctx, obj, PDF_NAME(S))) && pdf_dict_get(ctx, obj, PDF_NAME(P))) {
        pdf_dict_del(ctx, obj, PDF_NAME(Alt));
        pdf_dict_del(ctx, obj, PDF_NAME(ActualText));
        pdf_dict_del(ctx, obj, PDF_NAME(E));
        pdf_dict_del(ctx, obj, PDF_NAME(T));
    }
}

// `budget` is the number of items left to visit, which ends a malformed outline that loops.
static void rename_outline_items(fz_context *ctx, pdf_obj *item, const char *title, const char *new_title, int *budget) {
    while (pdf_is_dict(ctx, item) && (*budget)-- > 0) {
        if (strcmp(pdf_to_text_string(ctx, pdf_dict_get(ctx, item, PDF_NAME(Title))), title) == 0) {
            pdf_dict_put_text_string(ctx, item, PDF_NAME(Title), new_title);
        }
        rename_outline_items(ctx, pdf_dict_get(ctx, item, PDF_NAME(First)), title, new_title, budget);
        item = pdf_dict_get(ctx, item, PDF_NAME(Next));
    }
}

int mupdf_pdf_rename_outline_items(fz_context *ctx, fz_document *doc, const char *title, const char *new_title, const char **out_error) {
    if (!ctx || !doc || !title || !new_title) return -1;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        pdf_obj *outlines = pdf_dict_getl(ctx, pdf_trailer(ctx, pdoc), PDF_NAME(Root), PDF_NAME(Outlines), NULL);
        int budget = pdf_xref_len(ctx, pdoc);
        rename_outline_items(ctx, pdf_dict_get(ctx, outlines, PDF_NAME(First)), title, new_title, &budget);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_strip_document_data(fz_context *ctx, fz_document *doc, const char **out_error) {
    if (!ctx || !doc) return -1;
    pdf_page *page = NULL;
    fz_var(page);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");

        pdf_obj *trailer = pdf_trailer(ctx, pdoc);
        pdf_dict_del(ctx, trailer, PDF_NAME(Info));
        pdf_obj *root = pdf_dict_get(ctx, trailer, PDF_NAME(Root));
        pdf_dict_del(ctx, root, PDF_NAME(Collection));
        pdf_obj *names = pdf_dict_get(ctx, root, PDF_NAME(Names));
        if (pdf_is_dict(ctx, names)) pdf_dict_del(ctx, names, PDF_NAME(EmbeddedFiles));
        // Hybrid forms keep every field's value in the XFA too, where deleting a widget can't reach.
        pdf_obj *acroform = pdf_dict_get(ctx, root, PDF_NAME(AcroForm));
        if (pdf_is_dict(ctx, acroform)) pdf_dict_del(ctx, acroform, PDF_NAME(XFA));

        int page_count = pdf_count_pages(ctx, pdoc);
        for (int p = 0; p < page_count; p++) {
            page = pdf_load_page(ctx, pdoc, p);
            pdf_annot *annot = pdf_first_annot(ctx, page);
            while (annot) {
                pdf_annot *next = pdf_next_annot(ctx, annot);
                if (pdf_annot_type(ctx, annot) == PDF_ANNOT_FILE_ATTACHMENT) {
                    pdf_delete_annot(ctx, page, annot);
                    // Deleting can also take the annotation's popup, which may have been `next`.
                    next = pdf_first_annot(ctx, page);
                }
                annot = next;
            }
            pdf_drop_page(ctx, page);
            page = NULL;
        }

        int xref_len = pdf_xref_len(ctx, pdoc);
        for (int num = 1; num < xref_len; num++) {
            pdf_obj *obj = NULL;
            fz_var(obj);
            fz_try(ctx) {
                obj = pdf_load_object(ctx, pdoc, num);
                strip_object_data(ctx, obj);
            } fz_always(ctx) {
                pdf_drop_obj(ctx, obj);
            } fz_catch(ctx) {
                // A damaged object has to stop nothing: the writer can't carry its content either.
                fz_report_error(ctx);
            }
        }
    } fz_always(ctx) {
        if (page) pdf_drop_page(ctx, page);
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
        // black_boxes: 1 = Blackout Region, 2 = Whiteout Region, 0 = Text Only
        opts.black_boxes = (black_boxes == 1) ? 1 : 0;
        if (black_boxes == 1 || black_boxes == 2) {
            opts.image_method = PDF_REDACT_IMAGE_PIXELS;
            opts.line_art = PDF_REDACT_LINE_ART_REMOVE_IF_TOUCHED;
        } else {
            opts.image_method = PDF_REDACT_IMAGE_NONE;
            opts.line_art = PDF_REDACT_LINE_ART_NONE;
        }
        opts.text = PDF_REDACT_TEXT_REMOVE;

        pdf_redact_page(ctx, pdoc, ppage, &opts);
        if (rects && n_rects > 0) {
            delete_annots_touching_rects(ctx, ppage, rects, n_rects);
        }

        if (black_boxes == 2 && rects && n_rects > 0) {
            for (int i = 0; i < n_rects; i++) {
                fz_rect r = rects[i];
                float min_x = fminf(r.x0, r.x1);
                float max_x = fmaxf(r.x0, r.x1);
                float min_y = fminf(r.y0, r.y1);
                float max_y = fmaxf(r.y0, r.y1);
                fz_rect norm_rect = fz_make_rect(min_x, min_y, max_x, max_y);
                pdf_annot *sq = pdf_create_annot(ctx, ppage, PDF_ANNOT_SQUARE);
                pdf_set_annot_rect(ctx, sq, norm_rect);
                float white[3] = {1.0f, 1.0f, 1.0f};
                pdf_set_annot_color(ctx, sq, 3, white);
                pdf_set_annot_interior_color(ctx, sq, 3, white);
                pdf_set_annot_border_width(ctx, sq, 0.0f);
                pdf_update_annot(ctx, sq);
                pdf_drop_annot(ctx, sq);
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

static float distance_to_segment(float x, float y, fz_point a, fz_point b) {
    float dx = b.x - a.x, dy = b.y - a.y;
    float l2 = dx * dx + dy * dy;
    float t = l2 > 0.0001f ? fmaxf(0.0f, fminf(1.0f, ((x - a.x) * dx + (y - a.y) * dy) / l2)) : 0.0f;
    float px = x - (a.x + t * dx), py = y - (a.y + t * dy);
    return sqrtf(px * px + py * py);
}

static int is_cloudy(fz_context *ctx, pdf_annot *annot) {
    return pdf_name_eq(ctx, pdf_dict_getp(ctx, pdf_annot_obj(ctx, annot), "BE/S"), PDF_NAME(C));
}

/* The topmost annotation the Eraser or a click at (x, y) means, in page space: along a line or
 * outline, over a highlighted quad, or within a note, stamp or text box. Not a reply, popup or
 * link. Annotations later in /Annots are drawn on top, so the last one hit wins. */
/* The layer something with an /OC entry is on: its optional content group's object number, or 0
 * for none, or for a membership dictionary (/OCMD) naming several. */
static int vp_oc_layer(fz_context *ctx, pdf_obj *obj) {
    pdf_obj *oc = pdf_dict_get(ctx, obj, PDF_NAME(OC));
    if (pdf_is_indirect(ctx, oc) && pdf_name_eq(ctx, pdf_dict_get(ctx, oc, PDF_NAME(Type)), PDF_NAME(OCG)))
        return pdf_to_num(ctx, oc);
    return 0;
}

/* Whether its /OC hides it while the document's layers are shown as they are now. */
static int vp_oc_hidden(fz_context *ctx, pdf_document *pdoc, pdf_obj *obj) {
    pdf_obj *oc = pdf_dict_get(ctx, obj, PDF_NAME(OC));
    return oc && pdf_is_ocg_hidden(ctx, pdoc, NULL, "View", oc);
}

static pdf_annot *annot_near_point(fz_context *ctx, pdf_page *ppage, float x, float y) {
    pdf_annot *found = NULL;
    for (pdf_annot *annot = pdf_first_annot(ctx, ppage); annot; annot = pdf_next_annot(ctx, annot)) {
        enum pdf_annot_type atype = pdf_annot_type(ctx, annot);
        int hit = 0;
        if (atype == PDF_ANNOT_POPUP || atype == PDF_ANNOT_LINK) continue;
        // One on a hidden layer isn't there to click or erase.
        if (vp_oc_hidden(ctx, ppage->doc, pdf_annot_obj(ctx, annot))) continue;
        // Replies have no appearance of their own; they go with their parent.
        if (pdf_dict_get(ctx, pdf_annot_obj(ctx, annot), PDF_NAME(IRT))) continue;
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
        } else if (atype == PDF_ANNOT_LINE) {
            fz_point a, b;
            pdf_annot_line(ctx, annot, &a, &b);
            hit = distance_to_segment(x, y, a, b) <= 6.0f + pdf_annot_border_width(ctx, annot) / 2;
        } else if (atype == PDF_ANNOT_POLY_LINE || atype == PDF_ANNOT_POLYGON) {
            // Along the outline: a polygon, cloudy or not, rings other content.
            int n = pdf_annot_vertex_count(ctx, annot);
            int closed = atype == PDF_ANNOT_POLYGON;
            float tol = 6.0f + pdf_annot_border_width(ctx, annot) / 2 + (is_cloudy(ctx, annot) ? 6.0f : 0.0f);
            for (int i = 0; i + 1 < n + closed && !hit; i++) {
                hit = distance_to_segment(x, y, pdf_annot_vertex(ctx, annot, i), pdf_annot_vertex(ctx, annot, (i + 1) % n)) <= tol;
            }
            // Dimension polygons and polylines have their measurement label in the middle.
            if (!hit && pdf_annot_intent(ctx, annot) != PDF_ANNOT_IT_DEFAULT) {
                fz_rect r = pdf_bound_annot(ctx, annot);
                hit = x >= r.x0 && x <= r.x1 && y >= r.y0 && y <= r.y1;
            }
        } else if (atype == PDF_ANNOT_SQUARE || atype == PDF_ANNOT_CIRCLE) {
            // Only the outline, which rings other content.
            fz_rect r = pdf_bound_annot(ctx, annot);
            float tol = 8.0f + (is_cloudy(ctx, annot) ? 6.0f : 0.0f);
            int near = x >= r.x0 - tol && x <= r.x1 + tol && y >= r.y0 - tol && y <= r.y1 + tol;
            int inside = x > r.x0 + tol && x < r.x1 - tol && y > r.y0 + tol && y < r.y1 - tol;
            if (atype == PDF_ANNOT_CIRCLE && near && r.x1 > r.x0 && r.y1 > r.y0) {
                float nx = (x - (r.x0 + r.x1) / 2) / ((r.x1 - r.x0) / 2);
                float ny = (y - (r.y0 + r.y1) / 2) / ((r.y1 - r.y0) / 2);
                hit = fabsf(sqrtf(nx * nx + ny * ny) - 1) * fminf(r.x1 - r.x0, r.y1 - r.y0) / 2 <= tol;
            } else {
                hit = near && !inside;
            }
        } else if (atype == PDF_ANNOT_TEXT || atype == PDF_ANNOT_FILE_ATTACHMENT || atype == PDF_ANNOT_SOUND || atype == PDF_ANNOT_CARET || atype == PDF_ANNOT_SQUIGGLY) {
            fz_rect r = pdf_bound_annot(ctx, annot);
            float tol = 6.0f;
            hit = x >= r.x0 - tol && x <= r.x1 + tol && y >= r.y0 - tol && y <= r.y1 + tol;
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
        if (hit) found = annot;
    }
    return found;
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
        pdf_annot *annot = annot_near_point(ctx, ppage, x, y);
        if (annot) {
            delete_annot_and_replies(ctx, ppage, annot);
            deleted = 1;
        }
    } fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return deleted;
}

int mupdf_pdf_annot_near_point(fz_context *ctx, fz_document *doc, int pageno, float x, float y, int *out_objnum, const char **out_error) {
    if (!ctx || !doc || !out_objnum) return -1;
    *out_objnum = 0;
    pdf_page *ppage = NULL;
    fz_var(ppage);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *annot = annot_near_point(ctx, ppage, x, y);
        if (annot) *out_objnum = pdf_to_num(ctx, pdf_annot_obj(ctx, annot));
    } fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_pdf_delete_highlight_near_point(fz_context *ctx, fz_document *doc, int pageno, float x, float y, const char **out_error) {
    return mupdf_pdf_delete_annot_near_point(ctx, doc, pageno, x, y, out_error);
}


// Stamps an image into a new PDF_ANNOT_STAMP annotation at the given rect — a purely visual
// signature overlay (see PDFFormControls.swift). Does not touch the AcroForm field's /V and isn't
// a cryptographic signature (no OpenSSL in this build).
/* Object number of the last annotation on a page — pdf_create_annot appends, so called right
 * after one of the add functions above this identifies the annotation it just created. */
int mupdf_pdf_last_annot_objnum(fz_context *ctx, fz_document *doc, int pageno, int *out_objnum, const char **out_error) {
    if (!ctx || !doc || !out_objnum) return -1;
    *out_objnum = 0;
    pdf_page *ppage = NULL;
    fz_var(ppage);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *last = NULL;
        for (pdf_annot *a = pdf_first_annot(ctx, ppage); a; a = pdf_next_annot(ctx, a)) {
            last = a;
        }
        if (last) *out_objnum = pdf_to_num(ctx, pdf_annot_obj(ctx, last));
    }
    fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    }
    fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

/* Deletes exactly the annotation whose dictionary is object `objnum` on a page. Returns 1 if it
 * was found and deleted, 0 if no annotation on the page has that object number, -1 on error. */
int mupdf_pdf_delete_annot_by_objnum(fz_context *ctx, fz_document *doc, int pageno, int objnum, const char **out_error) {
    if (!ctx || !doc || objnum <= 0) return -1;
    pdf_page *ppage = NULL;
    int deleted = 0;
    fz_var(ppage);
    fz_var(deleted);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        for (pdf_annot *a = pdf_first_annot(ctx, ppage); a; a = pdf_next_annot(ctx, a)) {
            if (pdf_to_num(ctx, pdf_annot_obj(ctx, a)) == objnum) {
                delete_annot_and_replies(ctx, ppage, a);
                deleted = 1;
                break;
            }
        }
    }
    fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    }
    fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return deleted;
}

static pdf_annot *find_annot_by_objnum(fz_context *ctx, pdf_page *page, int objnum) {
    for (pdf_annot *a = pdf_first_annot(ctx, page); a; a = pdf_next_annot(ctx, a)) {
        if (pdf_to_num(ctx, pdf_annot_obj(ctx, a)) == objnum) return a;
    }
    return NULL;
}

/* ---- Undo for annotations, and editing ones that came with the file ----
 * A deleted annotation is copied first into a holding document that's never saved, so Undo can
 * put it back with its replies, author and dates after a save has dropped the originals. */

fz_document *mupdf_pdf_new_holding_document(fz_context *ctx) {
    if (!ctx) return NULL;
    pdf_document *holding = NULL;
    fz_try(ctx) {
        holding = pdf_create_document(ctx);
        pdf_dict_puts_drop(ctx, pdf_trailer(ctx, holding), "VectorPDFStash", pdf_new_array(ctx, holding, 8));
    } fz_catch(ctx) {
        return NULL;
    }
    return (fz_document *)holding;
}

/* Where a stashed copy keeps the object number of the layer it was on (see stash_objects). */
#define VP_STASHED_LAYER "VectorPDFLayer"

/* Puts a copy back in `pdoc` on the layer it was stashed from. */
static void unstash_layer(fz_context *ctx, pdf_document *pdoc, pdf_obj *obj) {
    pdf_obj *num = pdf_dict_gets(ctx, obj, VP_STASHED_LAYER);
    if (!num) return;
    if (pdf_is_int(ctx, num) && pdf_to_int(ctx, num) > 0)
        pdf_dict_put_drop(ctx, obj, PDF_NAME(OC), pdf_new_indirect(ctx, pdoc, pdf_to_int(ctx, num), 0));
    pdf_dict_dels(ctx, obj, VP_STASHED_LAYER);
}

/* The annotation `root` and, transitively, its replies and the popups of all of them. */
static void collect_thread(fz_context *ctx, pdf_page *page, pdf_obj *root, pdf_obj *into) {
    pdf_array_push(ctx, into, root);
    pdf_obj *popup = pdf_dict_get(ctx, root, PDF_NAME(Popup));
    if (pdf_is_indirect(ctx, popup)) pdf_array_push(ctx, into, popup);
    int num = pdf_to_num(ctx, root);
    for (pdf_annot *a = pdf_first_annot(ctx, page); a; a = pdf_next_annot(ctx, a)) {
        pdf_obj *obj = pdf_annot_obj(ctx, a);
        if (pdf_to_num(ctx, pdf_dict_get(ctx, obj, PDF_NAME(IRT))) == num) collect_thread(ctx, page, obj, into);
    }
}

/* Copies `objects` into the holding document's stash and returns where. /P, which would bring
 * the whole page along, is left out of the copies; `restore_page` puts it back on the originals. */
static int stash_objects(fz_context *ctx, pdf_document *holding, pdf_obj *objects, pdf_obj *restore_page) {
    int n = pdf_array_len(ctx, objects);
    for (int i = 0; i < n; i++) pdf_dict_del(ctx, pdf_array_get(ctx, objects, i), PDF_NAME(P));
    /* Copying /OC would copy the layer too, and the annotation would come back on a copy of it
     * that isn't one of the document's layers. The copies keep its object number instead. */
    pdf_obj **layers = fz_calloc(ctx, n > 0 ? n : 1, sizeof *layers);
    for (int i = 0; i < n; i++) {
        pdf_obj *obj = pdf_array_get(ctx, objects, i);
        pdf_obj *oc = pdf_dict_get(ctx, obj, PDF_NAME(OC));
        if (pdf_is_indirect(ctx, oc)) {
            layers[i] = pdf_keep_obj(ctx, oc);
            pdf_dict_puts_drop(ctx, obj, VP_STASHED_LAYER, pdf_new_int(ctx, pdf_to_num(ctx, oc)));
            pdf_dict_del(ctx, obj, PDF_NAME(OC));
        }
    }
    pdf_graft_map *map = pdf_new_graft_map(ctx, holding);
    pdf_obj *copies = NULL;
    fz_var(copies);
    fz_try(ctx) {
        copies = pdf_new_array(ctx, holding, n);
        for (int i = 0; i < n; i++) {
            pdf_obj *copy = pdf_graft_mapped_object(ctx, map, pdf_array_get(ctx, objects, i));
            pdf_array_push_drop(ctx, copies, copy);
        }
        pdf_array_push(ctx, pdf_dict_gets(ctx, pdf_trailer(ctx, holding), "VectorPDFStash"), copies);
    } fz_always(ctx) {
        pdf_drop_graft_map(ctx, map);
        pdf_drop_obj(ctx, copies);
        if (restore_page) {
            for (int i = 0; i < n; i++) pdf_dict_put(ctx, pdf_array_get(ctx, objects, i), PDF_NAME(P), restore_page);
        }
        for (int i = 0; i < n; i++) {
            if (!layers[i]) continue;
            pdf_obj *obj = pdf_array_get(ctx, objects, i);
            pdf_dict_dels(ctx, obj, VP_STASHED_LAYER);
            pdf_dict_put_drop(ctx, obj, PDF_NAME(OC), layers[i]);
        }
        fz_free(ctx, layers);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
    return pdf_array_len(ctx, pdf_dict_gets(ctx, pdf_trailer(ctx, holding), "VectorPDFStash")) - 1;
}

/* Copies the annotation `objnum`, its replies and popups into `holding`, then deletes them. */
int mupdf_pdf_stash_and_delete_annot(fz_context *ctx, fz_document *doc, int pageno, int objnum, fz_document *holding, int *out_index, const char **out_error) {
    if (!ctx || !doc || !holding || !out_index) return -1;
    pdf_page *ppage = NULL;
    pdf_obj *objects = NULL;
    int found = 0;
    fz_var(ppage);
    fz_var(objects);
    fz_var(found);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *annot = find_annot_by_objnum(ctx, ppage, objnum);
        if (annot) {
            objects = pdf_new_array(ctx, pdoc, 4);
            collect_thread(ctx, ppage, pdf_annot_obj(ctx, annot), objects);
            *out_index = stash_objects(ctx, (pdf_document *)holding, objects, ppage->obj);
            delete_annot_and_replies(ctx, ppage, annot);
            found = 1;
        }
    } fz_always(ctx) {
        pdf_drop_obj(ctx, objects);
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return found;
}

/* Puts a stashed annotation and its replies back on the page, as new objects; returns the new
 * object number of the annotation itself. */
int mupdf_pdf_unstash_annot(fz_context *ctx, fz_document *doc, int pageno, fz_document *holding, int index, int *out_objnum, const char **out_error) {
    if (!ctx || !doc || !holding || !out_objnum) return -1;
    pdf_page *ppage = NULL;
    pdf_graft_map *map = NULL;
    fz_var(ppage);
    fz_var(map);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        pdf_obj *copies = pdf_array_get(ctx, pdf_dict_gets(ctx, pdf_trailer(ctx, (pdf_document *)holding), "VectorPDFStash"), index);
        if (!pdf_is_array(ctx, copies)) fz_throw(ctx, FZ_ERROR_GENERIC, "Nothing stashed there");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_obj *annots = pdf_dict_get(ctx, ppage->obj, PDF_NAME(Annots));
        if (!pdf_is_array(ctx, annots)) annots = pdf_dict_put_array(ctx, ppage->obj, PDF_NAME(Annots), 4);
        map = pdf_new_graft_map(ctx, pdoc);
        int n = pdf_array_len(ctx, copies);
        for (int i = 0; i < n; i++) {
            pdf_obj *obj = pdf_graft_mapped_object(ctx, map, pdf_array_get(ctx, copies, i));
            pdf_dict_put(ctx, obj, PDF_NAME(P), ppage->obj);
            unstash_layer(ctx, pdoc, obj);
            pdf_array_push(ctx, annots, obj);
            if (i == 0) *out_objnum = pdf_to_num(ctx, obj);
            pdf_drop_obj(ctx, obj);
        }
    } fz_always(ctx) {
        pdf_drop_graft_map(ctx, map);
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

/* Copies the annotation `objnum` alone into `holding`, before an edit, so Undo can restore it. */
int mupdf_pdf_snapshot_annot(fz_context *ctx, fz_document *doc, int pageno, int objnum, fz_document *holding, int *out_index, const char **out_error) {
    if (!ctx || !doc || !holding || !out_index) return -1;
    pdf_page *ppage = NULL;
    pdf_obj *objects = NULL;
    int found = 0;
    fz_var(ppage);
    fz_var(objects);
    fz_var(found);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *annot = find_annot_by_objnum(ctx, ppage, objnum);
        if (annot) {
            objects = pdf_new_array(ctx, pdoc, 1);
            pdf_array_push(ctx, objects, pdf_annot_obj(ctx, annot));
            *out_index = stash_objects(ctx, (pdf_document *)holding, objects, ppage->obj);
            found = 1;
        }
    } fz_always(ctx) {
        pdf_drop_obj(ctx, objects);
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return found;
}

/* Gives the annotation `objnum` back the entries of a snapshot, keeping its object number, so
 * its replies and anything else pointing at it are untouched. */
int mupdf_pdf_restore_annot_snapshot(fz_context *ctx, fz_document *doc, int pageno, int objnum, fz_document *holding, int index, const char **out_error) {
    if (!ctx || !doc || !holding) return -1;
    pdf_page *ppage = NULL;
    pdf_graft_map *map = NULL;
    pdf_obj *copy = NULL;
    int found = 0;
    fz_var(ppage);
    fz_var(map);
    fz_var(copy);
    fz_var(found);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        pdf_obj *copies = pdf_array_get(ctx, pdf_dict_gets(ctx, pdf_trailer(ctx, (pdf_document *)holding), "VectorPDFStash"), index);
        if (!pdf_is_array(ctx, copies)) fz_throw(ctx, FZ_ERROR_GENERIC, "Nothing stashed there");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *annot = find_annot_by_objnum(ctx, ppage, objnum);
        if (annot) {
            pdf_obj *obj = pdf_annot_obj(ctx, annot);
            map = pdf_new_graft_map(ctx, pdoc);
            copy = pdf_graft_mapped_object(ctx, map, pdf_array_get(ctx, copies, 0));
            while (pdf_dict_len(ctx, obj) > 0) pdf_dict_del(ctx, obj, pdf_dict_get_key(ctx, obj, 0));
            int n = pdf_dict_len(ctx, copy);
            for (int i = 0; i < n; i++) pdf_dict_put(ctx, obj, pdf_dict_get_key(ctx, copy, i), pdf_dict_get_val(ctx, copy, i));
            pdf_dict_put(ctx, obj, PDF_NAME(P), ppage->obj);
            unstash_layer(ctx, pdoc, obj);
            found = 1;
        }
    } fz_always(ctx) {
        pdf_drop_obj(ctx, copy);
        pdf_drop_graft_map(ctx, map);
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return found;
}

static void offset_number_pairs(fz_context *ctx, pdf_obj *array, fz_point v) {
    int n = pdf_array_len(ctx, array);
    for (int i = 0; i + 1 < n; i += 2) {
        pdf_array_put_real(ctx, array, i, pdf_array_get_real(ctx, array, i) + v.x);
        pdf_array_put_real(ctx, array, i + 1, pdf_array_get_real(ctx, array, i + 1) + v.y);
    }
}

static void offset_rect_entry(fz_context *ctx, pdf_obj *obj, fz_point v) {
    pdf_obj *rect = pdf_dict_get(ctx, obj, PDF_NAME(Rect));
    if (pdf_is_array(ctx, rect)) offset_number_pairs(ctx, rect, v);
}

/* Moves the annotation `objnum` by (dx, dy) in page space. Only where it is changes: the
 * appearance it has, from whichever app made it, is drawn into its moved /Rect unchanged. */
int mupdf_pdf_translate_annot(fz_context *ctx, fz_document *doc, int pageno, int objnum, float dx, float dy, const char **out_error) {
    if (!ctx || !doc) return -1;
    pdf_page *ppage = NULL;
    int found = 0;
    fz_var(ppage);
    fz_var(found);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *annot = find_annot_by_objnum(ctx, ppage, objnum);
        if (annot) {
            fz_matrix page_ctm;
            pdf_page_transform(ctx, ppage, NULL, &page_ctm);
            fz_point v = fz_transform_vector(fz_make_point(dx, dy), fz_invert_matrix(page_ctm));
            pdf_obj *obj = pdf_annot_obj(ctx, annot);
            offset_rect_entry(ctx, obj, v);
            pdf_obj *popup = pdf_dict_get(ctx, obj, PDF_NAME(Popup));
            if (popup) offset_rect_entry(ctx, popup, v);
            pdf_obj *keys[] = { PDF_NAME(QuadPoints), PDF_NAME(Vertices), PDF_NAME(L), PDF_NAME(CL) };
            for (size_t k = 0; k < sizeof keys / sizeof keys[0]; k++) {
                pdf_obj *pairs = pdf_dict_get(ctx, obj, keys[k]);
                if (pdf_is_array(ctx, pairs)) offset_number_pairs(ctx, pairs, v);
            }
            pdf_obj *ink = pdf_dict_get(ctx, obj, PDF_NAME(InkList));
            for (int i = 0; i < pdf_array_len(ctx, ink); i++) offset_number_pairs(ctx, pdf_array_get(ctx, ink, i), v);
            found = 1;
        }
    } fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return found;
}

/* Changes how the annotation `objnum` looks, and has MuPDF draw it again from its entries:
 * a color (has_color), a line width (width >= 0), a line's ending (line_ending >= 0), the
 * box of a rectangle or oval (has_rect), or the ends of a line or the corners of a polygon
 * (points, count). */
int mupdf_pdf_restyle_annot(fz_context *ctx, fz_document *doc, int pageno, int objnum,
                            int has_color, float r, float g, float b, float width, int line_ending,
                            int has_rect, float x0, float y0, float x1, float y1,
                            const fz_point *points, int count, const char **out_error) {
    if (!ctx || !doc) return -1;
    pdf_page *ppage = NULL;
    int found = 0;
    fz_var(ppage);
    fz_var(found);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *annot = find_annot_by_objnum(ctx, ppage, objnum);
        if (annot) {
            enum pdf_annot_type type = pdf_annot_type(ctx, annot);
            if (has_color) {
                float color[3] = {r, g, b};
                pdf_set_annot_color(ctx, annot, 3, color);
            }
            if (width >= 0 && pdf_annot_has_border(ctx, annot)) pdf_set_annot_border_width(ctx, annot, width);
            if (line_ending >= 0 && type == PDF_ANNOT_LINE) {
                enum pdf_line_ending start, end;
                pdf_annot_line_ending_styles(ctx, annot, &start, &end);
                pdf_set_annot_line_ending_styles(ctx, annot, start, (enum pdf_line_ending)line_ending);
            }
            if (has_rect && (type == PDF_ANNOT_SQUARE || type == PDF_ANNOT_CIRCLE)) {
                pdf_set_annot_rect(ctx, annot, fz_make_rect(fminf(x0, x1), fminf(y0, y1), fmaxf(x0, x1), fmaxf(y0, y1)));
            }
            if (points && count >= 2 && type == PDF_ANNOT_LINE) pdf_set_annot_line(ctx, annot, points[0], points[1]);
            if (points && count >= 2 && (type == PDF_ANNOT_POLYGON || type == PDF_ANNOT_POLY_LINE)) pdf_set_annot_vertices(ctx, annot, count, points);
            pdf_update_annot(ctx, annot);
            found = 1;
        }
    } fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return found;
}

/* What the canvas needs to select, move and restyle the annotation `objnum`, in page space.
 * `points` gets a line's ends or a polygon's corners, up to `max_points`. */
int mupdf_pdf_describe_annot(fz_context *ctx, fz_document *doc, int pageno, int objnum, mupdf_annot_description *out,
                             fz_point *points, int max_points, const char **out_error) {
    if (!ctx || !doc || !out) return -1;
    memset(out, 0, sizeof *out);
    pdf_page *ppage = NULL;
    int found = 0;
    fz_var(ppage);
    fz_var(found);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *annot = find_annot_by_objnum(ctx, ppage, objnum);
        if (annot) {
            enum pdf_annot_type type = pdf_annot_type(ctx, annot);
            fz_strlcpy(out->subtype, pdf_string_from_annot_type(ctx, type), sizeof out->subtype);
            fz_rect bounds = pdf_bound_annot(ctx, annot);
            fz_rect rect = pdf_annot_has_rect(ctx, annot) ? pdf_annot_rect(ctx, annot) : bounds;
            out->x0 = rect.x0; out->y0 = rect.y0; out->x1 = rect.x1; out->y1 = rect.y1;
            out->bx0 = bounds.x0; out->by0 = bounds.y0; out->bx1 = bounds.x1; out->by1 = bounds.y1;
            int n = 0;
            float color[4] = {0};
            pdf_annot_color(ctx, annot, &n, color);
            out->has_color = n == 3;
            out->r = color[0]; out->g = color[1]; out->b = color[2];
            out->border_width = pdf_annot_has_border(ctx, annot) ? pdf_annot_border_width(ctx, annot) : 0;
            out->is_cloud = is_cloudy(ctx, annot);
            out->layer = vp_oc_layer(ctx, pdf_annot_obj(ctx, annot));
            out->hidden = vp_oc_hidden(ctx, pdoc, pdf_annot_obj(ctx, annot));
            out->line_ending = -1;
            if (type == PDF_ANNOT_LINE && points && max_points >= 2) {
                pdf_annot_line(ctx, annot, &points[0], &points[1]);
                out->point_count = 2;
                enum pdf_line_ending start, end;
                pdf_annot_line_ending_styles(ctx, annot, &start, &end);
                out->line_ending = end;
            } else if ((type == PDF_ANNOT_POLYGON || type == PDF_ANNOT_POLY_LINE) && points) {
                int count = pdf_annot_vertex_count(ctx, annot);
                out->point_count = count < max_points ? count : max_points;
                for (int i = 0; i < out->point_count; i++) points[i] = pdf_annot_vertex(ctx, annot, i);
            }
            enum pdf_intent intent = pdf_annot_has_intent(ctx, annot) ? pdf_annot_intent(ctx, annot) : PDF_ANNOT_IT_DEFAULT;
            out->is_measurement = intent == PDF_ANNOT_IT_LINE_DIMENSION || intent == PDF_ANNOT_IT_POLYLINE_DIMENSION
                || intent == PDF_ANNOT_IT_POLYGON_DIMENSION || pdf_dict_gets(ctx, pdf_annot_obj(ctx, annot), "Measure") != NULL;
            found = 1;
        }
    } fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return found;
}

/* Draws the annotation `objnum` alone, as MuPDF draws it on the page, at `scale` pixels per
 * point; `out_bounds` gets the page-space area the pixmap covers. */
int mupdf_pdf_render_annot(fz_context *ctx, fz_document *doc, int pageno, int objnum, float scale,
                           fz_pixmap **out_pixmap, fz_rect *out_bounds, const char **out_error) {
    if (!ctx || !doc || !out_pixmap || !out_bounds) return -1;
    *out_pixmap = NULL;
    pdf_page *ppage = NULL;
    fz_pixmap *pix = NULL;
    fz_device *dev = NULL;
    fz_var(ppage);
    fz_var(pix);
    fz_var(dev);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *annot = find_annot_by_objnum(ctx, ppage, objnum);
        if (!annot) fz_throw(ctx, FZ_ERROR_GENERIC, "No such annotation");
        fz_rect bounds = fz_expand_rect(pdf_bound_annot(ctx, annot), 1);
        *out_bounds = bounds;
        fz_matrix ctm = fz_scale(scale, scale);
        fz_irect ibox = fz_round_rect(fz_transform_rect(bounds, ctm));
        pix = fz_new_pixmap_with_bbox(ctx, fz_device_rgb(ctx), ibox, NULL, 1);
        fz_clear_pixmap(ctx, pix);
        dev = fz_new_draw_device(ctx, ctm, pix);
        pdf_run_annot(ctx, annot, dev, fz_identity, NULL);
        fz_close_device(ctx, dev);
        *out_pixmap = pix;
        pix = NULL;
    } fz_always(ctx) {
        fz_drop_device(ctx, dev);
        fz_drop_pixmap(ctx, pix);
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

/* Revision cloud: a square annotation with a cloudy border effect (/BE << /S /C /I intensity >>).
 * Unlike the callout's, this appearance is MuPDF's own, which is measured against Acrobat's. */
int mupdf_pdf_add_cloud_annot(fz_context *ctx, fz_document *doc, int pageno,
                              float x0, float y0, float x1, float y1, float intensity,
                              float r, float g, float b, const char **out_error) {
    if (!ctx || !doc) return -1;
    pdf_page *ppage = NULL;
    pdf_annot *annot = NULL;
    fz_var(ppage);
    fz_var(annot);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        annot = pdf_create_annot(ctx, ppage, PDF_ANNOT_SQUARE);
        float color[3] = {r, g, b};
        pdf_set_annot_rect(ctx, annot, fz_make_rect(fminf(x0, x1), fminf(y0, y1), fmaxf(x0, x1), fmaxf(y0, y1)));
        pdf_set_annot_color(ctx, annot, 3, color);
        pdf_set_annot_border_width(ctx, annot, 1.5f);
        pdf_set_annot_border_effect(ctx, annot, PDF_BORDER_EFFECT_CLOUDY);
        pdf_set_annot_border_effect_intensity(ctx, annot, intensity);
        pdf_update_annot(ctx, annot);
        pdf_set_annot_resynthesised(ctx, annot);
    }
    fz_always(ctx) {
        pdf_drop_annot(ctx, annot);
        if (ppage) pdf_drop_page(ctx, ppage);
    }
    fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

/* Revision cloud round any outline: a Polygon annotation with the same cloudy border. */
int mupdf_pdf_add_cloud_polygon_annot(fz_context *ctx, fz_document *doc, int pageno,
                                      const fz_point *points, int count, float intensity,
                                      float r, float g, float b, const char **out_error) {
    if (!ctx || !doc || !points || count < 3) return -1;
    pdf_page *ppage = NULL;
    pdf_annot *annot = NULL;
    fz_var(ppage);
    fz_var(annot);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        annot = pdf_create_annot(ctx, ppage, PDF_ANNOT_POLYGON);
        pdf_set_annot_vertices(ctx, annot, count, points);
        float color[3] = {r, g, b};
        pdf_set_annot_color(ctx, annot, 3, color);
        pdf_set_annot_border_width(ctx, annot, 1.5f);
        pdf_set_annot_border_effect(ctx, annot, PDF_BORDER_EFFECT_CLOUDY);
        pdf_set_annot_border_effect_intensity(ctx, annot, intensity);
        pdf_update_annot(ctx, annot);
        pdf_set_annot_resynthesised(ctx, annot);
    }
    fz_always(ctx) {
        pdf_drop_annot(ctx, annot);
        if (ppage) pdf_drop_page(ctx, ppage);
    }
    fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

/* Rectangle, oval or line, with MuPDF's own appearance, which centres a rectangle's or oval's
 * border on its Rect, as the canvas draws it. */
int mupdf_pdf_add_shape_annot(fz_context *ctx, fz_document *doc, int pageno, int kind,
                              float x0, float y0, float x1, float y1, float width, int line_ending,
                              float r, float g, float b, const char **out_error) {
    if (!ctx || !doc || kind < 0 || kind > 2) return -1;
    pdf_page *ppage = NULL;
    pdf_annot *annot = NULL;
    fz_var(ppage);
    fz_var(annot);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        float color[3] = {r, g, b};
        if (kind == 2) {
            annot = pdf_create_annot(ctx, ppage, PDF_ANNOT_LINE);
            pdf_set_annot_line(ctx, annot, fz_make_point(x0, y0), fz_make_point(x1, y1));
            pdf_set_annot_line_ending_styles(ctx, annot, PDF_ANNOT_LE_NONE, (enum pdf_line_ending)line_ending);
        } else {
            annot = pdf_create_annot(ctx, ppage, kind == 0 ? PDF_ANNOT_SQUARE : PDF_ANNOT_CIRCLE);
            pdf_set_annot_rect(ctx, annot, fz_make_rect(fminf(x0, x1), fminf(y0, y1), fmaxf(x0, x1), fmaxf(y0, y1)));
        }
        pdf_set_annot_color(ctx, annot, 3, color);
        pdf_set_annot_border_width(ctx, annot, width);
        pdf_update_annot(ctx, annot);
        pdf_set_annot_resynthesised(ctx, annot);
    }
    fz_always(ctx) {
        pdf_drop_annot(ctx, annot);
        if (ppage) pdf_drop_page(ctx, ppage);
    }
    fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

/* Sticky note: a Text annotation with the Comment icon and a popup for viewers that use one. */
int mupdf_pdf_add_note_annot(fz_context *ctx, fz_document *doc, int pageno,
                             float x0, float y0, float x1, float y1, const char *text,
                             float r, float g, float b, const char **out_error) {
    if (!ctx || !doc || !text) return -1;
    pdf_page *ppage = NULL;
    pdf_annot *annot = NULL;
    fz_var(ppage);
    fz_var(annot);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        annot = pdf_create_annot(ctx, ppage, PDF_ANNOT_TEXT);
        float color[3] = {r, g, b};
        pdf_set_annot_rect(ctx, annot, fz_make_rect(x0, y0, x1, y1));
        pdf_set_annot_icon_name(ctx, annot, "Comment");
        pdf_set_annot_color(ctx, annot, 3, color);
        pdf_set_annot_contents(ctx, annot, text);
        pdf_set_annot_popup(ctx, annot, fz_make_rect(x1, y0, x1 + 200.0f, y0 + 100.0f));
        pdf_update_annot(ctx, annot);
        pdf_set_annot_resynthesised(ctx, annot);
    }
    fz_always(ctx) {
        pdf_drop_annot(ctx, annot);
        if (ppage) pdf_drop_page(ctx, ppage);
    }
    fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

// These write the dictionary directly: MuPDF's setters would mark the annotation for a new
// appearance, and that would replace the hand-built ones.
static void stamp_annot_identity(fz_context *ctx, pdf_obj *obj, const char *author) {
    int64_t now = (int64_t)time(NULL);
    pdf_dict_put_text_string(ctx, obj, PDF_NAME(T), author);
    if (!pdf_dict_get(ctx, obj, PDF_NAME(CreationDate))) pdf_dict_put_date(ctx, obj, PDF_NAME(CreationDate), now);
    pdf_dict_put_date(ctx, obj, PDF_NAME(M), now);
}

int mupdf_pdf_set_annot_author(fz_context *ctx, fz_document *doc, int pageno, int objnum, const char *author, const char **out_error) {
    if (!ctx || !doc || !author) return -1;
    pdf_page *ppage = NULL;
    int found = 0;
    fz_var(ppage);
    fz_var(found);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *a = find_annot_by_objnum(ctx, ppage, objnum);
        if (a) {
            stamp_annot_identity(ctx, pdf_annot_obj(ctx, a), author);
            found = 1;
        }
    }
    fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    }
    fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return found;
}

int mupdf_pdf_set_annot_comment(fz_context *ctx, fz_document *doc, int pageno, int objnum, const char *text, const char **out_error) {
    if (!ctx || !doc || !text) return -1;
    pdf_page *ppage = NULL;
    int found = 0;
    fz_var(ppage);
    fz_var(found);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *a = find_annot_by_objnum(ctx, ppage, objnum);
        if (a) {
            pdf_dict_put_text_string(ctx, pdf_annot_obj(ctx, a), PDF_NAME(Contents), text);
            pdf_dict_put_date(ctx, pdf_annot_obj(ctx, a), PDF_NAME(M), (int64_t)time(NULL));
            found = 1;
        }
    }
    fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    }
    fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return found;
}

/* A reply is a Text annotation with /IRT and /RT /R (ISO 32000 12.5.6.2). A status is the same with
 * /State and /StateModel, hidden as Acrobat hides them (12.5.6.3). Both get an empty appearance,
 * since a viewer that doesn't understand threads would otherwise draw a note icon for each. */
int mupdf_pdf_add_annot_reply(fz_context *ctx, fz_document *doc, int pageno, int parent_objnum,
                              const char *text, const char *author,
                              const char *state, const char *state_model, const char **out_error) {
    if (!ctx || !doc || !text || !author) return -1;
    pdf_page *ppage = NULL;
    pdf_annot *reply = NULL;
    fz_buffer *empty = NULL;
    fz_var(ppage);
    fz_var(reply);
    fz_var(empty);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *parent = find_annot_by_objnum(ctx, ppage, parent_objnum);
        if (!parent) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Annotation to reply to not found");
        reply = pdf_create_annot(ctx, ppage, PDF_ANNOT_TEXT);
        pdf_obj *obj = pdf_annot_obj(ctx, reply);
        pdf_set_annot_icon_name(ctx, reply, "Comment");
        pdf_set_annot_contents(ctx, reply, text);
        if (state) pdf_set_annot_flags(ctx, reply, PDF_ANNOT_IS_HIDDEN | PDF_ANNOT_IS_PRINT | PDF_ANNOT_IS_NO_ZOOM | PDF_ANNOT_IS_NO_ROTATE);
        pdf_update_annot(ctx, reply);
        pdf_obj *n = pdf_dict_getp(ctx, obj, "AP/N");
        if (n) {
            empty = fz_new_buffer(ctx, 1);
            pdf_update_stream(ctx, pdoc, n, empty, 0);
        }
        pdf_dict_put(ctx, obj, PDF_NAME(Rect), pdf_dict_get(ctx, pdf_annot_obj(ctx, parent), PDF_NAME(Rect)));
        pdf_dict_put(ctx, obj, PDF_NAME(IRT), pdf_annot_obj(ctx, parent));
        pdf_dict_put(ctx, obj, PDF_NAME(RT), PDF_NAME(R));
        if (state) {
            pdf_dict_puts_drop(ctx, obj, "State", pdf_new_text_string(ctx, state));
            pdf_dict_puts_drop(ctx, obj, "StateModel", pdf_new_text_string(ctx, state_model ? state_model : "Review"));
        }
        stamp_annot_identity(ctx, obj, author);
    }
    fz_always(ctx) {
        fz_drop_buffer(ctx, empty);
        pdf_drop_annot(ctx, reply);
        if (ppage) pdf_drop_page(ctx, ppage);
    }
    fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

/* Editing or moving an annotation re-creates it, so its author, creation date and replies have to
 * follow it to the new object. */
int mupdf_pdf_move_annot_thread(fz_context *ctx, fz_document *doc, int pageno, int from_objnum, int to_objnum, const char **out_error) {
    if (!ctx || !doc) return -1;
    pdf_page *ppage = NULL;
    fz_var(ppage);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *from = find_annot_by_objnum(ctx, ppage, from_objnum);
        pdf_annot *to = find_annot_by_objnum(ctx, ppage, to_objnum);
        if (from && to) {
            pdf_obj *from_obj = pdf_annot_obj(ctx, from);
            pdf_obj *to_obj = pdf_annot_obj(ctx, to);
            if (pdf_dict_get(ctx, from_obj, PDF_NAME(T)))
                pdf_dict_put(ctx, to_obj, PDF_NAME(T), pdf_dict_get(ctx, from_obj, PDF_NAME(T)));
            if (pdf_dict_get(ctx, from_obj, PDF_NAME(CreationDate)))
                pdf_dict_put(ctx, to_obj, PDF_NAME(CreationDate), pdf_dict_get(ctx, from_obj, PDF_NAME(CreationDate)));
            for (pdf_annot *a = pdf_first_annot(ctx, ppage); a; a = pdf_next_annot(ctx, a)) {
                pdf_obj *obj = pdf_annot_obj(ctx, a);
                if (pdf_to_num(ctx, pdf_dict_get(ctx, obj, PDF_NAME(IRT))) == from_objnum) {
                    pdf_dict_put(ctx, obj, PDF_NAME(IRT), to_obj);
                    pdf_dict_put(ctx, obj, PDF_NAME(Rect), pdf_dict_get(ctx, to_obj, PDF_NAME(Rect)));
                }
            }
        }
    }
    fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    }
    fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

void mupdf_pdf_free_review_annots(fz_context *ctx, mupdf_review_annot *annots, int count) {
    if (!ctx || !annots) return;
    for (int i = 0; i < count; i++) {
        fz_free(ctx, annots[i].author);
        fz_free(ctx, annots[i].contents);
        fz_free(ctx, annots[i].state);
        fz_free(ctx, annots[i].state_model);
    }
    fz_free(ctx, annots);
}

/* Lists every reviewable annotation on a page: everything a reader sees as a markup, from any app.
 * The entries read the dictionary, as MuPDF's getters throw on subtypes that don't allow a key. */
int mupdf_pdf_get_review_annots(fz_context *ctx, fz_document *doc, int pageno,
                                mupdf_review_annot **out, int *out_count, const char **out_error) {
    if (!ctx || !doc || !out || !out_count) return -1;
    *out = NULL;
    *out_count = 0;
    pdf_page *ppage = NULL;
    mupdf_review_annot *list = NULL;
    int count = 0;
    fz_var(ppage);
    fz_var(list);
    fz_var(count);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        int capacity = 0;
        for (pdf_annot *a = pdf_first_annot(ctx, ppage); a; a = pdf_next_annot(ctx, a)) capacity++;
        if (capacity > 0) list = fz_calloc(ctx, capacity, sizeof(*list));
        for (pdf_annot *a = pdf_first_annot(ctx, ppage); a; a = pdf_next_annot(ctx, a)) {
            enum pdf_annot_type type = pdf_annot_type(ctx, a);
            if (type == PDF_ANNOT_POPUP || type == PDF_ANNOT_LINK || type == PDF_ANNOT_REDACT) continue;
            pdf_obj *obj = pdf_annot_obj(ctx, a);
            mupdf_review_annot *e = &list[count++];
            e->objnum = pdf_to_num(ctx, obj);
            // A grouped annotation (/RT /Group) is a part of its parent's shape, not an answer to it.
            if (!pdf_name_eq(ctx, pdf_dict_get(ctx, obj, PDF_NAME(RT)), PDF_NAME(Group)))
                e->parent_objnum = pdf_to_num(ctx, pdf_dict_get(ctx, obj, PDF_NAME(IRT)));
            fz_rect r = pdf_bound_annot(ctx, a);
            e->x0 = r.x0; e->y0 = r.y0; e->x1 = r.x1; e->y1 = r.y1;
            pdf_obj *c = pdf_dict_get(ctx, obj, PDF_NAME(C));
            int n = pdf_array_len(ctx, c);
            if (n == 3) {
                e->r = pdf_array_get_real(ctx, c, 0); e->g = pdf_array_get_real(ctx, c, 1); e->b = pdf_array_get_real(ctx, c, 2);
            } else if (n == 1) {
                e->r = e->g = e->b = pdf_array_get_real(ctx, c, 0);
            }
            e->created = pdf_dict_get_date(ctx, obj, PDF_NAME(CreationDate));
            e->modified = pdf_dict_get_date(ctx, obj, PDF_NAME(M));
            fz_strlcpy(e->subtype, pdf_string_from_annot_type(ctx, type), sizeof(e->subtype));
            e->is_callout = type == PDF_ANNOT_FREE_TEXT && pdf_name_eq(ctx, pdf_dict_get(ctx, obj, PDF_NAME(IT)), PDF_NAME(FreeTextCallout));
            e->is_cloud = pdf_name_eq(ctx, pdf_dict_getp(ctx, obj, "BE/S"), PDF_NAME(C));
            e->layer = vp_oc_layer(ctx, obj);
            e->hidden = vp_oc_hidden(ctx, pdoc, obj);
            e->author = fz_strdup(ctx, pdf_dict_get_text_string(ctx, obj, PDF_NAME(T)));
            e->contents = fz_strdup(ctx, pdf_dict_get_text_string(ctx, obj, PDF_NAME(Contents)));
            e->state = fz_strdup(ctx, pdf_to_text_string(ctx, pdf_dict_gets(ctx, obj, "State")));
            e->state_model = fz_strdup(ctx, pdf_to_text_string(ctx, pdf_dict_gets(ctx, obj, "StateModel")));
        }
    }
    fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    }
    fz_catch(ctx) {
        mupdf_pdf_free_review_annots(ctx, list, count);
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    *out = list;
    *out_count = count;
    return 0;
}

/* Lists the measurement annotations on a page (dimension lines, perimeters, areas and angles as
 * written by the functions above, or by other tools using the same /IT intents). Fills up to
 * `capacity` entries of `out` and sets *out_count to the total found, which may be larger. */
int mupdf_pdf_get_measurement_annots(fz_context *ctx, fz_document *doc, int pageno,
                                     mupdf_measurement_annot *out, int capacity, int *out_count,
                                     const char **out_error) {
    if (!ctx || !doc || !out_count) return -1;
    *out_count = 0;
    pdf_page *ppage = NULL;
    int count = 0;
    fz_var(ppage);
    fz_var(count);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        for (pdf_annot *a = pdf_first_annot(ctx, ppage); a; a = pdf_next_annot(ctx, a)) {
            enum pdf_annot_type atype = pdf_annot_type(ctx, a);
            enum pdf_intent intent = pdf_annot_intent(ctx, a);
            const char *contents = pdf_annot_contents(ctx, a);
            int kind = 0;
            if (atype == PDF_ANNOT_LINE && intent == PDF_ANNOT_IT_LINE_DIMENSION) {
                kind = 1;
            } else if (atype == PDF_ANNOT_POLY_LINE && intent == PDF_ANNOT_IT_POLYLINE_DIMENSION) {
                kind = 2;
            } else if (atype == PDF_ANNOT_POLYGON && intent == PDF_ANNOT_IT_POLYGON_DIMENSION) {
                kind = 3;
            } else if (atype == PDF_ANNOT_POLY_LINE && pdf_annot_vertex_count(ctx, a) == 3) {
                const char *subj = pdf_dict_get_text_string(ctx, pdf_annot_obj(ctx, a), PDF_NAME(Subj));
                /* Angles written before /Subj was added are recognised by their degree label. */
                if ((subj && strcmp(subj, "Angle") == 0) || (contents && strstr(contents, "\xC2\xB0"))) {
                    kind = 4;
                }
            }
            if (!kind) continue;

            if (out && count < capacity) {
                mupdf_measurement_annot *m = &out[count];
                memset(m, 0, sizeof(*m));
                m->kind = kind;
                m->objnum = pdf_to_num(ctx, pdf_annot_obj(ctx, a));
                m->layer = vp_oc_layer(ctx, pdf_annot_obj(ctx, a));
                m->hidden = vp_oc_hidden(ctx, pdoc, pdf_annot_obj(ctx, a));
                int n_color = 0;
                float color[4] = {0, 0, 0, 0};
                pdf_annot_color(ctx, a, &n_color, color);
                if (n_color == 3) {
                    m->r = color[0]; m->g = color[1]; m->b = color[2];
                } else if (n_color == 1) {
                    m->r = m->g = m->b = color[0];
                }
                /* The getters below return page (top-down) coordinates. */
                if (kind == 1) {
                    fz_point p0, p1;
                    pdf_annot_line(ctx, a, &p0, &p1);
                    m->n_points = 2;
                    m->xy[0] = p0.x; m->xy[1] = p0.y;
                    m->xy[2] = p1.x; m->xy[3] = p1.y;
                } else {
                    int n = pdf_annot_vertex_count(ctx, a);
                    if (n > MUPDF_MEASUREMENT_MAX_POINTS) n = MUPDF_MEASUREMENT_MAX_POINTS;
                    for (int i = 0; i < n; i++) {
                        fz_point v = pdf_annot_vertex(ctx, a, i);
                        m->xy[2 * i] = v.x;
                        m->xy[2 * i + 1] = v.y;
                    }
                    m->n_points = n;
                }
                if (contents) {
                    strncpy(m->text, contents, sizeof(m->text) - 1);
                }
            }
            count++;
        }
    }
    fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    }
    fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    *out_count = count;
    return 0;
}

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
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        prepare_document_for_save(ctx, pdoc);
        pdf_write_options save_opts = default_save_options();
        pdf_save_document(ctx, pdoc, path, &save_opts);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_save_encrypted(fz_context *ctx, fz_document *doc, const char *path, const char *password, const char **out_error) {
    if (!ctx || !doc || !path) return -1;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        prepare_document_for_save(ctx, pdoc);
        pdf_write_options opts = default_save_options();
        if (password && *password) {
            opts.do_encrypt = PDF_ENCRYPT_AES_256;
            strncpy(opts.upwd_utf8, password, sizeof(opts.upwd_utf8) - 1);
            opts.upwd_utf8[sizeof(opts.upwd_utf8) - 1] = '\0';
            strncpy(opts.opwd_utf8, password, sizeof(opts.opwd_utf8) - 1);
            opts.opwd_utf8[sizeof(opts.opwd_utf8) - 1] = '\0';
        }
        pdf_save_document(ctx, pdoc, path, &opts);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

// Attachments

typedef void (*attachment_visitor)(fz_context *ctx, pdf_obj *fs, int page, const char *fallback_name, void *arg);

static int seen_object(fz_context *ctx, int **seen, int *count, int *cap, int num) {
    if (num <= 0) return 0; // a direct object can't be listed twice by reference
    for (int i = 0; i < *count; i++)
        if ((*seen)[i] == num) return 1;
    if (*count == *cap) {
        *cap = *cap ? *cap * 2 : 16;
        *seen = fz_realloc_array(ctx, *seen, *cap, int);
    }
    (*seen)[(*count)++] = num;
    return 0;
}

// Calls `visit` for each embedded file, in the order mupdf_pdf_list_attachments documents.
static void walk_attachments(fz_context *ctx, pdf_document *pdoc, attachment_visitor visit, void *arg) {
    pdf_obj *tree = NULL;
    int *seen = NULL, seen_count = 0, seen_cap = 0;
    fz_var(tree);
    fz_var(seen);
    fz_try(ctx) {
        tree = pdf_load_name_tree(ctx, pdoc, PDF_NAME(EmbeddedFiles));
        int n = pdf_dict_len(ctx, tree);
        for (int i = 0; i < n; i++) {
            pdf_obj *fs = pdf_dict_get_val(ctx, tree, i);
            if (!pdf_is_embedded_file(ctx, fs) || seen_object(ctx, &seen, &seen_count, &seen_cap, pdf_to_num(ctx, fs))) continue;
            visit(ctx, fs, -1, pdf_to_name(ctx, pdf_dict_get_key(ctx, tree, i)), arg);
        }
        int associated = pdf_count_document_associated_files(ctx, pdoc);
        for (int i = 0; i < associated; i++) {
            pdf_obj *fs = pdf_document_associated_file(ctx, pdoc, i);
            if (!pdf_is_embedded_file(ctx, fs) || seen_object(ctx, &seen, &seen_count, &seen_cap, pdf_to_num(ctx, fs))) continue;
            visit(ctx, fs, -1, NULL, arg);
        }
        // From the page objects rather than loaded pages, so a long document is quick to read.
        int pages = pdf_count_pages(ctx, pdoc);
        for (int p = 0; p < pages; p++) {
            pdf_obj *annots = pdf_dict_get(ctx, pdf_lookup_page_obj(ctx, pdoc, p), PDF_NAME(Annots));
            int count = pdf_array_len(ctx, annots);
            for (int a = 0; a < count; a++) {
                pdf_obj *annot = pdf_array_get(ctx, annots, a);
                if (!pdf_name_eq(ctx, pdf_dict_get(ctx, annot, PDF_NAME(Subtype)), PDF_NAME(FileAttachment))) continue;
                pdf_obj *fs = pdf_dict_get(ctx, annot, PDF_NAME(FS));
                if (!pdf_is_embedded_file(ctx, fs) || seen_object(ctx, &seen, &seen_count, &seen_cap, pdf_to_num(ctx, fs))) continue;
                visit(ctx, fs, p, NULL, arg);
            }
        }
    } fz_always(ctx) {
        pdf_drop_obj(ctx, tree);
        fz_free(ctx, seen);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
}

static void copy_text(char *dst, size_t size, const char *src) {
    if (!src) src = "";
    strncpy(dst, src, size - 1);
    dst[size - 1] = '\0';
}

typedef struct { mupdf_attachment *out; int capacity; int count; } list_state;

static void list_attachment(fz_context *ctx, pdf_obj *fs, int page, const char *fallback_name, void *arg) {
    list_state *state = arg;
    if (state->count < state->capacity) {
        mupdf_attachment *entry = &state->out[state->count];
        pdf_filespec_params params;
        pdf_get_filespec_params(ctx, fs, &params);
        entry->page = page;
        entry->size = params.size > 0 ? params.size : -1;
        entry->created = params.created;
        entry->modified = params.modified;
        copy_text(entry->name, sizeof entry->name, params.filename && *params.filename ? params.filename : fallback_name);
        // MuPDF reports a missing /Subtype as application/octet-stream; that says nothing.
        const char *mime = params.mimetype && strcmp(params.mimetype, "application/octet-stream") ? params.mimetype : "";
        copy_text(entry->mime_type, sizeof entry->mime_type, mime);
        copy_text(entry->description, sizeof entry->description, pdf_dict_get_text_string(ctx, fs, PDF_NAME(Desc)));
    }
    state->count++;
}

int mupdf_pdf_list_attachments(fz_context *ctx, fz_document *doc, mupdf_attachment *out, int capacity) {
    if (!ctx || !doc) return 0;
    list_state state = { out, out ? capacity : 0, 0 };
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (pdoc) walk_attachments(ctx, pdoc, list_attachment, &state);
    } fz_catch(ctx) {
        fz_report_error(ctx);
        return 0;
    }
    return state.count;
}

typedef struct { int index; int position; pdf_obj *found; } find_state;

static void find_attachment(fz_context *ctx, pdf_obj *fs, int page, const char *fallback_name, void *arg) {
    find_state *state = arg;
    if (state->position++ == state->index) state->found = pdf_keep_obj(ctx, fs);
}

int mupdf_pdf_save_attachment(fz_context *ctx, fz_document *doc, int index, const char *path, const char **out_error) {
    if (!ctx || !doc || !path || index < 0) return -1;
    find_state state = { index, 0, NULL };
    fz_buffer *contents = NULL;
    fz_var(contents);
    fz_var(state.found);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        walk_attachments(ctx, pdoc, find_attachment, &state);
        if (!state.found) fz_throw(ctx, FZ_ERROR_ARGUMENT, "No such attachment");
        contents = pdf_load_embedded_file_contents(ctx, state.found);
        if (!contents) fz_throw(ctx, FZ_ERROR_FORMAT, "The attachment has no contents");
        fz_save_buffer(ctx, contents, path);
    } fz_always(ctx) {
        fz_drop_buffer(ctx, contents);
        pdf_drop_obj(ctx, state.found);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_add_attachment(fz_context *ctx, fz_document *doc, const char *name, const char *mime_type, const unsigned char *data, size_t length, const char *description, const char **out_error) {
    if (!ctx || !doc || !name) return -1;
    fz_buffer *contents = NULL;
    pdf_obj *fs = NULL;
    fz_var(contents);
    fz_var(fs);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        contents = fz_new_buffer_from_copied_data(ctx, data, length);
        int64_t now = (int64_t)time(NULL);
        fs = pdf_add_embedded_file(ctx, pdoc, name, mime_type, contents, now, now, 1);
        if (description && *description)
            pdf_dict_put_text_string(ctx, fs, PDF_NAME(Desc), description);
        pdf_obj *root = pdf_dict_get(ctx, pdf_trailer(ctx, pdoc), PDF_NAME(Root));
        pdf_obj *names = pdf_dict_get(ctx, root, PDF_NAME(Names));
        if (!names) names = pdf_dict_put_dict(ctx, root, PDF_NAME(Names), 1);
        pdf_obj *tree = pdf_dict_get(ctx, names, PDF_NAME(EmbeddedFiles));
        if (!tree) tree = pdf_dict_put_dict(ctx, names, PDF_NAME(EmbeddedFiles), 1);
        if (pdf_dict_get(ctx, tree, PDF_NAME(Kids)))
            fz_throw(ctx, FZ_ERROR_UNSUPPORTED, "Can't add to this document's attachments");
        pdf_obj *list = pdf_dict_get(ctx, tree, PDF_NAME(Names));
        if (!list) list = pdf_dict_put_array(ctx, tree, PDF_NAME(Names), 2);
        // A name tree is kept in key order.
        int len = pdf_array_len(ctx, list), at = len;
        for (int i = 0; i + 1 < len; i += 2)
            if (strcmp(pdf_array_get_text_string(ctx, list, i), name) > 0) { at = i; break; }
        pdf_array_insert_drop(ctx, list, pdf_new_text_string(ctx, name), at);
        pdf_array_insert(ctx, list, fs, at + 1);
    } fz_always(ctx) {
        fz_drop_buffer(ctx, contents);
        pdf_drop_obj(ctx, fs);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_save_optimized(fz_context *ctx, fz_document *doc, const char *path, int subset_fonts, int image_dpi, int outline_text, const char **out_error) {
    if (!ctx || !doc || !path) return -1;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        // Loads every object first, so a repair can't happen part way and lose the edits below.
        pdf_check_document(ctx, pdoc);
        // In pdf_clean_file's order: outlining text leaves fonts unused, before they're subset.
        if (outline_text)
            pdf_vectorize_pages(ctx, pdoc, 0, NULL, PDF_CLEAN_VECTORIZE_YES);
        if (image_dpi > 0) {
            pdf_image_rewriter_options img = { 0 };
            int threshold = image_dpi + image_dpi / 2;
            // JPEGs are re-encoded as JPEG; lossless images stay lossless, so line art and
            // screenshots don't pick up JPEG artefacts. Black-and-white scans are left alone.
            char *quality = image_dpi >= 300 ? "85" : "75";
            img.color_lossy_image_subsample_method = FZ_SUBSAMPLE_BICUBIC;
            img.color_lossy_image_subsample_threshold = threshold;
            img.color_lossy_image_subsample_to = image_dpi;
            img.color_lossy_image_recompress_method = FZ_RECOMPRESS_JPEG;
            img.color_lossy_image_recompress_quality = quality;
            img.color_lossless_image_subsample_method = FZ_SUBSAMPLE_BICUBIC;
            img.color_lossless_image_subsample_threshold = threshold;
            img.color_lossless_image_subsample_to = image_dpi;
            img.color_lossless_image_recompress_method = FZ_RECOMPRESS_LOSSLESS;
            img.gray_lossy_image_subsample_method = FZ_SUBSAMPLE_BICUBIC;
            img.gray_lossy_image_subsample_threshold = threshold;
            img.gray_lossy_image_subsample_to = image_dpi;
            img.gray_lossy_image_recompress_method = FZ_RECOMPRESS_JPEG;
            img.gray_lossy_image_recompress_quality = quality;
            img.gray_lossless_image_subsample_method = FZ_SUBSAMPLE_BICUBIC;
            img.gray_lossless_image_subsample_threshold = threshold;
            img.gray_lossless_image_subsample_to = image_dpi;
            img.gray_lossless_image_recompress_method = FZ_RECOMPRESS_LOSSLESS;
            img.bitonal_image_recompress_method = FZ_RECOMPRESS_NEVER;
            // Keeps an image as it was if the new one comes out bigger.
            img.recompress_when = FZ_RECOMPRESS_WHEN_SMALLER;
            pdf_rewrite_images(ctx, pdoc, &img);
        }
        if (subset_fonts)
            pdf_subset_fonts(ctx, pdoc, 0, NULL);
        pdf_write_options opts = default_save_options();
        opts.do_garbage = 3;  // also merges duplicate objects, such as fonts embedded twice
        opts.do_compress = 1; // zlib: other readers don't all support brotli
        opts.do_compress_images = 1;
        opts.do_compress_fonts = 1;
        opts.do_use_objstms = 1;
        pdf_save_document(ctx, pdoc, path, &opts);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_save_flattened(fz_context *ctx, fz_document *doc, const char *path, int bake_annots, int bake_widgets, const char **out_error) {
    if (!ctx || !doc || !path) return -1;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        prepare_document_for_save(ctx, pdoc);
        pdf_bake_document(ctx, pdoc, bake_annots, bake_widgets);
        pdf_write_options save_opts = default_save_options();
        pdf_save_document(ctx, pdoc, path, &save_opts);
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

// MARK: - Page labels
//
// A label range starts at a page and runs to the start of the next range. A range of one page
// names that page, like a sheet code, so it moves with the page. A longer range numbers positions,
// so moving a page within it leaves the numbers in order.

// pdf_page_label recurses through /Kids with no check for cycles, and spells out a Roman numeral
// one M at a time, so a crafted file could overflow the stack or stall it. Trees past these limits
// count as malformed, and are never passed to it.
#define VP_LABEL_MAX_DEPTH 32
#define VP_LABEL_MAX_NODES 65536
#define VP_LABEL_MAX_ROMAN_START 100000

typedef struct {
    int start;
    int length;
    pdf_obj *label;   // NULL for pages before the first range, which are numbered from their index
} vp_label_range;

typedef struct {
    vp_label_range *ranges;
    int count;
    int page_count;
    int nodes;
    int malformed;
} vp_label_walk;

struct mupdf_page_labels {
    pdf_obj *tree;
    vp_label_range *ranges;
    int count;
    int page_count;
};

static pdf_obj *vp_label_tree(fz_context *ctx, pdf_document *pdoc) {
    pdf_obj *root = pdf_dict_get(ctx, pdf_trailer(ctx, pdoc), PDF_NAME(Root));
    return pdf_dict_get(ctx, root, PDF_NAME(PageLabels));
}

static int vp_label_is_safe(fz_context *ctx, pdf_obj *label) {
    pdf_obj *style = pdf_dict_get(ctx, label, PDF_NAME(S));
    if (style != PDF_NAME(R) && style != PDF_NAME(r)) return 1;
    return pdf_dict_get_int(ctx, label, PDF_NAME(St)) <= VP_LABEL_MAX_ROMAN_START;
}

static void vp_walk_label_node(fz_context *ctx, pdf_obj *node, int depth, vp_label_walk *walk) {
    if (walk->malformed) return;
    if (depth > VP_LABEL_MAX_DEPTH || ++walk->nodes > VP_LABEL_MAX_NODES) {
        walk->malformed = 1;
        return;
    }
    pdf_obj *kids = pdf_dict_get(ctx, node, PDF_NAME(Kids));
    for (int i = 0; i < pdf_array_len(ctx, kids); i++) {
        vp_walk_label_node(ctx, pdf_array_get(ctx, kids, i), depth + 1, walk);
    }
    pdf_obj *nums = pdf_dict_get(ctx, node, PDF_NAME(Nums));
    for (int i = 0; i + 1 < pdf_array_len(ctx, nums); i += 2) {
        int key = pdf_array_get_int(ctx, nums, i);
        pdf_obj *label = pdf_array_get(ctx, nums, i + 1);
        if (key < 0 || key >= walk->page_count) continue;
        if (!vp_label_is_safe(ctx, label)) {
            walk->malformed = 1;
            return;
        }
        // A malformed tree can repeat a key. MuPDF reads the last one.
        vp_label_range *last = walk->count > 0 ? &walk->ranges[walk->count - 1] : NULL;
        if (last && key < last->start) continue;
        if (last && key == last->start) {
            last->label = label;
        } else {
            walk->ranges[walk->count].start = key;
            walk->ranges[walk->count].length = 0;
            walk->ranges[walk->count].label = label;
            walk->count++;
        }
    }
}

/// Reads the tree into `walk`, with one range per stretch of pages. `walk->ranges` is the caller's
/// to free. No ranges means the document has no usable labels.
static void vp_load_label_ranges(fz_context *ctx, pdf_document *pdoc, pdf_obj *tree, vp_label_walk *walk) {
    memset(walk, 0, sizeof(*walk));
    walk->page_count = pdf_count_pages(ctx, pdoc);
    // Keys ascend and are below page_count, and one more for the pages before the first range.
    walk->ranges = (vp_label_range *)fz_malloc(ctx, (walk->page_count + 1) * sizeof(vp_label_range));
    vp_walk_label_node(ctx, tree, 0, walk);
    if (walk->malformed) walk->count = 0;
    if (walk->count > 0 && walk->ranges[0].start > 0) {
        memmove(walk->ranges + 1, walk->ranges, walk->count * sizeof(vp_label_range));
        walk->ranges[0].start = 0;
        walk->ranges[0].label = NULL;
        walk->count++;
    }
    for (int i = 0; i < walk->count; i++) {
        int end = i + 1 < walk->count ? walk->ranges[i + 1].start : walk->page_count;
        walk->ranges[i].length = end - walk->ranges[i].start;
    }
}

int mupdf_pdf_has_page_labels(fz_context *ctx, fz_document *doc) {
    if (!ctx || !doc) return 0;
    int has_labels = 0;
    vp_label_walk walk = { 0 };
    fz_var(has_labels);
    fz_var(walk);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        pdf_obj *tree = pdoc ? vp_label_tree(ctx, pdoc) : NULL;
        if (tree) {
            vp_load_label_ranges(ctx, pdoc, tree, &walk);
            has_labels = walk.count > 0;
        }
    } fz_always(ctx) {
        fz_free(ctx, walk.ranges);
    } fz_catch(ctx) {
        return 0;
    }
    return has_labels;
}

int mupdf_pdf_page_label(fz_context *ctx, fz_document *doc, int pageno, char *buf, int size, const char **out_error) {
    if (!ctx || !doc || !buf || size <= 0) return -1;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        pdf_page_label(ctx, pdoc, pageno, buf, size);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

mupdf_page_labels *mupdf_pdf_take_page_labels(fz_context *ctx, fz_document *doc) {
    if (!ctx || !doc) return NULL;
    mupdf_page_labels *labels = NULL;
    vp_label_walk walk = { 0 };
    fz_var(labels);
    fz_var(walk);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (pdoc) {
            labels = fz_malloc_struct(ctx, mupdf_page_labels);
            labels->page_count = pdf_count_pages(ctx, pdoc);
            pdf_obj *tree = vp_label_tree(ctx, pdoc);
            if (tree) {
                vp_load_label_ranges(ctx, pdoc, tree, &walk);
                labels->tree = pdf_keep_obj(ctx, tree);
                labels->ranges = walk.ranges;
                labels->count = walk.count;
                walk.ranges = NULL;
                pdf_dict_del(ctx, pdf_dict_get(ctx, pdf_trailer(ctx, pdoc), PDF_NAME(Root)), PDF_NAME(PageLabels));
            }
        }
    } fz_catch(ctx) {
        fz_free(ctx, walk.ranges);
        if (labels) {
            pdf_drop_obj(ctx, labels->tree);
            fz_free(ctx, labels->ranges);
            fz_free(ctx, labels);
        }
        return NULL;
    }
    return labels;
}

/// Pushes the label for the run of pages that starts `consumed` pages into `range`.
static void vp_push_label_run(fz_context *ctx, pdf_document *pdoc, pdf_obj *nums, const vp_label_range *range, int consumed) {
    if (range->label && consumed == 0) {
        pdf_array_push(ctx, nums, range->label);
        return;
    }
    pdf_obj *run = range->label ? pdf_copy_dict(ctx, range->label) : pdf_new_dict(ctx, pdoc, 2);
    fz_try(ctx) {
        int start = range->label ? fz_maxi(pdf_dict_get_int(ctx, range->label, PDF_NAME(St)), 1) : range->start + 1;
        if (!range->label) pdf_dict_put(ctx, run, PDF_NAME(S), PDF_NAME(D));
        pdf_dict_put_int(ctx, run, PDF_NAME(St), start + consumed);
        pdf_array_push(ctx, nums, run);
    } fz_always(ctx) {
        pdf_drop_obj(ctx, run);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
}

/// Pages an edit added: they carry on the numbered range they're next to. Beside a page that has
/// its own label there's nothing to carry on, so they're numbered by position.
enum { VP_LABEL_ADDED = -1, VP_LABEL_POSITION = -2 };

static void vp_write_label_ranges(fz_context *ctx, pdf_document *pdoc, const mupdf_page_labels *labels, const int *page_map, int count) {
    int *assigned = NULL;
    int *owner = NULL;
    int *kept = NULL;
    fz_var(assigned);
    fz_var(owner);
    fz_var(kept);
    fz_try(ctx) {
        assigned = (int *)fz_malloc(ctx, count * sizeof(int));
        owner = (int *)fz_malloc(ctx, labels->page_count * sizeof(int));
        kept = (int *)fz_calloc(ctx, labels->count, sizeof(int));
        for (int r = 0; r < labels->count; r++) {
            for (int i = 0; i < labels->ranges[r].length; i++) owner[labels->ranges[r].start + i] = r;
        }
        for (int i = 0; i < count; i++) {
            if (page_map[i] >= 0 && page_map[i] < labels->page_count) kept[owner[page_map[i]]]++;
        }

        // Pages in numbered ranges take up the numbers in order, however they were rearranged.
        // A range keeps as many pages as survived the edit.
        int next = 0, taken = 0;
        for (int i = 0; i < count; i++) {
            int old = page_map[i];
            if (old < 0 || old >= labels->page_count) {
                assigned[i] = VP_LABEL_ADDED;
            } else if (labels->ranges[owner[old]].length == 1) {
                assigned[i] = owner[old];
            } else {
                while (labels->ranges[next].length == 1 || taken == kept[next]) {
                    next++;
                    taken = 0;
                }
                assigned[i] = next;
                taken++;
            }
        }
        for (int i = 1; i < count; i++) {
            if (assigned[i] == VP_LABEL_ADDED && assigned[i - 1] >= 0 && labels->ranges[assigned[i - 1]].length > 1) {
                assigned[i] = assigned[i - 1];
            }
        }
        for (int i = count - 2; i >= 0; i--) {
            if (assigned[i] == VP_LABEL_ADDED && assigned[i + 1] >= 0 && labels->ranges[assigned[i + 1]].length > 1) {
                assigned[i] = assigned[i + 1];
            }
        }
        for (int i = 0; i < count; i++) {
            if (assigned[i] == VP_LABEL_ADDED) assigned[i] = VP_LABEL_POSITION;
        }

        pdf_obj *root = pdf_dict_get(ctx, pdf_trailer(ctx, pdoc), PDF_NAME(Root));
        pdf_obj *tree = pdf_dict_put_dict(ctx, root, PDF_NAME(PageLabels), 1);
        pdf_obj *nums = pdf_dict_put_array(ctx, tree, PDF_NAME(Nums), 2 * labels->count);
        memset(kept, 0, labels->count * sizeof(int));
        for (int i = 0; i < count; i++) {
            int r = assigned[i];
            int starts_run = i == 0 || assigned[i - 1] != r;
            if (r == VP_LABEL_POSITION) {
                if (starts_run) {
                    pdf_array_push_int(ctx, nums, i);
                    pdf_obj *run = pdf_array_push_dict(ctx, nums, 2);
                    pdf_dict_put(ctx, run, PDF_NAME(S), PDF_NAME(D));
                    pdf_dict_put_int(ctx, run, PDF_NAME(St), i + 1);
                }
            } else {
                if (starts_run) {
                    pdf_array_push_int(ctx, nums, i);
                    vp_push_label_run(ctx, pdoc, nums, &labels->ranges[r], kept[r]);
                }
                kept[r]++;
            }
        }
    } fz_always(ctx) {
        fz_free(ctx, assigned);
        fz_free(ctx, owner);
        fz_free(ctx, kept);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
}

int mupdf_pdf_restore_page_labels(fz_context *ctx, fz_document *doc, mupdf_page_labels *labels, const int *page_map, int count, const char **out_error) {
    if (!ctx || !doc || !labels) return 0;
    int failed = 0;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        pdf_obj *root = pdf_dict_get(ctx, pdf_trailer(ctx, pdoc), PDF_NAME(Root));
        // Clears the tree MuPDF creates when a page is inserted first.
        pdf_dict_del(ctx, root, PDF_NAME(PageLabels));
        if (!page_map) {
            if (labels->tree) pdf_dict_put(ctx, root, PDF_NAME(PageLabels), labels->tree);
        } else if (labels->count > 0 && count > 0) {
            vp_write_label_ranges(ctx, pdoc, labels, page_map, count);
        }
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        failed = fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    pdf_drop_obj(ctx, labels->tree);
    fz_free(ctx, labels->ranges);
    fz_free(ctx, labels);
    return failed;
}

// MARK: - Page edits

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
        if (from_page != to_page) {
            page_obj = pdf_lookup_page_obj(ctx, pdoc, from_page);
            if (!page_obj) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to lookup page object");
            pdf_keep_obj(ctx, page_obj);
            pdf_delete_page(ctx, pdoc, from_page);
            pdf_insert_page(ctx, pdoc, to_page, page_obj);
        }
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
        pdf_write_options save_opts = default_save_options();
        pdf_save_document(ctx, dst, out_path, &save_opts);
    } fz_always(ctx) {
        if (dst) pdf_drop_document(ctx, dst);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

// MARK: - Copying pages with their annotations
//
// pdf_graft_page copies a page's contents, resources and boxes, but not its annotations (markup,
// links, form widgets) or its measurement viewports. The helpers below copy those too, for both
// a page duplicated within its document and pages imported from another one.

typedef struct {
    pdf_document *src;
    pdf_document *dst;
    int same_doc;
    pdf_graft_map *map;   // for content objects; shared across the pages so resources are copied once
    int *memo;            // source object number -> destination object number, for objects copied here
    int memo_len;
} vp_page_copy;

static int vp_is_annot_or_field(fz_context *ctx, pdf_obj *dict) {
    if (!pdf_is_dict(ctx, dict)) return 0;
    if (pdf_name_eq(ctx, pdf_dict_get(ctx, dict, PDF_NAME(Type)), PDF_NAME(Annot))) return 1;
    if (pdf_dict_get(ctx, dict, PDF_NAME(Subtype)) && pdf_dict_get(ctx, dict, PDF_NAME(Rect))) return 1;
    return pdf_dict_get(ctx, dict, PDF_NAME(FT)) || pdf_dict_get(ctx, dict, PDF_NAME(T)) || pdf_dict_get(ctx, dict, PDF_NAME(Kids));
}

static int vp_is_page(fz_context *ctx, pdf_obj *dict) {
    return pdf_name_eq(ctx, pdf_dict_get(ctx, dict, PDF_NAME(Type)), PDF_NAME(Page));
}

/// Copies `obj` (found under `key` of its parent) into the destination document.
/// Annotations and form fields reached from it are copied here, so that page references inside
/// them can be redirected: a reference to a copied page goes to its copy, and (between documents)
/// a reference to a page that wasn't copied becomes null. Within one document, a widget keeps its
/// parent field — the copy becomes another widget of the same field — and objects other than
/// annotations and their appearance streams are shared rather than copied. Between documents,
/// everything else goes through the graft map.
static pdf_obj *vp_copy_obj(fz_context *ctx, vp_page_copy *st, pdf_obj *obj, pdf_obj *key, int in_ap) {
    if (!pdf_get_bound_document(ctx, obj)) return pdf_keep_obj(ctx, obj);

    if (pdf_is_indirect(ctx, obj)) {
        int num = pdf_to_num(ctx, obj);
        if (num > 0 && num < st->memo_len && st->memo[num])
            return pdf_new_indirect(ctx, st->dst, st->memo[num], 0);

        pdf_obj *resolved = pdf_resolve_indirect(ctx, obj);
        if (vp_is_page(ctx, resolved))
            return st->same_doc ? pdf_keep_obj(ctx, obj) : PDF_NULL;

        int owned;
        if (st->same_doc) {
            int is_field_parent = key && pdf_name_eq(ctx, key, PDF_NAME(Parent)) && vp_is_annot_or_field(ctx, resolved)
                && !pdf_dict_get(ctx, resolved, PDF_NAME(Subtype));
            owned = !is_field_parent && (vp_is_annot_or_field(ctx, resolved) || (in_ap && pdf_is_stream(ctx, obj)));
            if (!owned) return pdf_keep_obj(ctx, obj);
        } else if (!vp_is_annot_or_field(ctx, resolved)) {
            return pdf_graft_mapped_object(ctx, st->map, obj);
        }

        int new_num = pdf_create_object(ctx, st->dst);
        if (num > 0 && num < st->memo_len) st->memo[num] = new_num;
        pdf_obj *copy = NULL;
        pdf_obj *ref = NULL;
        fz_buffer *buf = NULL;
        fz_var(copy);
        fz_var(ref);
        fz_var(buf);
        fz_try(ctx) {
            // A stream's own dictionary (its /Resources, say) is not part of the appearance.
            copy = vp_copy_obj(ctx, st, resolved, key, pdf_is_stream(ctx, obj) ? 0 : in_ap);
            pdf_update_object(ctx, st->dst, new_num, copy);
            ref = pdf_new_indirect(ctx, st->dst, new_num, 0);
            if (pdf_is_stream(ctx, obj)) {
                buf = pdf_load_raw_stream_number(ctx, st->src, num);
                pdf_update_stream(ctx, st->dst, ref, buf, 1);
            }
        } fz_always(ctx) {
            pdf_drop_obj(ctx, copy);
            fz_drop_buffer(ctx, buf);
        } fz_catch(ctx) {
            pdf_drop_obj(ctx, ref);
            fz_rethrow(ctx);
        }
        return ref;
    }

    if (pdf_is_dict(ctx, obj)) {
        int len = pdf_dict_len(ctx, obj);
        pdf_obj *dict = pdf_new_dict(ctx, st->dst, len);
        fz_try(ctx) {
            for (int i = 0; i < len; i++) {
                pdf_obj *k = pdf_dict_get_key(ctx, obj, i);
                int child_in_ap = in_ap || pdf_name_eq(ctx, k, PDF_NAME(AP));
                pdf_dict_put_drop(ctx, dict, k, vp_copy_obj(ctx, st, pdf_dict_get_val(ctx, obj, i), k, child_in_ap));
            }
        } fz_catch(ctx) {
            pdf_drop_obj(ctx, dict);
            fz_rethrow(ctx);
        }
        return dict;
    }

    if (pdf_is_array(ctx, obj)) {
        int len = pdf_array_len(ctx, obj);
        pdf_obj *array = pdf_new_array(ctx, st->dst, len);
        fz_try(ctx) {
            for (int i = 0; i < len; i++)
                pdf_array_push_drop(ctx, array, vp_copy_obj(ctx, st, pdf_array_get(ctx, obj, i), key, in_ap));
        } fz_catch(ctx) {
            pdf_drop_obj(ctx, array);
            fz_rethrow(ctx);
        }
        return array;
    }

    return pdf_keep_obj(ctx, obj);
}

/// Between documents, a named destination (/Dest or a GoTo action's /D) means nothing in the
/// destination document, so replace it with the explicit destination it names.
static void vp_resolve_named_dest(fz_context *ctx, vp_page_copy *st, pdf_obj *holder_src, pdf_obj *holder_dst, pdf_obj *key) {
    pdf_obj *dest = pdf_dict_get(ctx, holder_src, key);
    if (!pdf_is_name(ctx, dest) && !pdf_is_string(ctx, dest)) return;
    pdf_obj *explicit = pdf_lookup_dest(ctx, st->src, dest);
    if (pdf_is_dict(ctx, explicit)) explicit = pdf_dict_get(ctx, explicit, PDF_NAME(D));
    if (!pdf_is_array(ctx, explicit)) return;
    pdf_dict_put_drop(ctx, holder_dst, key, vp_copy_obj(ctx, st, explicit, key, 0));
}

static pdf_obj *vp_acroform_fields(fz_context *ctx, pdf_document *doc) {
    pdf_obj *root = pdf_dict_get(ctx, pdf_trailer(ctx, doc), PDF_NAME(Root));
    pdf_obj *acroform = pdf_dict_get(ctx, root, PDF_NAME(AcroForm));
    if (!acroform) {
        acroform = pdf_dict_put_dict(ctx, root, PDF_NAME(AcroForm), 2);
    }
    pdf_obj *fields = pdf_dict_get(ctx, acroform, PDF_NAME(Fields));
    if (!fields) fields = pdf_dict_put_array(ctx, acroform, PDF_NAME(Fields), 4);
    return fields;
}

static int vp_has_root_field_named(fz_context *ctx, pdf_obj *fields, const char *name) {
    int n = pdf_array_len(ctx, fields);
    for (int i = 0; i < n; i++) {
        if (strcmp(pdf_dict_get_text_string(ctx, pdf_array_get(ctx, fields, i), PDF_NAME(T)), name) == 0) return 1;
    }
    return 0;
}

/// Within one document, a duplicated widget joins its original's field, so both show the same
/// value. A widget that is itself the field (no /Parent) is first split into a field holding the
/// field entries and a widget holding the rest, so the two widgets can share that field.
static void vp_link_duplicate_widget(fz_context *ctx, pdf_document *doc, pdf_obj *orig_ref, pdf_obj *copy_ref) {
    pdf_obj *parent = pdf_dict_get(ctx, orig_ref, PDF_NAME(Parent));
    if (parent) {
        pdf_obj *kids = pdf_dict_get(ctx, parent, PDF_NAME(Kids));
        if (!kids) kids = pdf_dict_put_array(ctx, parent, PDF_NAME(Kids), 2);
        pdf_array_push(ctx, kids, copy_ref);
        return;
    }
    static const char * const field_keys[] = { "T", "TU", "TM", "FT", "Ff", "V", "DV", "Opt", "MaxLen", "TI", "I" };
    pdf_obj *field = pdf_new_dict(ctx, doc, 8);
    pdf_obj *field_ref = NULL;
    fz_var(field_ref);
    fz_try(ctx) {
        for (int i = 0; i < (int)nelem(field_keys); i++) {
            pdf_obj *val = pdf_dict_gets(ctx, orig_ref, field_keys[i]);
            if (!val) continue;
            pdf_dict_puts(ctx, field, field_keys[i], val);
            pdf_dict_dels(ctx, orig_ref, field_keys[i]);
            pdf_dict_dels(ctx, copy_ref, field_keys[i]);
        }
        pdf_obj *kids = pdf_dict_put_array(ctx, field, PDF_NAME(Kids), 2);
        pdf_array_push(ctx, kids, orig_ref);
        pdf_array_push(ctx, kids, copy_ref);
        field_ref = pdf_add_object(ctx, doc, field);
        pdf_dict_put(ctx, orig_ref, PDF_NAME(Parent), field_ref);
        pdf_dict_put(ctx, copy_ref, PDF_NAME(Parent), field_ref);

        pdf_obj *fields = vp_acroform_fields(ctx, doc);
        int at = pdf_array_find(ctx, fields, orig_ref);
        if (at >= 0) pdf_array_put(ctx, fields, at, field_ref);
        else pdf_array_push(ctx, fields, field_ref);
    } fz_always(ctx) {
        pdf_drop_obj(ctx, field);
        pdf_drop_obj(ctx, field_ref);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
}

/// Between documents, adds each copied widget's top-level field to the destination's form
/// (renamed if a field of that name is already there), and brings over the form's default
/// resources so the copied fields' fonts are found.
static void vp_register_imported_field(fz_context *ctx, vp_page_copy *st, pdf_obj *widget_copy) {
    pdf_obj *top = widget_copy;
    for (pdf_obj *p = pdf_dict_get(ctx, top, PDF_NAME(Parent)); pdf_is_dict(ctx, p); p = pdf_dict_get(ctx, p, PDF_NAME(Parent)))
        top = p;
    if (!pdf_dict_get(ctx, top, PDF_NAME(FT)) && !pdf_dict_get(ctx, top, PDF_NAME(T)) && !pdf_dict_get(ctx, top, PDF_NAME(Kids)))
        return;
    pdf_obj *fields = vp_acroform_fields(ctx, st->dst);
    if (pdf_array_find(ctx, fields, top) >= 0) return;

    const char *name = pdf_dict_get_text_string(ctx, top, PDF_NAME(T));
    if (name[0] && vp_has_root_field_named(ctx, fields, name)) {
        char renamed[512];
        for (int n = 2; n < 10000; n++) {
            snprintf(renamed, sizeof renamed, "%s_%d", name, n);
            if (!vp_has_root_field_named(ctx, fields, renamed)) break;
        }
        pdf_dict_put_text_string(ctx, top, PDF_NAME(T), renamed);
    }
    pdf_array_push(ctx, fields, top);

    pdf_obj *src_form = pdf_dict_getp(ctx, pdf_trailer(ctx, st->src), "Root/AcroForm");
    pdf_obj *dst_form = pdf_dict_getp(ctx, pdf_trailer(ctx, st->dst), "Root/AcroForm");
    pdf_obj *src_fonts = pdf_dict_getp(ctx, src_form, "DR/Font");
    if (pdf_is_dict(ctx, src_fonts)) {
        pdf_obj *dr = pdf_dict_get(ctx, dst_form, PDF_NAME(DR));
        if (!dr) dr = pdf_dict_put_dict(ctx, dst_form, PDF_NAME(DR), 1);
        pdf_obj *dst_fonts = pdf_dict_get(ctx, dr, PDF_NAME(Font));
        if (!dst_fonts) dst_fonts = pdf_dict_put_dict(ctx, dr, PDF_NAME(Font), 4);
        int n = pdf_dict_len(ctx, src_fonts);
        for (int i = 0; i < n; i++) {
            pdf_obj *k = pdf_dict_get_key(ctx, src_fonts, i);
            if (!pdf_dict_get(ctx, dst_fonts, k))
                pdf_dict_put_drop(ctx, dst_fonts, k, pdf_graft_mapped_object(ctx, st->map, pdf_dict_get_val(ctx, src_fonts, i)));
        }
    }
    if (!pdf_dict_get(ctx, dst_form, PDF_NAME(DA)) && pdf_dict_get(ctx, src_form, PDF_NAME(DA)))
        pdf_dict_put(ctx, dst_form, PDF_NAME(DA), pdf_dict_get(ctx, src_form, PDF_NAME(DA)));
}

/// Copies the annotations of source page `src_page_obj` onto destination page `dst_page_ref`.
static void vp_copy_page_annots(fz_context *ctx, vp_page_copy *st, pdf_obj *src_page_obj, pdf_obj *dst_page_ref) {
    pdf_obj *annots = pdf_dict_get(ctx, src_page_obj, PDF_NAME(Annots));
    int n = pdf_array_len(ctx, annots);
    if (n == 0) return;
    pdf_obj *new_annots = pdf_dict_put_array(ctx, dst_page_ref, PDF_NAME(Annots), n);
    for (int i = 0; i < n; i++) {
        pdf_obj *annot = pdf_array_get(ctx, annots, i);
        if (!pdf_is_dict(ctx, annot)) continue;
        // Popups are recreated by viewers as needed; copying them would need their parents remapped.
        if (pdf_name_eq(ctx, pdf_dict_get(ctx, annot, PDF_NAME(Subtype)), PDF_NAME(Popup))) continue;

        pdf_obj *copy = vp_copy_obj(ctx, st, annot, NULL, 0);
        fz_try(ctx) {
            pdf_dict_del(ctx, copy, PDF_NAME(Popup));
            pdf_dict_put(ctx, copy, PDF_NAME(P), dst_page_ref);
            if (!st->same_doc) {
                vp_resolve_named_dest(ctx, st, annot, copy, PDF_NAME(Dest));
                pdf_obj *action = pdf_dict_get(ctx, annot, PDF_NAME(A));
                pdf_obj *action_copy = pdf_dict_get(ctx, copy, PDF_NAME(A));
                if (pdf_name_eq(ctx, pdf_dict_get(ctx, action, PDF_NAME(S)), PDF_NAME(GoTo)) && pdf_is_dict(ctx, action_copy))
                    vp_resolve_named_dest(ctx, st, action, action_copy, PDF_NAME(D));
            }
            if (pdf_name_eq(ctx, pdf_dict_get(ctx, annot, PDF_NAME(Subtype)), PDF_NAME(Widget))) {
                if (st->same_doc) vp_link_duplicate_widget(ctx, st->dst, annot, copy);
                else vp_register_imported_field(ctx, st, copy);
            }
            pdf_array_push(ctx, new_annots, copy);
        } fz_always(ctx) {
            pdf_drop_obj(ctx, copy);
        } fz_catch(ctx) {
            fz_rethrow(ctx);
        }
    }
}

/// Inserts copies of `src_pages` of `src` (which may be `dst` itself) into `dst` at `insert_slot`,
/// with their annotations and the page entries pdf_graft_page leaves out.
static void vp_copy_pages(fz_context *ctx, pdf_document *dst, pdf_document *src, const int *src_pages, int count, int insert_slot) {
    static const char * const extra_keys[] = { "VP", "Group", "Tabs" };
    vp_page_copy st = { src, dst, src == dst, NULL, NULL, 0 };
    fz_var(st.map);
    fz_var(st.memo);
    fz_try(ctx) {
        st.map = pdf_new_graft_map(ctx, dst);
        for (int i = 0; i < count; i++) {
            pdf_graft_mapped_page(ctx, st.map, insert_slot + i, src, src_pages[i]);
            pdf_obj *src_page = pdf_lookup_page_obj(ctx, src, src_pages[i]);
            pdf_obj *dst_page = pdf_lookup_page_obj(ctx, dst, insert_slot + i);
            for (int k = 0; k < (int)nelem(extra_keys); k++) {
                pdf_obj *val = pdf_dict_gets(ctx, src_page, extra_keys[k]);
                if (val) pdf_dict_puts_drop(ctx, dst_page, extra_keys[k], pdf_graft_mapped_object(ctx, st.map, val));
            }
        }

        st.memo_len = pdf_xref_len(ctx, src);
        st.memo = fz_calloc(ctx, st.memo_len, sizeof(int));
        // Between documents, references to a copied page (from links, say) go to its copy.
        if (!st.same_doc) {
            for (int i = 0; i < count; i++) {
                int src_num = pdf_to_num(ctx, pdf_lookup_page_obj(ctx, src, src_pages[i]));
                int dst_num = pdf_to_num(ctx, pdf_lookup_page_obj(ctx, dst, insert_slot + i));
                if (src_num > 0 && src_num < st.memo_len) st.memo[src_num] = dst_num;
            }
        }
        for (int i = 0; i < count; i++) {
            pdf_obj *dst_page = pdf_lookup_page_obj(ctx, dst, insert_slot + i);
            pdf_obj *dst_ref = pdf_new_indirect(ctx, dst, pdf_to_num(ctx, dst_page), 0);
            fz_try(ctx)
                vp_copy_page_annots(ctx, &st, pdf_lookup_page_obj(ctx, src, src_pages[i]), dst_ref);
            fz_always(ctx)
                pdf_drop_obj(ctx, dst_ref);
            fz_catch(ctx)
                fz_rethrow(ctx);
        }
    } fz_always(ctx) {
        fz_free(ctx, st.memo);
        pdf_drop_graft_map(ctx, st.map);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
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
        vp_copy_pages(ctx, pdoc, pdoc, page_indices, count, insert_slot);
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
    int *src_pages = NULL;
    fz_var(src_doc);
    fz_var(src_pages);
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
        src_pages = fz_malloc(ctx, src_count * sizeof(int));
        for (int i = 0; i < src_count; i++) src_pages[i] = i;
        vp_copy_pages(ctx, dst_pdoc, src_pdoc, src_pages, src_count, insert_slot);
        if (out_imported_count) *out_imported_count = src_count;
    } fz_always(ctx) {
        fz_free(ctx, src_pages);
        if (src_doc) fz_drop_document(ctx, src_doc);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_pdf_insert_blank_page(fz_context *ctx, fz_document *doc, int insert_slot, float width, float height, const char **out_error) {
    if (!ctx || !doc) return -1;
    pdf_obj *page_obj = NULL;
    pdf_obj *resources = NULL;
    fz_buffer *contents = NULL;
    fz_device *dev = NULL;
    fz_var(page_obj);
    fz_var(resources);
    fz_var(contents);
    fz_var(dev);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Target document is not a PDF");
        int total_pages = pdf_count_pages(ctx, pdoc);
        if (insert_slot < 0 || insert_slot > total_pages) {
            fz_throw(ctx, FZ_ERROR_GENERIC, "Insert slot out of bounds");
        }

        float w = width;
        float h = height;
        if (w <= 0.0f || h <= 0.0f) {
            int ref_page = (insert_slot > 0) ? (insert_slot - 1) : 0;
            if (total_pages > 0 && ref_page >= 0 && ref_page < total_pages) {
                pdf_obj *ref_page_obj = pdf_lookup_page_obj(ctx, pdoc, ref_page);
                if (ref_page_obj) {
                    pdf_obj *media_obj = pdf_dict_get_inheritable(ctx, ref_page_obj, PDF_NAME(MediaBox));
                    if (media_obj) {
                        fz_rect r = pdf_to_rect(ctx, media_obj);
                        w = fabsf(r.x1 - r.x0);
                        h = fabsf(r.y1 - r.y0);
                    }
                }
            }
        }
        if (w <= 0.0f || h <= 0.0f) {
            w = 612.0f;
            h = 792.0f;
        }

        fz_rect mediabox = fz_make_rect(0, 0, w, h);
        dev = pdf_page_write(ctx, pdoc, mediabox, &resources, &contents);
        fz_close_device(ctx, dev);
        fz_drop_device(ctx, dev);
        dev = NULL;

        page_obj = pdf_add_page(ctx, pdoc, mediabox, 0, resources, contents);
        pdf_insert_page(ctx, pdoc, insert_slot, page_obj);
    } fz_always(ctx) {
        if (dev) fz_drop_device(ctx, dev);
        if (page_obj) pdf_drop_obj(ctx, page_obj);
        if (resources) pdf_drop_obj(ctx, resources);
        if (contents) fz_drop_buffer(ctx, contents);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

// Store & Memory Management
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

/* Whether a widget's activation action (/A /S) is ResetForm. */
int mupdf_page_widget_is_reset_button(fz_context *ctx, fz_document *doc, int pageno, int widget_index,
                                      int *out_is_reset, const char **out_error) {
    if (!ctx || !doc || !out_is_reset) return -1;
    *out_is_reset = 0;
    pdf_page *ppage = NULL;
    fz_var(ppage);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *w = pdf_first_widget(ctx, ppage);
        for (int idx = 0; w && idx < widget_index; idx++) {
            w = pdf_next_widget(ctx, w);
        }
        if (w) {
            pdf_obj *action = pdf_dict_get(ctx, pdf_annot_obj(ctx, w), PDF_NAME(A));
            *out_is_reset = pdf_name_eq(ctx, pdf_dict_get(ctx, action, PDF_NAME(S)), PDF_NAME(ResetForm));
        }
    }
    fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    }
    fz_catch(ctx) {
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
            out_meta->pdf_version = pdf_version(ctx, pdoc);
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
    fz_page *plain_page = NULL;
    fz_var(plain_page);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) {
            plain_page = fz_load_page(ctx, doc, pageno);
            fz_rect r = fz_bound_page(ctx, plain_page);
            out_boxes->media_box = r;
            out_boxes->crop_box = r;
            out_boxes->has_crop_box = 1;
        } else {
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
        }
    } fz_always(ctx) {
        if (plain_page) fz_drop_page(ctx, plain_page);
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
    fz_var(entries);
    fz_var(count);
    fz_var(capacity);

    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        int num_pages = pdoc ? pdf_count_pages(ctx, pdoc) : 0;
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

// SVG Page Export
int mupdf_page_to_svg(fz_context *ctx, fz_document *doc, int pageno, int text_as_path, char **out_svg, const char **out_error) {
    if (!ctx || !doc || !out_svg) return -1;
    *out_svg = NULL;
    fz_page *page = NULL;
    fz_device *dev = NULL;
    fz_output *out = NULL;
    fz_buffer *buf = NULL;

    fz_var(page);
    fz_var(dev);
    fz_var(out);
    fz_var(buf);

    fz_try(ctx) {
        page = fz_load_page(ctx, doc, pageno);
        fz_rect bounds = fz_bound_page(ctx, page);
        float w = bounds.x1 - bounds.x0;
        float h = bounds.y1 - bounds.y0;

        buf = fz_new_buffer(ctx, 4096);
        out = fz_new_output_with_buffer(ctx, buf);

        int text_fmt = text_as_path ? FZ_SVG_TEXT_AS_PATH : FZ_SVG_TEXT_AS_TEXT;
        dev = fz_new_svg_device(ctx, out, w, h, text_fmt, 1);

        fz_matrix ctm = fz_translate(-bounds.x0, -bounds.y0);
        fz_run_page(ctx, page, dev, ctm, NULL);

        fz_close_device(ctx, dev);
        fz_drop_device(ctx, dev);
        dev = NULL;

        fz_close_output(ctx, out);
        fz_drop_output(ctx, out);
        out = NULL;

        unsigned char *data = NULL;
        size_t len = fz_buffer_storage(ctx, buf, &data);
        char *str = malloc(len + 1);
        if (str) {
            if (data && len > 0) {
                memcpy(str, data, len);
            }
            str[len] = '\0';
            *out_svg = str;
        }
    } fz_always(ctx) {
        if (dev) {
            fz_try(ctx) { fz_close_device(ctx, dev); } fz_catch(ctx) {}
            fz_drop_device(ctx, dev);
        }
        if (out) {
            fz_try(ctx) { fz_close_output(ctx, out); } fz_catch(ctx) {}
            fz_drop_output(ctx, out);
        }
        if (buf) fz_drop_buffer(ctx, buf);
        if (page) fz_drop_page(ctx, page);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

int mupdf_page_export_svg(fz_context *ctx, fz_document *doc, int pageno, const char *out_path, int text_as_path, const char **out_error) {
    if (!ctx || !doc || !out_path) return -1;
    fz_page *page = NULL;
    fz_device *dev = NULL;
    fz_output *out = NULL;

    fz_var(page);
    fz_var(dev);
    fz_var(out);

    fz_try(ctx) {
        page = fz_load_page(ctx, doc, pageno);
        fz_rect bounds = fz_bound_page(ctx, page);
        float w = bounds.x1 - bounds.x0;
        float h = bounds.y1 - bounds.y0;

        out = fz_new_output_with_path(ctx, out_path, 0);
        int text_fmt = text_as_path ? FZ_SVG_TEXT_AS_PATH : FZ_SVG_TEXT_AS_TEXT;
        dev = fz_new_svg_device(ctx, out, w, h, text_fmt, 1);

        fz_matrix ctm = fz_translate(-bounds.x0, -bounds.y0);
        fz_run_page(ctx, page, dev, ctm, NULL);

        fz_close_device(ctx, dev);
        fz_drop_device(ctx, dev);
        dev = NULL;

        fz_close_output(ctx, out);
        fz_drop_output(ctx, out);
        out = NULL;
    } fz_always(ctx) {
        if (dev) {
            fz_try(ctx) { fz_close_device(ctx, dev); } fz_catch(ctx) {}
            fz_drop_device(ctx, dev);
        }
        if (out) {
            fz_try(ctx) { fz_close_output(ctx, out); } fz_catch(ctx) {}
            fz_drop_output(ctx, out);
        }
        if (page) fz_drop_page(ctx, page);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return fz_caught(ctx) ? fz_caught(ctx) : -1;
    }
    return 0;
}

// Applies a reading theme (1 = dark, 2 = sepia) in place to an RGB(A) buffer.
int mupdf_apply_color_appearance(fz_context *ctx, unsigned char *samples, int width, int height, int stride, int n, int appearance_mode) {
    if (!ctx || !samples || width <= 0 || height <= 0 || stride <= 0) return -1;
    if (appearance_mode == 0) return 0;
    fz_pixmap *pix = NULL;
    fz_var(pix);
    fz_try(ctx) {
        int alpha = (n == 4) ? 1 : 0;
        pix = fz_new_pixmap_with_data(ctx, fz_device_rgb(ctx), width, height, NULL, alpha, stride, samples);
        if (appearance_mode == 1) {
            fz_invert_pixmap_luminance(ctx, pix);
        } else if (appearance_mode == 2) {
            fz_tint_pixmap(ctx, pix, 0x3A2E24, 0xF6EED9);
        }
    } fz_always(ctx) {
        if (pix) fz_drop_pixmap(ctx, pix);
    } fz_catch(ctx) {
        return -1;
    }
    return 0;
}

// Layers (Optional Content Groups)

int mupdf_pdf_count_layers(fz_context *ctx, fz_document *doc) {
    if (!ctx || !doc) return 0;
    int count = 0;
    fz_var(count);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (pdoc) count = pdf_count_layers(ctx, pdoc);
    } fz_catch(ctx) {
        count = 0;
    }
    return count;
}

int mupdf_pdf_get_layer_states(fz_context *ctx, fz_document *doc, int *out_states, int count) {
    if (!ctx || !doc || (!out_states && count > 0)) return -1;
    int mismatch = 0;
    fz_var(mismatch);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        mismatch = !pdoc || pdf_count_layers(ctx, pdoc) != count;
        if (!mismatch) {
            for (int i = 0; i < count; i++)
                out_states[i] = pdf_layer_is_enabled(ctx, pdoc, i) ? 1 : 0;
        }
    } fz_catch(ctx) {
        return -1;
    }
    return mismatch ? -1 : 0;
}

int mupdf_pdf_set_layer_states(fz_context *ctx, fz_document *doc, const int *states, int count) {
    if (!ctx || !doc || (!states && count > 0)) return -1;
    /* A copy that hasn't been opened again since a layer was added has fewer: left alone. */
    int mismatch = 0;
    fz_var(mismatch);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        mismatch = !pdoc || pdf_count_layers(ctx, pdoc) != count;
        if (!mismatch) {
            for (int i = 0; i < count; i++)
                pdf_enable_layer(ctx, pdoc, i, states[i] != 0);
        }
    } fz_catch(ctx) {
        return -1;
    }
    return mismatch ? -1 : 0;
}

int mupdf_pdf_layer_name(fz_context *ctx, fz_document *doc, int layer, char *buf, int size) {
    if (!ctx || !doc || !buf || size <= 0) return -1;
    buf[0] = 0;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "not a PDF");
        const char *name = pdf_layer_name(ctx, pdoc, layer);
        if (name) fz_strlcpy(buf, name, size);
    } fz_catch(ctx) {
        return -1;
    }
    return 0;
}

/* MuPDF numbers layers in descending order of object number (ocgcmp in pdf-layer.c), so the
 * layer at a position in /OCGs is numbered by how many layers have higher object numbers.
 * LayerTests checks this still holds. */
int mupdf_pdf_layer_at_position(fz_context *ctx, fz_document *doc, int position) {
    if (!ctx || !doc || position < 0) return -1;
    int layer = -1;
    fz_var(layer);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (pdoc) {
            pdf_obj *root = pdf_dict_get(ctx, pdf_trailer(ctx, pdoc), PDF_NAME(Root));
            pdf_obj *ocgs = pdf_dict_getp(ctx, root, "OCProperties/OCGs");
            int len = pdf_array_len(ctx, ocgs);
            if (position < len && len == pdf_count_layers(ctx, pdoc)) {
                int num = pdf_to_num(ctx, pdf_array_get(ctx, ocgs, position));
                int higher = 0, same = 0;
                for (int i = 0; i < len; i++) {
                    int other = pdf_to_num(ctx, pdf_array_get(ctx, ocgs, i));
                    if (other > num) higher++;
                    else if (other == num) same++;
                }
                /* A layer listed twice can't be told apart from its copy. */
                if (num > 0 && same == 1) layer = higher;
            }
        }
    } fz_catch(ctx) {
        layer = -1;
    }
    return layer;
}

static int vp_descending(const void *a, const void *b) {
    return *(const int *)b - *(const int *)a;
}

/* The layers' object numbers, as MuPDF numbers the layers (see mupdf_pdf_layer_at_position).
 * Returns how many, with `*out` to free; 0 and NULL if they can't be found. */
static int vp_layer_numbers(fz_context *ctx, pdf_document *pdoc, int **out) {
    *out = NULL;
    pdf_obj *ocgs = pdf_dict_getp(ctx, pdf_trailer(ctx, pdoc), "Root/OCProperties/OCGs");
    int len = pdf_array_len(ctx, ocgs);
    if (len == 0 || len != pdf_count_layers(ctx, pdoc)) return 0;
    int *nums = fz_malloc(ctx, len * sizeof *nums);
    for (int i = 0; i < len; i++) nums[i] = pdf_to_num(ctx, pdf_array_get(ctx, ocgs, i));
    qsort(nums, len, sizeof *nums, vp_descending);
    *out = nums;
    return len;
}

int mupdf_pdf_layer_object_number(fz_context *ctx, fz_document *doc, int layer) {
    if (!ctx || !doc || layer < 0) return 0;
    int num = 0;
    int *nums = NULL;
    fz_var(num);
    fz_var(nums);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        int n = pdoc ? vp_layer_numbers(ctx, pdoc, &nums) : 0;
        if (layer < n) num = nums[layer];
    } fz_always(ctx) {
        fz_free(ctx, nums);
    } fz_catch(ctx) {
        num = 0;
    }
    return num;
}

/* MuPDF reads the layers once; after the list changes, read them again, then show the ones that
 * were there before as they were (`nums` and `states`, `n` of each), and new ones as the document's
 * default configuration says. */
static void vp_reload_layers(fz_context *ctx, pdf_document *pdoc, const int *nums, const int *states, int n) {
    int *new_nums = NULL;
    fz_var(new_nums);
    pdf_drop_ocg(ctx, pdoc);
    pdoc->ocg = NULL;
    fz_try(ctx) {
        int m = vp_layer_numbers(ctx, pdoc, &new_nums);
        for (int j = 0; j < m; j++) {
            for (int i = 0; i < n; i++) {
                if (nums[i] == new_nums[j]) { pdf_enable_layer(ctx, pdoc, j, states[i]); break; }
            }
        }
    } fz_always(ctx) {
        fz_free(ctx, new_nums);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
}

/* How the layers are shown now: their numbers and states, `*out_n` of each, both to free. */
static void vp_layer_states(fz_context *ctx, pdf_document *pdoc, int **out_nums, int **out_states, int *out_n) {
    *out_states = NULL;
    *out_n = vp_layer_numbers(ctx, pdoc, out_nums);
    if (*out_n > 0) {
        *out_states = fz_malloc(ctx, *out_n * sizeof **out_states);
        for (int i = 0; i < *out_n; i++) (*out_states)[i] = pdf_layer_is_enabled(ctx, pdoc, i);
    }
}

int mupdf_pdf_add_layer(fz_context *ctx, fz_document *doc, const char *name, int *out_object_number, const char **out_error) {
    if (!ctx || !doc || !name || !out_object_number) return -1;
    *out_object_number = 0;
    int *old_nums = NULL, *states = NULL, *new_nums = NULL;
    pdf_obj *ocg = NULL;
    fz_var(old_nums);
    fz_var(states);
    fz_var(new_nums);
    fz_var(ocg);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        /* How the layers are shown now, by object number, to show them the same way after. */
        int n = 0;
        vp_layer_states(ctx, pdoc, &old_nums, &states, &n);
        pdf_obj *root = pdf_dict_get(ctx, pdf_trailer(ctx, pdoc), PDF_NAME(Root));
        pdf_obj *ocprops = pdf_dict_get(ctx, root, PDF_NAME(OCProperties));
        if (!pdf_is_dict(ctx, ocprops)) ocprops = pdf_dict_put_dict(ctx, root, PDF_NAME(OCProperties), 2);
        pdf_obj *ocgs = pdf_dict_get(ctx, ocprops, PDF_NAME(OCGs));
        if (!pdf_is_array(ctx, ocgs)) ocgs = pdf_dict_put_array(ctx, ocprops, PDF_NAME(OCGs), 1);
        pdf_obj *config = pdf_dict_get(ctx, ocprops, PDF_NAME(D));
        if (!pdf_is_dict(ctx, config)) config = pdf_dict_put_dict(ctx, ocprops, PDF_NAME(D), 2);

        ocg = pdf_add_new_dict(ctx, pdoc, 2);
        pdf_dict_put(ctx, ocg, PDF_NAME(Type), PDF_NAME(OCG));
        pdf_dict_put_text_string(ctx, ocg, PDF_NAME(Name), name);
        pdf_array_push(ctx, ocgs, ocg);
        /* Listed after the others, or as the only one. A document whose layers aren't in an
         * /Order lists every layer, this one included. */
        pdf_obj *order = pdf_dict_get(ctx, config, PDF_NAME(Order));
        if (pdf_is_array(ctx, order)) pdf_array_push(ctx, order, ocg);
        else if (n == 0) pdf_array_push(ctx, pdf_dict_put_array(ctx, config, PDF_NAME(Order), 1), ocg);

        vp_reload_layers(ctx, pdoc, old_nums, states, n);
        *out_object_number = pdf_to_num(ctx, ocg);
    } fz_always(ctx) {
        pdf_drop_obj(ctx, ocg);
        fz_free(ctx, old_nums);
        fz_free(ctx, new_nums);
        fz_free(ctx, states);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

static int vp_is_layer(fz_context *ctx, pdf_document *pdoc, int num) {
    pdf_obj *ocgs = pdf_dict_getp(ctx, pdf_trailer(ctx, pdoc), "Root/OCProperties/OCGs");
    int n = pdf_array_len(ctx, ocgs);
    for (int i = 0; i < n; i++) if (pdf_to_num(ctx, pdf_array_get(ctx, ocgs, i)) == num) return 1;
    return 0;
}

int mupdf_pdf_annot_layer(fz_context *ctx, fz_document *doc, int pageno, int objnum, int *out_layer, const char **out_error) {
    if (!ctx || !doc || !out_layer) return -1;
    *out_layer = 0;
    pdf_page *ppage = NULL;
    fz_var(ppage);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *annot = find_annot_by_objnum(ctx, ppage, objnum);
        if (annot) *out_layer = vp_oc_layer(ctx, pdf_annot_obj(ctx, annot));
    } fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_pdf_set_annot_layer(fz_context *ctx, fz_document *doc, int pageno, int objnum, int layer, const char **out_error) {
    if (!ctx || !doc) return -1;
    pdf_page *ppage = NULL;
    fz_var(ppage);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        if (layer > 0 && !vp_is_layer(ctx, pdoc, layer)) fz_throw(ctx, FZ_ERROR_ARGUMENT, "No such layer");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        pdf_annot *annot = find_annot_by_objnum(ctx, ppage, objnum);
        if (!annot) fz_throw(ctx, FZ_ERROR_ARGUMENT, "No such annotation");
        pdf_obj *obj = pdf_annot_obj(ctx, annot);
        if (layer > 0) pdf_dict_put_drop(ctx, obj, PDF_NAME(OC), pdf_new_indirect(ctx, pdoc, layer, 0));
        else pdf_dict_del(ctx, obj, PDF_NAME(OC));
    } fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_pdf_count_layer_ui(fz_context *ctx, fz_document *doc) {
    if (!ctx || !doc) return 0;
    int count = 0;
    fz_var(count);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (pdoc && pdf_count_layers(ctx, pdoc) > 0) count = pdf_count_layer_config_ui(ctx, pdoc);
    } fz_catch(ctx) {
        count = 0;
    }
    return count;
}

/* Walks the default configuration's /Order as populate_ui in pdf-layer.c does, giving each entry's
 * layer object number (0 for a heading), so they line up with pdf_layer_config_ui_info's. */
static int vp_order_numbers(fz_context *ctx, pdf_obj *ocgs, pdf_obj *order, int *out, int capacity, int fill, pdf_cycle_list *cycle_up) {
    int len = pdf_array_len(ctx, order);
    for (int i = 0; i < len; i++) {
        pdf_obj *o = pdf_array_get(ctx, order, i);
        if (pdf_is_array(ctx, o)) {
            pdf_cycle_list cycle;
            if (pdf_cycle(ctx, &cycle, cycle_up, o)) continue;
            fill = vp_order_numbers(ctx, ocgs, o, out, capacity, fill, &cycle);
            continue;
        }
        int num = 0;
        if (!pdf_is_string(ctx, o)) {
            num = pdf_to_num(ctx, o);
            int listed = 0;
            int n = pdf_array_len(ctx, ocgs);
            for (int j = 0; j < n && !listed; j++) listed = num > 0 && pdf_to_num(ctx, pdf_array_get(ctx, ocgs, j)) == num;
            if (!listed) continue; /* MuPDF leaves out a layer that isn't in /OCGs */
        }
        if (fill < capacity) out[fill] = num;
        fill++;
    }
    return fill;
}

int mupdf_pdf_layer_ui_entry(fz_context *ctx, fz_document *doc, int index, mupdf_layer_ui_entry *out, char *text_buf, int text_size) {
    if (!ctx || !doc || !out) return -1;
    memset(out, 0, sizeof *out);
    if (text_buf && text_size > 0) text_buf[0] = 0;
    int *numbers = NULL;
    fz_var(numbers);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "not a PDF");
        pdf_layer_config_ui info;
        pdf_layer_config_ui_info(ctx, pdoc, index, &info);
        int count = pdf_count_layer_config_ui(ctx, pdoc);
        pdf_obj *ocprops = pdf_dict_getp(ctx, pdf_trailer(ctx, pdoc), "Root/OCProperties");
        numbers = fz_calloc(ctx, count > 0 ? count : 1, sizeof *numbers);
        int walked = vp_order_numbers(ctx, pdf_dict_get(ctx, ocprops, PDF_NAME(OCGs)), pdf_dict_getp(ctx, ocprops, "D/Order"), numbers, count, 0, NULL);
        /* Only if the walk agrees with MuPDF's list; otherwise the entry can't be put to use. */
        if (walked == count && index >= 0 && index < count && (numbers[index] == 0) == (info.type == PDF_LAYER_UI_LABEL))
            out->object_number = numbers[index];
        out->depth = info.depth;
        out->type = (int)info.type;
        out->selected = info.selected;
        out->locked = info.locked;
        if (text_buf && text_size > 0 && info.text) fz_strlcpy(text_buf, info.text, text_size);
    } fz_always(ctx) {
        fz_free(ctx, numbers);
    } fz_catch(ctx) {
        return -1;
    }
    return 0;
}

int mupdf_pdf_toggle_layer_ui(fz_context *ctx, fz_document *doc, int index, const char **out_error) {
    if (!ctx || !doc) return -1;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "not a PDF");
        pdf_toggle_layer_config_ui(ctx, pdoc, index);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_pdf_rename_layer(fz_context *ctx, fz_document *doc, int layer, const char *name, const char **out_error) {
    if (!ctx || !doc || !name) return -1;
    int *nums = NULL, *states = NULL;
    fz_var(nums);
    fz_var(states);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc || !vp_is_layer(ctx, pdoc, layer)) fz_throw(ctx, FZ_ERROR_ARGUMENT, "No such layer");
        int n = 0;
        vp_layer_states(ctx, pdoc, &nums, &states, &n);
        pdf_obj *ocg = pdf_new_indirect(ctx, pdoc, layer, 0);
        pdf_dict_put_text_string(ctx, ocg, PDF_NAME(Name), name);
        pdf_drop_obj(ctx, ocg);
        /* MuPDF's list of layers holds on to the old name. */
        vp_reload_layers(ctx, pdoc, nums, states, n);
    } fz_always(ctx) {
        fz_free(ctx, nums);
        fz_free(ctx, states);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

/* Whether `obj`, or anything directly inside it (not following references), refers to object
 * `num`. `skip` is a key left out at the top, or NULL. */
static int vp_refers_to(fz_context *ctx, pdf_obj *obj, int num, pdf_obj *skip, int depth) {
    if (depth > 32) return 0;
    if (pdf_is_indirect(ctx, obj)) return pdf_to_num(ctx, obj) == num;
    if (pdf_is_array(ctx, obj)) {
        int n = pdf_array_len(ctx, obj);
        for (int i = 0; i < n; i++) if (vp_refers_to(ctx, pdf_array_get(ctx, obj, i), num, NULL, depth + 1)) return 1;
    } else if (pdf_is_dict(ctx, obj)) {
        int n = pdf_dict_len(ctx, obj);
        for (int i = 0; i < n; i++) {
            if (skip && pdf_name_eq(ctx, pdf_dict_get_key(ctx, obj, i), skip)) continue;
            if (vp_refers_to(ctx, pdf_dict_get_val(ctx, obj, i), num, NULL, depth + 1)) return 1;
        }
    }
    return 0;
}

/* The objects that make up the list of layers itself, which refer to every layer. */
static int vp_is_layer_list_object(fz_context *ctx, pdf_document *pdoc, int num) {
    pdf_obj *ocprops = pdf_dict_getp(ctx, pdf_trailer(ctx, pdoc), "Root/OCProperties");
    if (pdf_is_indirect(ctx, ocprops) && pdf_to_num(ctx, ocprops) == num) return 1;
    /* Its arrays and configurations, where they're objects of their own. */
    pdf_obj *stack[64];
    int top = 0;
    if (pdf_is_dict(ctx, ocprops)) stack[top++] = ocprops;
    while (top > 0) {
        pdf_obj *o = stack[--top];
        int n = pdf_is_dict(ctx, o) ? pdf_dict_len(ctx, o) : pdf_array_len(ctx, o);
        for (int i = 0; i < n; i++) {
            pdf_obj *v = pdf_is_dict(ctx, o) ? pdf_dict_get_val(ctx, o, i) : pdf_array_get(ctx, o, i);
            if (!pdf_is_array(ctx, v) && !pdf_is_dict(ctx, v)) continue;
            /* A layer, or a group of them used by content, isn't part of the list. */
            pdf_obj *type = pdf_dict_get(ctx, v, PDF_NAME(Type));
            if (pdf_name_eq(ctx, type, PDF_NAME(OCG)) || pdf_name_eq(ctx, type, PDF_NAME(OCMD))) continue;
            if (pdf_is_indirect(ctx, v) && pdf_to_num(ctx, v) == num) return 1;
            if (top < 64) stack[top++] = v;
        }
    }
    return 0;
}

static int vp_is_annotation(fz_context *ctx, pdf_obj *obj) {
    return pdf_is_dict(ctx, obj) &&
        (pdf_name_eq(ctx, pdf_dict_get(ctx, obj, PDF_NAME(Type)), PDF_NAME(Annot)) ||
         (pdf_dict_get(ctx, obj, PDF_NAME(Subtype)) && pdf_dict_get(ctx, obj, PDF_NAME(Rect)) && !pdf_dict_get(ctx, obj, PDF_NAME(Resources))));
}

int mupdf_pdf_layer_holds_content(fz_context *ctx, fz_document *doc, int layer) {
    if (!ctx || !doc || layer <= 0) return 1;
    int holds = 0;
    fz_var(holds);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        pdf_obj *root = pdf_dict_get(ctx, pdf_trailer(ctx, pdoc), PDF_NAME(Root));
        int root_num = pdf_to_num(ctx, root);
        int len = pdf_xref_len(ctx, pdoc);
        for (int i = 1; i < len && !holds; i++) {
            if (i == layer) continue;
            pdf_obj *obj = NULL;
            fz_try(ctx) {
                obj = pdf_load_object(ctx, pdoc, i);
            } fz_catch(ctx) {
                obj = NULL;
            }
            if (!obj) continue;
            /* The catalog holds the list of layers, which refers to every layer. */
            pdf_obj *skip = i == root_num ? PDF_NAME(OCProperties) : NULL;
            if (vp_refers_to(ctx, obj, layer, skip, 0) && !vp_is_annotation(ctx, obj) && !vp_is_layer_list_object(ctx, pdoc, i))
                holds = 1;
            pdf_drop_obj(ctx, obj);
        }
    } fz_catch(ctx) {
        holds = 1;
    }
    return holds;
}

int mupdf_pdf_annots_on_layer(fz_context *ctx, fz_document *doc, int layer, int *out, int capacity) {
    if (!ctx || !doc || layer <= 0) return -1;
    int count = 0;
    pdf_page *ppage = NULL;
    fz_var(count);
    fz_var(ppage);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        int pages = pdf_count_pages(ctx, pdoc);
        for (int p = 0; p < pages; p++) {
            ppage = pdf_load_page(ctx, pdoc, p);
            for (pdf_annot *a = pdf_first_annot(ctx, ppage); a; a = pdf_next_annot(ctx, a)) {
                if (vp_oc_layer(ctx, pdf_annot_obj(ctx, a)) != layer) continue;
                if (out && count < capacity) {
                    out[2 * count] = p;
                    out[2 * count + 1] = pdf_to_num(ctx, pdf_annot_obj(ctx, a));
                }
                count++;
            }
            pdf_drop_page(ctx, ppage);
            ppage = NULL;
        }
    } fz_always(ctx) {
        if (ppage) pdf_drop_page(ctx, ppage);
    } fz_catch(ctx) {
        return -1;
    }
    return count;
}

/* Takes every reference to object `num` out of `array` and the arrays inside it. */
static void vp_remove_from_array(fz_context *ctx, pdf_obj *array, int num, int depth) {
    if (depth > 32 || !pdf_is_array(ctx, array)) return;
    for (int i = pdf_array_len(ctx, array) - 1; i >= 0; i--) {
        pdf_obj *o = pdf_array_get(ctx, array, i);
        if (pdf_is_indirect(ctx, o) && pdf_to_num(ctx, o) == num) pdf_array_delete(ctx, array, i);
        else if (pdf_is_array(ctx, o)) vp_remove_from_array(ctx, o, num, depth + 1);
    }
}

static void vp_remove_from_config(fz_context *ctx, pdf_obj *config, int num) {
    if (!pdf_is_dict(ctx, config)) return;
    vp_remove_from_array(ctx, pdf_dict_get(ctx, config, PDF_NAME(Order)), num, 0);
    vp_remove_from_array(ctx, pdf_dict_get(ctx, config, PDF_NAME(ON)), num, 0);
    vp_remove_from_array(ctx, pdf_dict_get(ctx, config, PDF_NAME(OFF)), num, 0);
    vp_remove_from_array(ctx, pdf_dict_get(ctx, config, PDF_NAME(Locked)), num, 0);
    vp_remove_from_array(ctx, pdf_dict_get(ctx, config, PDF_NAME(RBGroups)), num, 0);
    pdf_obj *as = pdf_dict_get(ctx, config, PDF_NAME(AS));
    for (int i = 0; i < pdf_array_len(ctx, as); i++)
        vp_remove_from_array(ctx, pdf_dict_get(ctx, pdf_array_get(ctx, as, i), PDF_NAME(OCGs)), num, 0);
}

int mupdf_pdf_remove_layer(fz_context *ctx, fz_document *doc, int layer, const char **out_error) {
    if (!ctx || !doc) return -1;
    int *nums = NULL, *states = NULL;
    fz_var(nums);
    fz_var(states);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc || !vp_is_layer(ctx, pdoc, layer)) fz_throw(ctx, FZ_ERROR_ARGUMENT, "No such layer");
        int n = 0;
        vp_layer_states(ctx, pdoc, &nums, &states, &n);
        pdf_obj *root = pdf_dict_get(ctx, pdf_trailer(ctx, pdoc), PDF_NAME(Root));
        pdf_obj *ocprops = pdf_dict_get(ctx, root, PDF_NAME(OCProperties));
        pdf_obj *ocgs = pdf_dict_get(ctx, ocprops, PDF_NAME(OCGs));
        vp_remove_from_array(ctx, ocgs, layer, 31);
        vp_remove_from_config(ctx, pdf_dict_get(ctx, ocprops, PDF_NAME(D)), layer);
        pdf_obj *configs = pdf_dict_get(ctx, ocprops, PDF_NAME(Configs));
        for (int i = 0; i < pdf_array_len(ctx, configs); i++) vp_remove_from_config(ctx, pdf_array_get(ctx, configs, i), layer);
        /* Without layers, the document is as it would be had it never had any. */
        if (pdf_array_len(ctx, ocgs) == 0) pdf_dict_del(ctx, root, PDF_NAME(OCProperties));
        vp_reload_layers(ctx, pdoc, nums, states, n);
    } fz_always(ctx) {
        fz_free(ctx, nums);
        fz_free(ctx, states);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

struct mupdf_layer_config {
    pdf_obj *ocprops; /* a copy, or NULL for a document without layers */
};

/* A copy of `obj` with the arrays and dictionaries in it copied too, even where they're objects of
 * their own, so later changes to them don't reach the copy. Layers, and groups of them, are
 * referred to, not copied. */
static pdf_obj *vp_copy_config(fz_context *ctx, pdf_document *pdoc, pdf_obj *obj, int depth) {
    if (pdf_is_indirect(ctx, obj)) {
        pdf_obj *type = pdf_dict_get(ctx, obj, PDF_NAME(Type));
        if (depth > 16 || pdf_name_eq(ctx, type, PDF_NAME(OCG)) || pdf_name_eq(ctx, type, PDF_NAME(OCMD)) ||
            (!pdf_is_array(ctx, obj) && !pdf_is_dict(ctx, obj)))
            return pdf_keep_obj(ctx, obj);
    }
    if (pdf_is_array(ctx, obj)) {
        int n = pdf_array_len(ctx, obj);
        pdf_obj *copy = pdf_new_array(ctx, pdoc, n);
        fz_try(ctx) {
            for (int i = 0; i < n; i++) pdf_array_push_drop(ctx, copy, vp_copy_config(ctx, pdoc, pdf_array_get(ctx, obj, i), depth + 1));
        } fz_catch(ctx) {
            pdf_drop_obj(ctx, copy);
            fz_rethrow(ctx);
        }
        return copy;
    }
    if (pdf_is_dict(ctx, obj)) {
        int n = pdf_dict_len(ctx, obj);
        pdf_obj *copy = pdf_new_dict(ctx, pdoc, n);
        fz_try(ctx) {
            for (int i = 0; i < n; i++)
                pdf_dict_put_drop(ctx, copy, pdf_dict_get_key(ctx, obj, i), vp_copy_config(ctx, pdoc, pdf_dict_get_val(ctx, obj, i), depth + 1));
        } fz_catch(ctx) {
            pdf_drop_obj(ctx, copy);
            fz_rethrow(ctx);
        }
        return copy;
    }
    return pdf_keep_obj(ctx, obj);
}

mupdf_layer_config *mupdf_pdf_copy_layer_config(fz_context *ctx, fz_document *doc) {
    if (!ctx || !doc) return NULL;
    mupdf_layer_config *config = NULL;
    fz_var(config);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        config = fz_malloc_struct(ctx, mupdf_layer_config);
        pdf_obj *ocprops = pdf_dict_getp(ctx, pdf_trailer(ctx, pdoc), "Root/OCProperties");
        if (pdf_is_dict(ctx, ocprops)) config->ocprops = vp_copy_config(ctx, pdoc, ocprops, 0);
    } fz_catch(ctx) {
        fz_free(ctx, config);
        return NULL;
    }
    return config;
}

int mupdf_pdf_restore_layer_config(fz_context *ctx, fz_document *doc, mupdf_layer_config *config, const char **out_error) {
    if (!ctx || !doc || !config) return -1;
    int *nums = NULL, *states = NULL;
    fz_var(nums);
    fz_var(states);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        int n = 0;
        vp_layer_states(ctx, pdoc, &nums, &states, &n);
        pdf_obj *root = pdf_dict_get(ctx, pdf_trailer(ctx, pdoc), PDF_NAME(Root));
        if (config->ocprops) {
            /* Put back a copy, so the one kept for Redo stays as it is. */
            pdf_dict_put_drop(ctx, root, PDF_NAME(OCProperties), vp_copy_config(ctx, pdoc, config->ocprops, 0));
        } else {
            pdf_dict_del(ctx, root, PDF_NAME(OCProperties));
        }
        vp_reload_layers(ctx, pdoc, nums, states, n);
    } fz_always(ctx) {
        fz_free(ctx, nums);
        fz_free(ctx, states);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

void mupdf_pdf_drop_layer_config(fz_context *ctx, mupdf_layer_config *config) {
    if (!ctx || !config) return;
    pdf_drop_obj(ctx, config->ocprops);
    fz_free(ctx, config);
}
