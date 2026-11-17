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

// MuPDF accepts changes to form fields after signing, and nothing else; Acrobat also accepts
// comments being added, changed or deleted, unless a certification allows less. These tell
// whether a save (`version`, as xref sections count: 0 the latest) changed only comments.

static pdf_obj *object_in_version(fz_context *ctx, pdf_document *doc, int num, int version) {
    int base = doc->xref_base;
    pdf_obj *obj = NULL;
    doc->xref_base = version;
    fz_try(ctx)
        obj = pdf_load_object(ctx, doc, num);
    fz_always(ctx)
        doc->xref_base = base;
    fz_catch(ctx)
        obj = NULL;
    if (obj && pdf_is_null(ctx, obj)) { pdf_drop_obj(ctx, obj); obj = NULL; }
    return obj;
}

static int is_comment(fz_context *ctx, pdf_obj *obj) {
    if (!pdf_is_dict(ctx, obj)) return 0;
    pdf_obj *subtype = pdf_dict_get(ctx, obj, PDF_NAME(Subtype));
    pdf_obj *type = pdf_dict_get(ctx, obj, PDF_NAME(Type));
    if (!pdf_is_name(ctx, subtype) || pdf_name_eq(ctx, subtype, PDF_NAME(Widget))) return 0;
    if (type && !pdf_name_eq(ctx, type, PDF_NAME(Annot))) return 0;
    // Streams have subtypes too (Form, Image): an annotation is a dictionary with a /Rect.
    return !pdf_is_stream(ctx, obj) && pdf_is_array(ctx, pdf_dict_get(ctx, obj, PDF_NAME(Rect)));
}

/* The widgets in a page's /Annots, by object number, into `out`. Returns how many. */
static int page_widgets(fz_context *ctx, pdf_obj *annots, int *out, int capacity) {
    int count = 0;
    for (int i = 0, n = pdf_array_len(ctx, annots); i < n; i++) {
        pdf_obj *annot = pdf_array_get(ctx, annots, i);
        if (pdf_name_eq(ctx, pdf_dict_get(ctx, annot, PDF_NAME(Subtype)), PDF_NAME(Widget))) {
            if (count < capacity) out[count] = pdf_to_num(ctx, annot);
            count++;
        }
    }
    return count;
}

/* A page whose only change is in its comments: everything but /Annots the same, and the same
   widgets (form fields) in /Annots. */
static int page_changed_only_in_comments(fz_context *ctx, pdf_obj *old, pdf_obj *new) {
    if (!pdf_name_eq(ctx, pdf_dict_get(ctx, old, PDF_NAME(Type)), PDF_NAME(Page))) return 0;
    if (!pdf_name_eq(ctx, pdf_dict_get(ctx, new, PDF_NAME(Type)), PDF_NAME(Page))) return 0;
    for (int pass = 0; pass < 2; pass++) {
        pdf_obj *a = pass ? new : old, *b = pass ? old : new;
        for (int i = 0, n = pdf_dict_len(ctx, a); i < n; i++) {
            pdf_obj *key = pdf_dict_get_key(ctx, a, i);
            if (pdf_name_eq(ctx, key, PDF_NAME(Annots))) continue;
            pdf_obj *va = pdf_dict_get_val(ctx, a, i), *vb = pdf_dict_get(ctx, b, key);
            if (!vb || pdf_objcmp(ctx, va, vb)) return 0;
            // An indirect value must be the same object, not just the same number.
            if (pdf_is_indirect(ctx, va) != pdf_is_indirect(ctx, vb)) return 0;
        }
    }
    int old_widgets[64], new_widgets[64];
    int n_old = page_widgets(ctx, pdf_dict_get(ctx, old, PDF_NAME(Annots)), old_widgets, 64);
    int n_new = page_widgets(ctx, pdf_dict_get(ctx, new, PDF_NAME(Annots)), new_widgets, 64);
    if (n_old != n_new || n_old > 64) return 0;
    for (int i = 0; i < n_old; i++) if (old_widgets[i] != new_widgets[i]) return 0;
    return 1;
}

/* Whether stream `num` is an appearance of a comment, and not something a page draws: the
   appearance of one of the comments on the pages, in `version`. */
static int is_comment_appearance(fz_context *ctx, pdf_document *doc, int num, int version) {
    int base = doc->xref_base;
    int found = 0;
    doc->xref_base = version;
    fz_try(ctx) {
        for (int p = 0, n = pdf_count_pages(ctx, doc); p < n && found >= 0; p++) {
            pdf_obj *page = pdf_lookup_page_obj(ctx, doc, p);
            pdf_obj *contents = pdf_dict_get(ctx, page, PDF_NAME(Contents));
            if (pdf_to_num(ctx, contents) == num) { found = -1; break; }
            for (int i = 0, m = pdf_array_len(ctx, contents); i < m; i++)
                if (pdf_to_num(ctx, pdf_array_get(ctx, contents, i)) == num) { found = -1; break; }
            if (found < 0) break;
            pdf_obj *xobjects = pdf_dict_getp(ctx, page, "Resources/XObject");
            for (int i = 0, m = pdf_dict_len(ctx, xobjects); i < m; i++)
                if (pdf_to_num(ctx, pdf_dict_get_val(ctx, xobjects, i)) == num) { found = -1; break; }
            pdf_obj *annots = pdf_dict_get(ctx, page, PDF_NAME(Annots));
            for (int i = 0, m = pdf_array_len(ctx, annots); i < m && found == 0; i++) {
                pdf_obj *annot = pdf_array_get(ctx, annots, i);
                if (!is_comment(ctx, annot)) continue;
                pdf_obj *ap = pdf_dict_get(ctx, annot, PDF_NAME(AP));
                for (int k = 0, nk = pdf_dict_len(ctx, ap); k < nk && !found; k++) {
                    pdf_obj *entry = pdf_dict_get_val(ctx, ap, k);
                    if (pdf_to_num(ctx, entry) == num) found = 1;
                    else if (pdf_is_dict(ctx, entry) && !pdf_is_stream(ctx, entry))
                        for (int s = 0, ns = pdf_dict_len(ctx, entry); s < ns; s++)
                            if (pdf_to_num(ctx, pdf_dict_get_val(ctx, entry, s)) == num) found = 1;
                }
            }
        }
    } fz_always(ctx) {
        doc->xref_base = base;
    } fz_catch(ctx) {
        found = 0;
    }
    return found > 0;
}

/* Whether `num` is a page's /Annots array, kept apart from the page, in `version`. */
static int is_page_annots(fz_context *ctx, pdf_document *doc, int num, int version) {
    int base = doc->xref_base;
    int found = 0;
    doc->xref_base = version;
    fz_try(ctx) {
        for (int p = 0, n = pdf_count_pages(ctx, doc); p < n && !found; p++)
            found = pdf_to_num(ctx, pdf_dict_get(ctx, pdf_lookup_page_obj(ctx, doc, p), PDF_NAME(Annots))) == num;
    } fz_always(ctx) {
        doc->xref_base = base;
    } fz_catch(ctx) {
        found = 0;
    }
    return found;
}

static int version_changed_only_comments(fz_context *ctx, pdf_document *doc, int version) {
    if (version < 0 || version + 1 >= doc->num_xref_sections) return 0;
    pdf_xref *xref = &doc->xref_sections[version];
    pdf_obj *info = pdf_dict_get(ctx, xref->trailer, PDF_NAME(Info));
    pdf_obj *metadata = NULL;
    int ok = 1;
    pdf_obj *old = NULL, *new = NULL;
    fz_var(old);
    fz_var(new);
    fz_var(ok);
    fz_try(ctx) {
        pdf_obj *root = object_in_version(ctx, doc, pdf_to_num(ctx, pdf_dict_get(ctx, xref->trailer, PDF_NAME(Root))), version);
        metadata = pdf_dict_get(ctx, root, PDF_NAME(Metadata));
        int metadata_num = pdf_to_num(ctx, metadata);
        pdf_drop_obj(ctx, root);
        for (pdf_xref_subsec *sub = xref->subsec; sub && ok; sub = sub->next) {
            for (int i = 0; i < sub->len && ok; i++) {
                pdf_xref_entry *entry = &sub->table[i];
                int num = sub->start + i;
                if (num == 0 || entry->type == 0) continue;
                if (num == pdf_to_num(ctx, info) || num == metadata_num) continue;
                old = object_in_version(ctx, doc, num, version + 1);
                new = entry->type == 'f' ? NULL : object_in_version(ctx, doc, num, version);
                if (!old) {
                    // Made in this save: it matters only through what refers to it, checked here.
                    ok = 1;
                } else if (pdf_is_stream(ctx, new) && (pdf_name_eq(ctx, pdf_dict_get(ctx, new, PDF_NAME(Type)), PDF_NAME(ObjStm))
                                                   || pdf_name_eq(ctx, pdf_dict_get(ctx, new, PDF_NAME(Type)), PDF_NAME(XRef)))) {
                    ok = 1;
                } else if (is_comment(ctx, old)) {
                    ok = !new || is_comment(ctx, new);
                } else if (pdf_is_stream(ctx, old)) {
                    ok = is_comment_appearance(ctx, doc, num, version + 1) && (!new || is_comment_appearance(ctx, doc, num, version));
                } else if (new && pdf_is_dict(ctx, old)) {
                    ok = page_changed_only_in_comments(ctx, old, new);
                } else if (new && pdf_is_array(ctx, old) && pdf_is_array(ctx, new)) {
                    // A page's /Annots on its own: the same widgets, in the same page's.
                    int a[64], b[64];
                    int na = page_widgets(ctx, old, a, 64), nb = page_widgets(ctx, new, b, 64);
                    ok = na == nb && na <= 64 && is_page_annots(ctx, doc, num, version) && is_page_annots(ctx, doc, num, version + 1);
                    for (int k = 0; ok && k < na; k++) ok = a[k] == b[k];
                } else {
                    ok = 0;
                }
                pdf_drop_obj(ctx, old); old = NULL;
                pdf_drop_obj(ctx, new); new = NULL;
            }
        }
    } fz_always(ctx) {
        pdf_drop_obj(ctx, old);
        pdf_drop_obj(ctx, new);
    } fz_catch(ctx) {
        fz_report_error(ctx);
        ok = 0;
    }
    return ok;
}

/* Whether every save after the signature was one MuPDF accepted (before the one `broken` saves
   ago that it didn't) or one that changed only comments. */
static int later_changes_only_comments(fz_context *ctx, pdf_document *doc, pdf_obj *field, int broken) {
    int signed_in = pdf_find_version_for_obj(ctx, doc, field);
    int unsaved = pdf_count_unsaved_versions(ctx, doc);
    for (int v = signed_in - 1; v >= unsaved; v--) {
        if (v - unsaved >= broken) continue;  // MuPDF passed it
        if (!version_changed_only_comments(ctx, doc, v)) return 0;
    }
    return 1;
}

// Adds the signed signature fields under `field` (a field and its kids) to `out`.
static void add_signatures(fz_context *ctx, pdf_document *doc, pdf_obj *field, int depth, int *out, int capacity, int *count) {
    if (depth > 32 || !pdf_is_dict(ctx, field) || pdf_mark_obj(ctx, field)) return;
    fz_try(ctx) {
        pdf_obj *kids = pdf_dict_get(ctx, field, PDF_NAME(Kids));
        int n = pdf_array_len(ctx, kids);
        // A field with a name of its own among its kids is a field; without, a widget of this one.
        int has_child_fields = 0;
        for (int i = 0; i < n && !has_child_fields; i++)
            has_child_fields = pdf_dict_get(ctx, pdf_array_get(ctx, kids, i), PDF_NAME(T)) != NULL;
        if (has_child_fields) {
            for (int i = 0; i < n; i++)
                add_signatures(ctx, doc, pdf_array_get(ctx, kids, i), depth + 1, out, capacity, count);
        } else if (pdf_name_eq(ctx, pdf_dict_get_inheritable(ctx, field, PDF_NAME(FT)), PDF_NAME(Sig))
                   && pdf_signature_is_signed(ctx, doc, field)) {
            pdf_obj *widget = n > 0 ? pdf_array_get(ctx, kids, 0) : field;
            if (out && *count < capacity) out[*count] = pdf_to_num(ctx, widget);
            (*count)++;
        }
    } fz_always(ctx) {
        pdf_unmark_obj(ctx, field);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
}

int mupdf_pdf_list_signatures(fz_context *ctx, fz_document *doc, int *out, int capacity) {
    if (!ctx || !doc) return -1;
    int count = 0;
    fz_var(count);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (pdoc) {
            pdf_obj *fields = pdf_dict_getp(ctx, pdf_trailer(ctx, pdoc), "Root/AcroForm/Fields");
            for (int i = 0, n = pdf_array_len(ctx, fields); i < n; i++)
                add_signatures(ctx, pdoc, pdf_array_get(ctx, fields, i), 0, out, capacity, &count);
        }
    } fz_catch(ctx) {
        fz_report_error(ctx);
        return -1;
    }
    return count;
}

int mupdf_pdf_signature_data(fz_context *ctx, fz_document *doc, int objnum, mupdf_signature_data *out, const char **out_error) {
    if (!ctx || !doc || !out) return -1;
    memset(out, 0, sizeof *out);
    pdf_obj *field = NULL;
    fz_range *ranges = NULL;
    char *name = NULL;
    fz_var(field);
    fz_var(ranges);
    fz_var(name);
    fz_try(ctx) {
        pdf_document *pdoc = pdf_document_from_fz_document(ctx, doc);
        if (!pdoc) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Document is not a PDF");
        field = pdf_new_indirect(ctx, pdoc, objnum, 0);
        if (!pdf_signature_is_signed(ctx, pdoc, field)) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Not a signed signature field");
        pdf_obj *sig = pdf_dict_get_inheritable(ctx, field, PDF_NAME(V));
        copy_text(out->subfilter, sizeof out->subfilter, pdf_to_name(ctx, pdf_dict_get(ctx, sig, PDF_NAME(SubFilter))));
        int n = pdf_signature_byte_range(ctx, pdoc, field, NULL);
        if (n > 0) {
            ranges = fz_malloc_array(ctx, n, fz_range);
            pdf_signature_byte_range(ctx, pdoc, field, ranges);
            out->range_count = n < MUPDF_SIGNATURE_MAX_RANGES ? n : MUPDF_SIGNATURE_MAX_RANGES;
            for (int i = 0; i < out->range_count; i++) {
                out->range_offset[i] = ranges[i].offset;
                out->range_length[i] = (int64_t)ranges[i].length;
            }
            out->has_more_ranges = n > MUPDF_SIGNATURE_MAX_RANGES;
        }
        char *contents = NULL;
        out->contents_length = pdf_signature_contents(ctx, pdoc, field, &contents);
        out->contents = (unsigned char *)contents;
        copy_text(out->signer, sizeof out->signer, pdf_dict_get_text_string(ctx, sig, PDF_NAME(Name)));
        copy_text(out->reason, sizeof out->reason, pdf_dict_get_text_string(ctx, sig, PDF_NAME(Reason)));
        copy_text(out->location, sizeof out->location, pdf_dict_get_text_string(ctx, sig, PDF_NAME(Location)));
        name = pdf_load_field_name(ctx, field);
        copy_text(out->field_name, sizeof out->field_name, name);
        out->page = -1;
        pdf_obj *page_obj = pdf_dict_get(ctx, field, PDF_NAME(P));
        if (page_obj) {
            fz_try(ctx) {
                out->page = pdf_lookup_page_number(ctx, pdoc, page_obj);
                if (out->page >= 0) {
                    fz_matrix ctm;
                    pdf_page_obj_transform(ctx, page_obj, NULL, &ctm);
                    fz_rect r = fz_transform_rect(pdf_dict_get_rect(ctx, field, PDF_NAME(Rect)), ctm);
                    out->x0 = r.x0; out->y0 = r.y0; out->x1 = r.x1; out->y1 = r.y1;
                }
            } fz_catch(ctx) {
                fz_report_error(ctx);
                out->page = -1;
            }
        }
        out->later_changes = -2;
        fz_try(ctx) {
            out->later_changes = pdf_validate_signature(ctx, pdoc, field);
            int level = certification_level(ctx, sig);
            if (out->later_changes > 0 && level != 1 && level != 2 && !pdf_dict_get(ctx, sig, PDF_NAME(Lock))
                && !pdf_dict_get(ctx, field, PDF_NAME(Lock)))
                out->later_changes_only_comments = later_changes_only_comments(ctx, pdoc, field, out->later_changes);
        } fz_catch(ctx) {
            fz_report_error(ctx);
        }
    } fz_always(ctx) {
        fz_free(ctx, ranges);
        fz_free(ctx, name);
        pdf_drop_obj(ctx, field);
    } fz_catch(ctx) {
        if (out->contents) { fz_free(ctx, out->contents); out->contents = NULL; }
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

void mupdf_pdf_free_signature_data(fz_context *ctx, mupdf_signature_data *data) {
    if (ctx && data && data->contents) {
        fz_free(ctx, data->contents);
        data->contents = NULL;
    }
}

