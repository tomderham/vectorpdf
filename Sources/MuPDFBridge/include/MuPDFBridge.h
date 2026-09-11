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

// Document Lifecycle
int mupdf_document_open(fz_context *ctx, const char *path, fz_document **out_doc, const char **out_error);
int mupdf_document_count_pages(fz_context *ctx, fz_document *doc, int *out_count, const char **out_error);
void mupdf_document_drop(fz_context *ctx, fz_document *doc);

// Password Authentication — must be checked/resolved immediately after mupdf_document_open and
// before any other document access (page count, rendering, etc.), which can fail or return
// incorrect results on an unauthenticated encrypted document.
int mupdf_document_needs_password(fz_context *ctx, fz_document *doc, int *out_needs_password, const char **out_error);
int mupdf_document_authenticate_password(fz_context *ctx, fz_document *doc, const char *password, int *out_authenticated, const char **out_error);

// Outline (Table of Contents)
int mupdf_document_load_outline(fz_context *ctx, fz_document *doc, fz_outline **out_outline, const char **out_error);
void mupdf_outline_drop(fz_context *ctx, fz_outline *outline);
const char *mupdf_outline_title(fz_outline *outline);
const char *mupdf_outline_uri(fz_outline *outline);
int mupdf_outline_page(fz_outline *outline);
fz_outline *mupdf_outline_next(fz_outline *outline);
fz_outline *mupdf_outline_down(fz_outline *outline);

// Page Lifecycle
int mupdf_page_load(fz_context *ctx, fz_document *doc, int pageno, fz_page **out_page, const char **out_error);
int mupdf_page_bounds(fz_context *ctx, fz_page *page, fz_rect *out_rect, const char **out_error);
void mupdf_page_drop(fz_context *ctx, fz_page *page);

// Display List
int mupdf_display_list_create(fz_context *ctx, fz_page *page, fz_display_list **out_list, const char **out_error);
void mupdf_display_list_drop(fz_context *ctx, fz_display_list *list);

// Pixmap Rendering
int mupdf_render_display_list(fz_context *ctx, fz_display_list *list, float scale_x, float scale_y, fz_pixmap **out_pixmap, const char **out_error);
int mupdf_render_page(fz_context *ctx, fz_page *page, float scale_x, float scale_y, fz_pixmap **out_pixmap, const char **out_error);
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

fz_stext_line *mupdf_stext_block_first_line(fz_stext_block *block);
fz_stext_line *mupdf_stext_next_line(fz_stext_line *line);
fz_rect mupdf_stext_line_bbox(fz_stext_line *line);

fz_stext_char *mupdf_stext_line_first_char(fz_stext_line *line);
fz_stext_char *mupdf_stext_next_char(fz_stext_char *ch);
int mupdf_stext_char_c(fz_stext_char *ch);
fz_quad mupdf_stext_char_quad(fz_stext_char *ch);
fz_point mupdf_stext_char_origin(fz_stext_char *ch);
float mupdf_stext_char_size(fz_stext_char *ch);

// Links & Cross-References
int mupdf_links_load(fz_context *ctx, fz_page *page, fz_link **out_links, const char **out_error);
void mupdf_links_drop(fz_context *ctx, fz_link *links);
fz_link *mupdf_link_next(fz_link *link);
fz_rect mupdf_link_rect(fz_link *link);
const char *mupdf_link_uri(fz_link *link);
int mupdf_resolve_link_page(fz_context *ctx, fz_document *doc, const char *uri, int *out_page, float *out_x, float *out_y);

// Annotations & PDF Saving
int mupdf_pdf_highlight_annot(fz_context *ctx, fz_document *doc, int pageno, fz_quad quad, float r, float g, float b, const char **out_error);
int mupdf_pdf_stamp_image_annot(fz_context *ctx, fz_document *doc, int pageno, float x0, float y0, float x1, float y1, const unsigned char *image_data, size_t image_len, const char **out_error);
int mupdf_pdf_page_has_stamp_near_rect(fz_context *ctx, fz_document *doc, int pageno, float x0, float y0, float x1, float y1, int *out_found, const char **out_error);
int mupdf_pdf_save(fz_context *ctx, fz_document *doc, const char *path, const char **out_error);

// Store & Memory Management
void mupdf_context_empty_store(fz_context *ctx);
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
int mupdf_page_set_widget_value(fz_context *ctx, fz_document *doc, int pageno, int widget_index,
                                const char *value, const char **out_error);
int mupdf_document_reset_form(fz_context *ctx, fz_document *doc, const char **out_error);
int mupdf_page_get_choice_options(fz_context *ctx, fz_document *doc, int pageno, int widget_index,
                                  char ***out_options, int *out_count, const char **out_error);
void mupdf_free_choice_options(fz_context *ctx, char **options, int count);

#ifdef __cplusplus
}
#endif

#endif /* MuPDFBridge_h */
