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
int mupdf_pdf_highlight_annot(fz_context *ctx, fz_document *doc, int pageno, fz_quad quad, float r, float g, float b, const char **out_error) {
    if (!ctx || !doc) return -1;
    pdf_page *ppage = NULL;
    pdf_annot *annot = NULL;
    fz_var(ppage);
    fz_var(annot);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_GENERIC, "Document is not a PDF");
        ppage = pdf_load_page(ctx, pdoc, pageno);
        if (!ppage) fz_throw(ctx, FZ_ERROR_GENERIC, "Failed to load PDF page for annotation");
        annot = pdf_create_annot(ctx, ppage, PDF_ANNOT_HIGHLIGHT);
        pdf_set_annot_quad_points(ctx, annot, 1, &quad);
        float color[3] = {r, g, b};
        pdf_set_annot_color(ctx, annot, 3, color);
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
        pdf_calculate_form(ctx, pdoc);
        int page_count = pdf_count_pages(ctx, pdoc);
        for (int p = 0; p < page_count; p++) {
            pdf_page *page = pdf_load_page(ctx, pdoc, p);
            if (page) {
                pdf_update_page(ctx, page);
                pdf_drop_page(ctx, page);
            }
        }
        pdf_save_document(ctx, pdoc, path, &pdf_default_write_options);
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
                               int *out_flags, const char **out_error) {
    if (!ctx || !doc) return -1;
    if (out_type) *out_type = 0;
    if (out_rect) *out_rect = fz_empty_rect;
    if (out_name) *out_name = NULL;
    if (out_value) *out_value = NULL;
    if (out_flags) *out_flags = 0;
    
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

        pdf_obj *field = pdf_annot_obj(ctx, w);
        if (field) {
            if (out_flags) {
                *out_flags = pdf_field_flags(ctx, field);
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
            
            // Radio siblings share one root field via /Parent — passing the kid's own object here
            // only updates that kid's /AS, leaving a previously-selected sibling stuck "on". Pass
            // the shared root so it clears every sibling. Checkboxes have no /Parent, so this is a
            // no-op fallback to `field`.
            pdf_obj *valueField = field;
            if (field) {
                pdf_obj *parent = pdf_dict_get(ctx, field, PDF_NAME(Parent));
                if (parent) valueField = parent;
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


