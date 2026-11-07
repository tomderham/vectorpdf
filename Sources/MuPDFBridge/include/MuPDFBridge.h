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

#ifndef MuPDFBridge_h
#define MuPDFBridge_h

#include <mupdf/fitz.h>
#include <mupdf/pdf.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Context Lifecycle
fz_context *mupdf_context_create(size_t max_store_bytes);
fz_context *mupdf_context_clone(fz_context *base);
void mupdf_context_drop(fz_context *ctx);
// A root context sharing nothing with the others but the FreeType lock, for a thread that does a
// lot of work on its own; never clone it (mupdf_context_clone returns NULL): clones would share
// locks that dropping it frees. Drop it with mupdf_context_drop_independent.
fz_context *mupdf_context_create_independent(size_t max_store_bytes);
void mupdf_context_drop_independent(fz_context *ctx);

// Document Lifecycle
int mupdf_document_open(fz_context *ctx, const char *path, fz_document **out_doc, const char **out_error);
int mupdf_document_count_pages(fz_context *ctx, fz_document *doc, int *out_count, const char **out_error);
void mupdf_document_drop(fz_context *ctx, fz_document *doc);

// Password Authentication — must be checked/resolved immediately after mupdf_document_open and
// before any other document access (page count, rendering, etc.), which can fail or return
// incorrect results on an unauthenticated encrypted document.
// Whether doc is a PDF; EPUB, XPS, CBZ and FB2 documents can be read but not edited or saved.
int mupdf_document_is_pdf(fz_context *ctx, fz_document *doc);
int mupdf_document_needs_password(fz_context *ctx, fz_document *doc, int *out_needs_password, const char **out_error);
int mupdf_document_authenticate_password(fz_context *ctx, fz_document *doc, const char *password, int *out_authenticated, const char **out_error);

// Outline (Table of Contents)
int mupdf_document_load_outline(fz_context *ctx, fz_document *doc, fz_outline **out_outline, const char **out_error);
void mupdf_outline_drop(fz_context *ctx, fz_outline *outline);
const char *mupdf_outline_title(fz_outline *outline);
const char *mupdf_outline_uri(fz_outline *outline);
int mupdf_outline_page(fz_outline *outline);
/// Where on its page the entry points, in page space; NAN when the destination gives no position.
float mupdf_outline_y(fz_outline *outline);
fz_outline *mupdf_outline_next(fz_outline *outline);
fz_outline *mupdf_outline_down(fz_outline *outline);

// Page Lifecycle
int mupdf_page_load(fz_context *ctx, fz_document *doc, int pageno, fz_page **out_page, const char **out_error);
int mupdf_page_bounds(fz_context *ctx, fz_page *page, fz_rect *out_rect, const char **out_error);
void mupdf_page_drop(fz_context *ctx, fz_page *page);

// Display List
int mupdf_display_list_create_hiding(fz_context *ctx, fz_page *page, const int *hidden, int hidden_count, fz_display_list **out_list, const char **out_error);
int mupdf_display_list_create(fz_context *ctx, fz_page *page, fz_display_list **out_list, const char **out_error);
void mupdf_display_list_drop(fz_context *ctx, fz_display_list *list);

// Pixmap Rendering
int mupdf_render_display_list(fz_context *ctx, fz_display_list *list, float scale_x, float scale_y, fz_pixmap **out_pixmap, const char **out_error);
int mupdf_render_page(fz_context *ctx, fz_page *page, float scale_x, float scale_y, fz_pixmap **out_pixmap, const char **out_error);
int mupdf_render_page_rect(fz_context *ctx, fz_page *page, float scale_x, float scale_y, float x0, float y0, float x1, float y1, fz_pixmap **out_pixmap, const char **out_error);
// Renders the part of a display list inside page rect (x0, y0)-(x1, y1) at `scale`. Pass a rect
// already on the pixel grid (each edge * scale a whole number), or the bitmap won't line up with it.
int mupdf_render_display_list_rect(fz_context *ctx, fz_display_list *list, float scale, float x0, float y0, float x1, float y1, fz_pixmap **out_pixmap, const char **out_error);
void mupdf_pixmap_drop(fz_context *ctx, fz_pixmap *pixmap);
int mupdf_pixmap_width(fz_pixmap *pixmap);
int mupdf_pixmap_height(fz_pixmap *pixmap);
ptrdiff_t mupdf_pixmap_stride(fz_pixmap *pixmap);
unsigned char *mupdf_pixmap_samples(fz_pixmap *pixmap);
int mupdf_pixmap_n(fz_pixmap *pixmap);

// Structured Text
int mupdf_stext_page_load(fz_context *ctx, fz_page *page, fz_stext_page **out_stext, const char **out_error);
int mupdf_stext_page_load_from_display_list(fz_context *ctx, fz_display_list *list, fz_stext_page **out_stext, const char **out_error);
void mupdf_stext_page_drop(fz_context *ctx, fz_stext_page *stext);

fz_stext_block *mupdf_stext_first_block(fz_stext_page *page);
fz_stext_block *mupdf_stext_next_block(fz_stext_block *block);
int mupdf_stext_block_type(fz_stext_block *block);
fz_rect mupdf_stext_block_bbox(fz_stext_block *block);
uint32_t mupdf_stext_block_vector_flags(fz_stext_block *block);
uint32_t mupdf_stext_block_vector_argb(fz_stext_block *block);

fz_stext_line *mupdf_stext_block_first_line(fz_stext_block *block);
fz_stext_line *mupdf_stext_next_line(fz_stext_line *line);
fz_rect mupdf_stext_line_bbox(fz_stext_line *line);

fz_stext_char *mupdf_stext_line_first_char(fz_stext_line *line);
fz_stext_char *mupdf_stext_next_char(fz_stext_char *ch);
int mupdf_stext_char_c(fz_stext_char *ch);
fz_quad mupdf_stext_char_quad(fz_stext_char *ch);
fz_point mupdf_stext_char_origin(fz_stext_char *ch);
float mupdf_stext_char_size(fz_stext_char *ch);
int mupdf_stext_char_is_bold(fz_context *ctx, fz_stext_char *ch);
int mupdf_stext_char_is_italic(fz_context *ctx, fz_stext_char *ch);
const char *mupdf_stext_char_font_name(fz_context *ctx, fz_stext_char *ch);
uint32_t mupdf_stext_char_color(fz_stext_char *ch);

// Links & Cross-References
int mupdf_links_load(fz_context *ctx, fz_page *page, fz_link **out_links, const char **out_error);
void mupdf_links_drop(fz_context *ctx, fz_link *links);
fz_link *mupdf_link_next(fz_link *link);
fz_rect mupdf_link_rect(fz_link *link);
const char *mupdf_link_uri(fz_link *link);
int mupdf_resolve_link_page(fz_context *ctx, fz_document *doc, const char *uri, int *out_page, float *out_x, float *out_y);

// Annotations & PDF Saving
int mupdf_pdf_highlight_annot(fz_context *ctx, fz_document *doc, int pageno, fz_quad quad, float r, float g, float b, const char **out_error);
int mupdf_pdf_add_highlight(fz_context *ctx, fz_document *doc, int pageno, const fz_quad *quads, int n_quads, float r, float g, float b, const char **out_error);
int mupdf_pdf_add_text_markup(fz_context *ctx, fz_document *doc, int pageno, int type, const fz_quad *quads, int n_quads, float r, float g, float b, const char **out_error);
int mupdf_pdf_add_ink_stroke(fz_context *ctx, fz_document *doc, int pageno, const fz_point *points, int n_points, float stroke_width, float r, float g, float b, const char **out_error);
int mupdf_pdf_add_free_text_annot(fz_context *ctx, fz_document *doc, int pageno, float x0, float y0, float x1, float y1, const char *text, float font_size, float r, float g, float b, const char **out_error);
int mupdf_pdf_delete_highlight_near_point(fz_context *ctx, fz_document *doc, int pageno, float x, float y, const char **out_error);
int mupdf_pdf_delete_annot_near_point(fz_context *ctx, fz_document *doc, int pageno, float x, float y, const char **out_error);
int mupdf_pdf_last_annot_objnum(fz_context *ctx, fz_document *doc, int pageno, int *out_objnum, const char **out_error);
int mupdf_pdf_delete_annot_by_objnum(fz_context *ctx, fz_document *doc, int pageno, int objnum, const char **out_error);

#define MUPDF_MEASUREMENT_MAX_POINTS 512
typedef struct {
    int kind;      /* 1 = length, 2 = perimeter, 3 = area, 4 = angle */
    int objnum;
    float r, g, b;
    int n_points;
    float xy[2 * MUPDF_MEASUREMENT_MAX_POINTS]; /* page (top-down) coordinates */
    char text[256]; /* /Contents, UTF-8, truncated */
    /* The layer it's on (its /OC's object number), or 0; and whether that's hidden. */
    int layer, hidden;
    /* For a length: how far the dimension line is drawn from the measured points, in page
       (top-down) space, as mupdf_pdf_add_line_dimension's leader_offset. */
    float leader;
} mupdf_measurement_annot;
int mupdf_pdf_get_measurement_annots(fz_context *ctx, fz_document *doc, int pageno,
                                     mupdf_measurement_annot *out, int capacity, int *out_count,
                                     const char **out_error);
int mupdf_pdf_stamp_image_annot(fz_context *ctx, fz_document *doc, int pageno, float x0, float y0, float x1, float y1, const unsigned char *image_data, size_t image_len, const char **out_error);
int mupdf_pdf_page_has_stamp_near_rect(fz_context *ctx, fz_document *doc, int pageno, float x0, float y0, float x1, float y1, int *out_found, const char **out_error);
int mupdf_pdf_add_callout_annot(fz_context *ctx, fz_document *doc, int pageno,
                                float target_x, float target_y,
                                float knee_x, float knee_y,
                                float box_x0, float box_y0, float box_x1, float box_y1,
                                const char *text, float font_size, int line_ending,
                                float r, float g, float b,
                                const char **out_error);
typedef struct {
    char subtype[32];
    /* /Rect, and the area it's drawn in, in page space. */
    float x0, y0, x1, y1;
    float bx0, by0, bx1, by1;
    int has_color;
    float r, g, b;
    float border_width;
    int is_cloud;
    int is_measurement;
    /* A line's end style, or -1. */
    int line_ending;
    int point_count;
    /* The layer it's on (its /OC's object number), or 0; and whether that's hidden. */
    int layer, hidden;
} mupdf_annot_description;

fz_document *mupdf_pdf_new_holding_document(fz_context *ctx);
int mupdf_pdf_stash_and_delete_annot(fz_context *ctx, fz_document *doc, int pageno, int objnum, fz_document *holding, int *out_index, const char **out_error);
int mupdf_pdf_unstash_annot(fz_context *ctx, fz_document *doc, int pageno, fz_document *holding, int index, int *out_objnum, const char **out_error);
int mupdf_pdf_snapshot_annot(fz_context *ctx, fz_document *doc, int pageno, int objnum, fz_document *holding, int *out_index, const char **out_error);
int mupdf_pdf_restore_annot_snapshot(fz_context *ctx, fz_document *doc, int pageno, int objnum, fz_document *holding, int index, const char **out_error);
int mupdf_pdf_translate_annot(fz_context *ctx, fz_document *doc, int pageno, int objnum, float dx, float dy, const char **out_error);
int mupdf_pdf_restyle_annot(fz_context *ctx, fz_document *doc, int pageno, int objnum,
                            int has_color, float r, float g, float b, float width, int line_ending,
                            int has_rect, float x0, float y0, float x1, float y1,
                            const fz_point *points, int count, const char **out_error);
int mupdf_pdf_describe_annot(fz_context *ctx, fz_document *doc, int pageno, int objnum, mupdf_annot_description *out,
                             fz_point *points, int max_points, const char **out_error);
int mupdf_pdf_render_annot(fz_context *ctx, fz_document *doc, int pageno, int objnum, float scale,
                           fz_pixmap **out_pixmap, fz_rect *out_bounds, const char **out_error);
int mupdf_pdf_annot_near_point(fz_context *ctx, fz_document *doc, int pageno, float x, float y, int *out_objnum, const char **out_error);
int mupdf_pdf_add_cloud_annot(fz_context *ctx, fz_document *doc, int pageno,
                              float x0, float y0, float x1, float y1, float intensity,
                              float r, float g, float b, const char **out_error);
int mupdf_pdf_add_cloud_polygon_annot(fz_context *ctx, fz_document *doc, int pageno,
                                      const fz_point *points, int count, float intensity,
                                      float r, float g, float b, const char **out_error);
int mupdf_pdf_add_note_annot(fz_context *ctx, fz_document *doc, int pageno,
                             float x0, float y0, float x1, float y1, const char *text,
                             float r, float g, float b, const char **out_error);
/* kind: 0 rectangle (Square) and 1 oval (Circle) fill the box (x0, y0)-(x1, y1); 2 is a Line
 * from (x0, y0) to (x1, y1), with line_ending at (x1, y1). */
int mupdf_pdf_add_shape_annot(fz_context *ctx, fz_document *doc, int pageno, int kind,
                              float x0, float y0, float x1, float y1, float width, int line_ending,
                              float r, float g, float b, const char **out_error);
int mupdf_pdf_set_annot_author(fz_context *ctx, fz_document *doc, int pageno, int objnum, const char *author, const char **out_error);
int mupdf_pdf_set_annot_comment(fz_context *ctx, fz_document *doc, int pageno, int objnum, const char *text, const char **out_error);
int mupdf_pdf_add_annot_reply(fz_context *ctx, fz_document *doc, int pageno, int parent_objnum,
                              const char *text, const char *author,
                              const char *state, const char *state_model, const char **out_error);
int mupdf_pdf_move_annot_thread(fz_context *ctx, fz_document *doc, int pageno, int from_objnum, int to_objnum, const char **out_error);

typedef struct {
    int objnum;
    int parent_objnum;  /* 0 unless this replies to another annotation */
    float x0, y0, x1, y1; /* page (top-down) coordinates */
    float r, g, b;
    long long created, modified; /* seconds since 1970, 0 or less if absent */
    char subtype[24];
    int is_callout, is_cloud;
    /* The layer it's on (its /OC's object number), or 0; and whether that's hidden. */
    int layer, hidden;
    char *author, *contents, *state, *state_model; /* UTF-8, never NULL */
} mupdf_review_annot;
int mupdf_pdf_get_review_annots(fz_context *ctx, fz_document *doc, int pageno,
                                mupdf_review_annot **out, int *out_count, const char **out_error);
void mupdf_pdf_free_review_annots(fz_context *ctx, mupdf_review_annot *annots, int count);
int mupdf_pdf_add_line_dimension_annot(fz_context *ctx, fz_document *doc, int pageno,
                                       float x0, float y0, float x1, float y1,
                                       float leader_offset, const char *text,
                                       float r, float g, float b,
                                       const char **out_error);
int mupdf_pdf_add_polyline_dimension_annot(fz_context *ctx, fz_document *doc, int pageno,
                                           const fz_point *vertices, int n_vertices,
                                           const char *text,
                                           float r, float g, float b,
                                           const char **out_error);
int mupdf_pdf_add_polygon_dimension_annot(fz_context *ctx, fz_document *doc, int pageno,
                                          const fz_point *vertices, int n_vertices,
                                          const char *text,
                                          float r, float g, float b, float fill_alpha,
                                          const char **out_error);
int mupdf_pdf_add_angle_annot(fz_context *ctx, fz_document *doc, int pageno,
                              const fz_point *vertices, int n_vertices,
                              const char *text,
                              float r, float g, float b,
                              const char **out_error);
int mupdf_pdf_set_page_scale(fz_context *ctx, fz_document *doc, int pageno,
                             const char *ratio_str, const char *unit_str,
                             float pts_per_unit, const char **out_error);
int mupdf_pdf_get_page_scale(fz_context *ctx, fz_document *doc, int pageno,
                             char *out_ratio, size_t ratio_cap,
                             char *out_unit, size_t unit_cap,
                             float *out_pts_per_unit, int *out_found,
                             const char **out_error);
int mupdf_pdf_rename_outline_items(fz_context *ctx, fz_document *doc, const char *title, const char *new_title, const char **out_error);
int mupdf_pdf_strip_document_data(fz_context *ctx, fz_document *doc, const char **out_error);
int mupdf_page_apply_redaction_rects(fz_context *ctx, fz_document *doc, int pageno, const fz_rect *rects, int n_rects, int black_boxes, const char **out_error);
int mupdf_page_add_redact_annot(fz_context *ctx, fz_document *doc, int pageno, float x0, float y0, float x1, float y1, const char **out_error);
int mupdf_pdf_save(fz_context *ctx, fz_document *doc, const char *path, const char **out_error);
int mupdf_pdf_save_encrypted(fz_context *ctx, fz_document *doc, const char *path, const char *password, const char **out_error);
// Baked annotations stay on their layers.
int mupdf_pdf_save_flattened(fz_context *ctx, fz_document *doc, const char *path, int bake_annots, int bake_widgets, const char **out_error);
// Saves a smaller copy: unused and duplicate objects removed, streams compressed into object
// streams, and optionally fonts subset to the glyphs used, colour and grey images above
// image_dpi * 1.5 downsampled to image_dpi (0 leaves images alone), and text turned into outlines.
// It changes `doc`, so pass a throwaway copy, never the open document.
int mupdf_pdf_save_optimized(fz_context *ctx, fz_document *doc, const char *path, int subset_fonts, int image_dpi, int outline_text, const char **out_error);

// Attachments (embedded files)
typedef struct {
    /* The page of its file attachment annotation, or -1 for one attached to the document. */
    int page;
    /* Bytes, or -1 if the file doesn't say. */
    int size;
    /* Seconds since 1970, or -1 if unknown. */
    int64_t created, modified;
    char name[512];
    /* Empty if the file doesn't say. */
    char mime_type[128];
    char description[512];
} mupdf_attachment;

// Lists up to `capacity` of the PDF's embedded files into `out` and returns how many there are,
// in a fixed order: the document's attachments (/EmbeddedFiles), its associated files (/AF), then
// file attachment annotations page by page. Each file once; references to files outside the PDF
// are left out. 0 for a document that isn't a PDF.
int mupdf_pdf_list_attachments(fz_context *ctx, fz_document *doc, mupdf_attachment *out, int capacity);
// Writes the contents of attachment `index`, in mupdf_pdf_list_attachments' order, to `path`.
int mupdf_pdf_save_attachment(fz_context *ctx, fz_document *doc, int index, const char *path, const char **out_error);
// Attaches a file to the document (in /EmbeddedFiles). `mime_type` may be NULL.
int mupdf_pdf_add_attachment(fz_context *ctx, fz_document *doc, const char *name, const char *mime_type, const unsigned char *data, size_t length, const char *description, const char **out_error);

// Page Manipulation
int mupdf_pdf_rotate_page(fz_context *ctx, fz_document *doc, int pageno, int delta_degrees, const char **out_error);
int mupdf_pdf_delete_page(fz_context *ctx, fz_document *doc, int pageno, const char **out_error);
int mupdf_pdf_reorder_page(fz_context *ctx, fz_document *doc, int from_page, int to_page, const char **out_error);
int mupdf_pdf_reorder_pages(fz_context *ctx, fz_document *doc, const int *page_indices, int count, int dest_slot, const char **out_error);
int mupdf_pdf_delete_pages(fz_context *ctx, fz_document *doc, const int *page_indices, int count, const char **out_error);
int mupdf_pdf_extract_pages(fz_context *ctx, fz_document *doc, const int *page_indices, int count, const char *out_path, const char **out_error);
int mupdf_pdf_duplicate_pages(fz_context *ctx, fz_document *doc, const int *page_indices, int count, int *out_inserted_slot, const char **out_error);
int mupdf_pdf_import_pages(fz_context *ctx, fz_document *doc, const char *src_path, int insert_slot, int *out_imported_count, const char **out_error);
int mupdf_pdf_insert_blank_page(fz_context *ctx, fz_document *doc, int insert_slot, float width, float height, const char **out_error);

// Page Labels
// Whether the document has a /PageLabels tree that's safe to read; if not, pages have no labels.
int mupdf_pdf_has_page_labels(fz_context *ctx, fz_document *doc);
int mupdf_pdf_page_label(fz_context *ctx, fz_document *doc, int pageno, char *buf, int size, const char **out_error);

// MuPDF shifts labels when pages are inserted or deleted, so it can't move a label with its page,
// and it adds labels to a document that had none. To avoid that, take the labels out before a page
// edit and restore them afterwards. `page_map[new_index]` is the page's index before the edit, or
// -1 for a page the edit added. Pass a NULL map if the edit failed, which puts back what was there.
typedef struct mupdf_page_labels mupdf_page_labels;
mupdf_page_labels *mupdf_pdf_take_page_labels(fz_context *ctx, fz_document *doc);
int mupdf_pdf_restore_page_labels(fz_context *ctx, fz_document *doc, mupdf_page_labels *labels, const int *page_map, int count, const char **out_error);

// Layers (Optional Content Groups)
// Layer visibility belongs to each opened document, not the file, so every copy that draws or
// reads text has to be told the same states. Nothing here changes what's saved.
// The number of layers; 0 for a document without any, or one that isn't a PDF.
int mupdf_pdf_count_layers(fz_context *ctx, fz_document *doc);
// Each layer's state (1 shown, 0 hidden), `count` of them, as counted above.
int mupdf_pdf_get_layer_states(fz_context *ctx, fz_document *doc, int *out_states, int count);
int mupdf_pdf_set_layer_states(fz_context *ctx, fz_document *doc, const int *states, int count);
// The layer's own name, copied into `buf`.
int mupdf_pdf_layer_name(fz_context *ctx, fz_document *doc, int layer, char *buf, int size);
// The layer (as numbered above) that's `position`th in the document's own list of them (its
// /OCGs), which isn't the order above; -1 if there's none.
int mupdf_pdf_layer_at_position(fz_context *ctx, fz_document *doc, int position);
// The object number of a layer (as numbered above), which names it in every copy of the file and
// doesn't change when layers are added; 0 if there's none.
int mupdf_pdf_layer_object_number(fz_context *ctx, fz_document *doc, int layer);
// Adds a layer, shown, to the end of the document's list, keeping the others as they're shown
// now. Sets *out_object_number to the new layer's object number. Unlike showing and hiding
// layers, this changes the file.
int mupdf_pdf_add_layer(fz_context *ctx, fz_document *doc, const char *name, int *out_object_number, const char **out_error);
// Renames the layer with this object number.
int mupdf_pdf_rename_layer(fz_context *ctx, fz_document *doc, int layer, const char *name, const char **out_error);
// Whether anything but annotations and the layer list refers to the layer: page content, a form
// or an image drawn on it. Such a layer can't be deleted without leaving that content always shown.
// 1 if so, or if it can't be told; 0 if it holds only annotations, or nothing.
int mupdf_pdf_layer_holds_content(fz_context *ctx, fz_document *doc, int layer);
// The annotations on a layer, as (page, object number) pairs in `out`, up to `capacity` pairs.
// Returns how many there are, or -1.
int mupdf_pdf_annots_on_layer(fz_context *ctx, fz_document *doc, int layer, int *out, int capacity);
// Takes a layer out of the document's lists of layers, removing them when it was the last. The
// annotations on it should be taken off it first. The layers left are shown as they were.
int mupdf_pdf_remove_layer(fz_context *ctx, fz_document *doc, int layer, const char **out_error);
// A copy of the document's list of layers and how they're arranged (its /OCProperties), for Undo,
// and putting one back. The layers left are shown as they were; any others, as the copy says.
typedef struct mupdf_layer_config mupdf_layer_config;
mupdf_layer_config *mupdf_pdf_copy_layer_config(fz_context *ctx, fz_document *doc);
int mupdf_pdf_restore_layer_config(fz_context *ctx, fz_document *doc, mupdf_layer_config *config, const char **out_error);
void mupdf_pdf_drop_layer_config(fz_context *ctx, mupdf_layer_config *config);
// The layer an annotation is on (its /OC's object number), or 0.
int mupdf_pdf_annot_layer(fz_context *ctx, fz_document *doc, int pageno, int objnum, int *out_layer, const char **out_error);
// Puts an annotation on the layer with this object number, or on none for 0, so it's shown and
// hidden with it here and in other readers.
int mupdf_pdf_set_annot_layer(fz_context *ctx, fz_document *doc, int pageno, int objnum, int layer, const char **out_error);
// The document's own list of layers to show people (its /Order), with headings, nesting and
// groups of which only one can be shown. 0 entries when it has none: list the layers instead.
int mupdf_pdf_count_layer_ui(fz_context *ctx, fz_document *doc);
typedef struct {
    int depth;
    int type;       // 0 heading, 1 checkbox, 2 one of a group (radio)
    int selected;
    int locked;
    int object_number; // the layer's, or 0 for a heading
} mupdf_layer_ui_entry;
// `config` is the configuration chosen with mupdf_pdf_select_layer_config, -1 for the default:
// the list is the one it gives, if it gives one.
int mupdf_pdf_layer_ui_entry(fz_context *ctx, fz_document *doc, int config, int index, mupdf_layer_ui_entry *out, char *text_buf, int text_size);
// Shows or hides an entry, hiding the rest of its group when it's one of one, and doing nothing
// to a locked entry or a heading.
int mupdf_pdf_toggle_layer_ui(fz_context *ctx, fz_document *doc, int index, const char **out_error);
// The document's alternative layer configurations (its /Configs), such as a plot set-up or a
// language, not counting the default one (/D).
int mupdf_pdf_count_layer_configs(fz_context *ctx, fz_document *doc);
// A configuration's name (-1 for the default), copied into `buf`; empty when it has none.
int mupdf_pdf_layer_config_name(fz_context *ctx, fz_document *doc, int config, char *buf, int size);
// Shows and hides layers as configuration `config` says (-1 for the default), and takes its list
// of layers, groups, locked layers and intent. With `states` (`count` of them, as
// mupdf_pdf_get_layer_states gives them), shows the layers that way instead, keeping the rest.
// Like showing and hiding layers, this doesn't change the file. Reading the layers again after the
// list of them changes (adding, renaming or deleting one) goes back to the default: choose the
// configuration again, with the states, after that.
int mupdf_pdf_select_layer_config(fz_context *ctx, fz_document *doc, int config, const int *states, int count, const char **out_error);
// How the default configuration shows each layer, as the file opens: `count` states, as
// mupdf_pdf_get_layer_states gives them.
int mupdf_pdf_default_layer_states(fz_context *ctx, fz_document *doc, int *out_states, int count);
// Takes what hidden layers hold out of the document, as they're shown now: page content marked as
// on them, forms and images on them, and annotations on them; then the hidden layers themselves.
// The layers left are all shown, and the default configuration lists them; alternative
// configurations are removed.
int mupdf_pdf_remove_hidden_layers(fz_context *ctx, fz_document *doc, const char **out_error);

// Store & Memory Management
// No fz_empty_store wrapper: the store is shared by every cloned context, and emptying it frees
// items other threads are still using. Shrinking evicts only unused items, so is safe.
int mupdf_context_shrink_store(fz_context *ctx, unsigned int percent);
void mupdf_free(fz_context *ctx, void *ptr);

// Fast Plain Text Extraction
char *mupdf_stext_page_text(fz_context *ctx, fz_stext_page *page);

// AcroForms & Interactive Form Widgets
int mupdf_page_count_widgets(fz_context *ctx, fz_document *doc, int pageno, int *out_count, const char **out_error);
int mupdf_page_get_widget_info(fz_context *ctx, fz_document *doc, int pageno, int widget_index,
                               int *out_type, fz_rect *out_rect, char **out_name, char **out_value,
                               int *out_flags, float *out_font_size,
                               int *out_max_len, int *out_text_align,
                               const char **out_error);
int mupdf_page_widget_is_reset_button(fz_context *ctx, fz_document *doc, int pageno, int widget_index, int *out_is_reset, const char **out_error);
int mupdf_page_set_widget_value(fz_context *ctx, fz_document *doc, int pageno, int widget_index,
                                const char *value, const char **out_error);
int mupdf_document_reset_form(fz_context *ctx, fz_document *doc, const char **out_error);
int mupdf_page_get_choice_options(fz_context *ctx, fz_document *doc, int pageno, int widget_index,
                                  char ***out_options, int *out_count, const char **out_error);
void mupdf_free_choice_options(fz_context *ctx, char **options, int count);

// Document Metadata, Encryption & Security Permissions
typedef struct {
    char format[64];
    char encryption[64];
    char title[256];
    char author[256];
    char subject[256];
    char keywords[512];
    char creator[256];
    char producer[256];
    char creation_date[64];
    char mod_date[64];
    int is_encrypted;
    int pdf_version;
} mupdf_document_metadata;

typedef struct {
    int can_print;
    int can_modify;
    int can_copy;
    int can_annotate;
    int can_fill_forms;
    int can_accessibility;
    int can_assemble;
    int can_print_high_quality;
} mupdf_document_permissions;

// Page Geometry Boxes
typedef struct {
    fz_rect media_box;
    fz_rect crop_box;
    fz_rect bleed_box;
    fz_rect trim_box;
    fz_rect art_box;
    int has_crop_box;
    int has_bleed_box;
    int has_trim_box;
    int has_art_box;
} mupdf_page_boxes;

// Embedded & Subset Font Catalog
typedef struct {
    char name[128];
    char subtype[64];
    char encoding[64];
    int is_embedded;
    int is_subset;
} mupdf_font_entry;

typedef struct {
    mupdf_font_entry *fonts;
    int count;
} mupdf_font_list;

int mupdf_document_get_metadata(fz_context *ctx, fz_document *doc, mupdf_document_metadata *out_meta, const char **out_error);
int mupdf_document_get_permissions(fz_context *ctx, fz_document *doc, mupdf_document_permissions *out_perms, const char **out_error);
int mupdf_page_get_boxes(fz_context *ctx, fz_document *doc, int pageno, mupdf_page_boxes *out_boxes, const char **out_error);
int mupdf_document_get_fonts(fz_context *ctx, fz_document *doc, mupdf_font_list *out_fonts, const char **out_error);
void mupdf_free_font_list(fz_context *ctx, mupdf_font_list *fonts);

// SVG Page Export
int mupdf_page_to_svg(fz_context *ctx, fz_document *doc, int pageno, int text_as_path, char **out_svg, const char **out_error);
int mupdf_page_export_svg(fz_context *ctx, fz_document *doc, int pageno, const char *out_path, int text_as_path, const char **out_error);

// Reading theme (dark/sepia) applied in place to an RGB(A) buffer
int mupdf_apply_color_appearance(fz_context *ctx, unsigned char *samples, int width, int height, int stride, int n, int appearance_mode);

#ifdef __cplusplus
}
#endif

#endif /* MuPDFBridge_h */
