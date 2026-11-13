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

// What the sidebar's Document tab lists besides layers and attachments: form fields (with what
// a signature field says about its signature), links and named destinations.

#include "MuPDFBridge.h"
#include <string.h>

static void copy_text(char *dst, size_t size, const char *src) {
    if (!dst || size == 0) return;
    dst[0] = 0;
    if (!src) return;
    fz_strlcpy(dst, src, size);
}

int mupdf_pdf_has_form_fields(fz_context *ctx, fz_document *doc) {
    if (!ctx || !doc) return 0;
    int found = 0;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (pdoc) {
            pdf_obj *fields = pdf_dict_getp(ctx, pdf_trailer(ctx, pdoc), "Root/AcroForm/Fields");
            found = pdf_array_len(ctx, fields) > 0;
        }
    } fz_catch(ctx) {
        fz_report_error(ctx);
        found = 0;
    }
    return found;
}

int mupdf_pdf_has_links(fz_context *ctx, fz_document *doc) {
    if (!ctx || !doc) return 0;
    int found = 0;
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (pdoc) {
            int count = pdf_count_pages(ctx, pdoc);
            for (int i = 0; i < count && !found; i++) {
                pdf_obj *annots = pdf_dict_get(ctx, pdf_lookup_page_obj(ctx, pdoc, i), PDF_NAME(Annots));
                int n = pdf_array_len(ctx, annots);
                for (int k = 0; k < n; k++) {
                    if (pdf_name_eq(ctx, pdf_dict_get(ctx, pdf_array_get(ctx, annots, k), PDF_NAME(Subtype)), PDF_NAME(Link))) {
                        found = 1;
                        break;
                    }
                }
            }
        }
    } fz_catch(ctx) {
        fz_report_error(ctx);
        found = 0;
    }
    return found;
}

// The field's /TU (the name shown to people), from it or the field it's part of.
static const char *field_tooltip(fz_context *ctx, pdf_obj *field) {
    for (int depth = 0; field && depth < 32; depth++) {
        pdf_obj *tu = pdf_dict_get(ctx, field, PDF_NAME(TU));
        if (tu) return pdf_to_text_string(ctx, tu);
        field = pdf_dict_get(ctx, field, PDF_NAME(Parent));
    }
    return NULL;
}

// The /P of a DocMDP transform in the signature's references: 1 to 3 when the signature certifies
// the document, 0 when it doesn't.
static int certification_level(fz_context *ctx, pdf_obj *sig) {
    pdf_obj *refs = pdf_dict_get(ctx, sig, PDF_NAME(Reference));
    int n = pdf_array_len(ctx, refs);
    for (int i = 0; i < n; i++) {
        pdf_obj *ref = pdf_array_get(ctx, refs, i);
        if (pdf_name_eq(ctx, pdf_dict_get(ctx, ref, PDF_NAME(TransformMethod)), PDF_NAME(DocMDP))) {
            int p = pdf_dict_get_int(ctx, pdf_dict_get(ctx, ref, PDF_NAME(TransformParams)), PDF_NAME(P));
            return (p >= 1 && p <= 3) ? p : 2;
        }
    }
    return 0;
}

int mupdf_page_list_form_fields(fz_context *ctx, fz_document *doc, int pageno, mupdf_form_field *out, int capacity) {
    if (!ctx || !doc) return -1;
    pdf_page *page = NULL;
    char *name = NULL;
    int count = 0;
    fz_var(page);
    fz_var(name);
    fz_var(count);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        page = pdf_load_page(ctx, pdoc, pageno);
        for (pdf_annot *w = pdf_first_widget(ctx, page); w; w = pdf_next_widget(ctx, w)) {
            if (out && count < capacity) {
                mupdf_form_field *f = &out[count];
                memset(f, 0, sizeof *f);
                pdf_obj *obj = pdf_annot_obj(ctx, w);
                fz_rect r = pdf_bound_widget(ctx, w);
                f->page = pageno;
                f->type = (int)pdf_widget_type(ctx, w);
                f->x0 = r.x0; f->y0 = r.y0; f->x1 = r.x1; f->y1 = r.y1;
                f->flags = pdf_field_flags(ctx, obj);
                f->object_number = pdf_to_num(ctx, obj);
                name = pdf_load_field_name(ctx, obj);
                copy_text(f->name, sizeof f->name, name);
                fz_free(ctx, name);
                name = NULL;
                copy_text(f->label, sizeof f->label, field_tooltip(ctx, obj));
                f->signed_time = -1;
                f->changed_since_signing = -1;
                if (f->type == PDF_WIDGET_TYPE_SIGNATURE) {
                    f->is_signed = pdf_signature_is_signed(ctx, pdoc, obj);
                    if (f->is_signed) {
                        pdf_obj *sig = pdf_dict_get_inheritable(ctx, obj, PDF_NAME(V));
                        copy_text(f->signer, sizeof f->signer, pdf_dict_get_text_string(ctx, sig, PDF_NAME(Name)));
                        copy_text(f->reason, sizeof f->reason, pdf_dict_get_text_string(ctx, sig, PDF_NAME(Reason)));
                        copy_text(f->location, sizeof f->location, pdf_dict_get_text_string(ctx, sig, PDF_NAME(Location)));
                        if (pdf_dict_get(ctx, sig, PDF_NAME(M)))
                            f->signed_time = pdf_dict_get_date(ctx, sig, PDF_NAME(M));
                        f->certification = certification_level(ctx, sig);
                        fz_try(ctx)
                            f->changed_since_signing = pdf_signature_incremental_change_since_signing(ctx, pdoc, obj) ? 1 : 0;
                        fz_catch(ctx) {
                            fz_report_error(ctx);
                            f->changed_since_signing = -1;
                        }
                    }
                } else {
                    copy_text(f->value, sizeof f->value, pdf_field_value(ctx, obj));
                }
            }
            count++;
        }
    } fz_always(ctx) {
        fz_free(ctx, name);
        fz_drop_page(ctx, (fz_page *)page);
    } fz_catch(ctx) {
        fz_report_error(ctx);
        return -1;
    }
    return count;
}

// Adds the names in `dict` (a name tree flattened into a dictionary, or the PDF 1.1 /Dests
// dictionary) to `out` from `*count` on, leaving out any that are in `skip` (already added). A
// dictionary's keys are unique, so nothing else needs checking: documents can have hundreds of
// thousands of destinations.
static void add_dest_names(fz_context *ctx, fz_document *doc, pdf_obj *dict, pdf_obj *skip, mupdf_named_dest *out, int capacity, int *count) {
    int n = pdf_dict_len(ctx, dict);
    for (int i = 0; i < n; i++) {
        pdf_obj *key = pdf_dict_get_key(ctx, dict, i);
        const char *name = pdf_to_name(ctx, key);
        if (!name || !*name) continue;
        if (skip && pdf_dict_get(ctx, skip, key)) continue;
        if (out && *count < capacity) {
            mupdf_named_dest *d = &out[*count];
            memset(d, 0, sizeof *d);
            copy_text(d->name, sizeof d->name, name);
            d->page = -1;
            char *uri = NULL;
            fz_var(uri);
            fz_try(ctx) {
                uri = pdf_new_uri_from_path_and_named_dest(ctx, NULL, name);
                float x = 0, y = 0;
                fz_location loc = fz_resolve_link(ctx, doc, uri, &x, &y);
                d->page = loc.page;
                d->x = x;
                d->y = y;
            } fz_always(ctx) {
                fz_free(ctx, uri);
            } fz_catch(ctx) {
                fz_report_error(ctx);
                d->page = -1;
            }
        }
        (*count)++;
    }
}

int mupdf_pdf_list_named_dests(fz_context *ctx, fz_document *doc, mupdf_named_dest *out, int capacity) {
    if (!ctx || !doc) return 0;
    pdf_obj *tree = NULL;
    int count = 0;
    fz_var(tree);
    fz_var(count);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (pdoc) {
            tree = pdf_load_name_tree(ctx, pdoc, PDF_NAME(Dests));
            add_dest_names(ctx, doc, tree, NULL, out, capacity, &count);
            pdf_obj *old = pdf_dict_getp(ctx, pdf_trailer(ctx, pdoc), "Root/Dests");
            add_dest_names(ctx, doc, old, tree, out, capacity, &count);
        }
    } fz_always(ctx) {
        pdf_drop_obj(ctx, tree);
    } fz_catch(ctx) {
        fz_report_error(ctx);
    }
    return count;
}
