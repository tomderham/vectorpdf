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

// Signing with a certificate: a pdf_pkcs7_signer whose signature comes from the app (the
// Security framework's CMS encoder), not OpenSSL. MuPDF reserves room for it when a field is
// signed, then, as the document is saved, hands the signer the bytes the signature covers.

#include "MuPDFBridge.h"
#include <string.h>
#include <time.h>

typedef struct {
    pdf_pkcs7_signer base;
    int refs;
    vp_signer_callbacks callbacks;
    char *cn, *o, *ou, *email, *c;
    size_t max_size;
} vp_signer;

static pdf_pkcs7_signer *signer_keep(fz_context *ctx, pdf_pkcs7_signer *signer) {
    ((vp_signer *)signer)->refs++;
    return signer;
}

static void signer_drop(fz_context *ctx, pdf_pkcs7_signer *signer) {
    vp_signer *s = (vp_signer *)signer;
    if (!s || --s->refs > 0) return;
    if (s->callbacks.release) s->callbacks.release(s->callbacks.context);
    fz_free(ctx, s->cn);
    fz_free(ctx, s->o);
    fz_free(ctx, s->ou);
    fz_free(ctx, s->email);
    fz_free(ctx, s->c);
    fz_free(ctx, s);
}

static char *dup_or_null(fz_context *ctx, const char *s) { return s ? fz_strdup(ctx, s) : NULL; }

static pdf_pkcs7_distinguished_name *signer_name(fz_context *ctx, pdf_pkcs7_signer *signer) {
    vp_signer *s = (vp_signer *)signer;
    pdf_pkcs7_distinguished_name *dn = fz_malloc_struct(ctx, pdf_pkcs7_distinguished_name);
    fz_try(ctx) {
        dn->cn = dup_or_null(ctx, s->cn);
        dn->o = dup_or_null(ctx, s->o);
        dn->ou = dup_or_null(ctx, s->ou);
        dn->email = dup_or_null(ctx, s->email);
        dn->c = dup_or_null(ctx, s->c);
    } fz_catch(ctx) {
        pdf_signature_drop_distinguished_name(ctx, dn);
        fz_rethrow(ctx);
    }
    return dn;
}

static size_t signer_max_size(fz_context *ctx, pdf_pkcs7_signer *signer) {
    return ((vp_signer *)signer)->max_size;
}

static int signer_create_digest(fz_context *ctx, pdf_pkcs7_signer *signer, fz_stream *in, unsigned char *digest, size_t digest_len) {
    vp_signer *s = (vp_signer *)signer;
    if (s->callbacks.begin(s->callbacks.context) != 0)
        fz_throw(ctx, FZ_ERROR_GENERIC, "The signature couldn't be started");
    unsigned char buf[65536];
    size_t n;
    while (in && (n = fz_read(ctx, in, buf, sizeof buf)) > 0) {
        if (s->callbacks.update(s->callbacks.context, buf, n) != 0)
            fz_throw(ctx, FZ_ERROR_GENERIC, "The signature couldn't be made");
    }
    size_t len = s->callbacks.finish(s->callbacks.context, digest, digest_len);
    if (len == 0)
        fz_throw(ctx, FZ_ERROR_GENERIC, "The signature couldn't be made");
    return (int)len;
}

pdf_pkcs7_signer *mupdf_new_signer(fz_context *ctx, vp_signer_callbacks callbacks, const char *cn, const char *o, const char *ou, const char *email, const char *c, size_t max_size) {
    if (!ctx || !callbacks.begin || !callbacks.update || !callbacks.finish) return NULL;
    vp_signer *s = NULL;
    fz_var(s);
    fz_try(ctx) {
        s = fz_malloc_struct(ctx, vp_signer);
        s->refs = 1;
        s->base.keep = signer_keep;
        s->base.drop = signer_drop;
        s->base.get_signing_name = signer_name;
        s->base.max_digest_size = signer_max_size;
        s->base.create_digest = signer_create_digest;
        s->max_size = max_size;
        s->cn = dup_or_null(ctx, cn);
        s->o = dup_or_null(ctx, o);
        s->ou = dup_or_null(ctx, ou);
        s->email = dup_or_null(ctx, email);
        s->c = dup_or_null(ctx, c);
        s->callbacks = callbacks;
    } fz_catch(ctx) {
        if (s) {
            s->callbacks.release = NULL;  // the caller still owns its context
            signer_drop(ctx, &s->base);
        }
        fz_report_error(ctx);
        return NULL;
    }
    return &s->base;
}

void mupdf_drop_signer(fz_context *ctx, pdf_pkcs7_signer *signer) {
    if (ctx && signer) signer->drop(ctx, signer);
}

// A field name not used yet: Signature1, Signature2, …
static void unused_field_name(fz_context *ctx, pdf_document *doc, char *name, size_t cap) {
    pdf_obj *fields = pdf_dict_getp(ctx, pdf_trailer(ctx, doc), "Root/AcroForm/Fields");
    for (int i = 1; i < 10000; i++) {
        fz_snprintf(name, cap, "Signature%d", i);
        if (!fields || !pdf_lookup_field(ctx, fields, name)) return;
    }
    fz_throw(ctx, FZ_ERROR_LIMIT, "Too many signature fields");
}

static int name_in(fz_context *ctx, pdf_obj *names, const char *name) {
    for (int i = 0, n = pdf_array_len(ctx, names); i < n; i++)
        if (!strcmp(pdf_array_get_text_string(ctx, names, i), name)) return 1;
    return 0;
}

// Makes the fields a signature field's /Lock names read-only: all of them, those listed
// (Include), or all but those (Exclude). Not the signature field itself.
static void lock_fields(fz_context *ctx, pdf_obj *fields, pdf_obj *signature, pdf_obj *action, pdf_obj *names, int depth) {
    if (depth > 32) return;
    for (int i = 0, n = pdf_array_len(ctx, fields); i < n; i++) {
        pdf_obj *field = pdf_array_get(ctx, fields, i);
        pdf_obj *kids = pdf_dict_get(ctx, field, PDF_NAME(Kids));
        if (kids && pdf_dict_get(ctx, pdf_array_get(ctx, kids, 0), PDF_NAME(T))) {
            lock_fields(ctx, kids, signature, action, names, depth + 1);
            continue;
        }
        if (pdf_objcmp(ctx, field, signature) == 0) continue;
        char *name = pdf_load_field_name(ctx, field);
        int listed = name_in(ctx, names, name);
        fz_free(ctx, name);
        int lock = pdf_name_eq(ctx, action, PDF_NAME(All)) || (pdf_name_eq(ctx, action, PDF_NAME(Include)) && listed)
            || (pdf_name_eq(ctx, action, PDF_NAME(Exclude)) && !listed);
        if (lock) pdf_dict_put_int(ctx, field, PDF_NAME(Ff), pdf_field_flags(ctx, field) | PDF_FIELD_IS_READ_ONLY);
    }
}

// Signs `widget` as pdf_sign_signature does, but with the signer's name, the reason and the
// location in the signature dictionary too (as Acrobat writes them): MuPDF writes them only in
// the appearance, and anything changed once a signature is recorded is saved after it.
static void sign_widget(fz_context *ctx, pdf_document *doc, pdf_annot *widget, pdf_pkcs7_signer *signer, fz_image *graphic,
                        const char *reason, const char *location, int flags) {
    pdf_obj *field = pdf_annot_obj(ctx, widget);
    if (pdf_widget_is_readonly(ctx, widget)) fz_throw(ctx, FZ_ERROR_ARGUMENT, "The signature field is read-only");
    int64_t now = time(NULL);
    pdf_pkcs7_distinguished_name *dn = NULL;
    fz_display_list *list = NULL;
    char *info = NULL;
    char *zeros = NULL;
    pdf_obj *v = NULL;
    fz_var(dn);
    fz_var(list);
    fz_var(info);
    fz_var(zeros);
    fz_var(v);
    fz_try(ctx) {
        dn = signer->get_signing_name(ctx, signer);
        const char *name = dn && dn->cn ? dn->cn : NULL;

        // Its appearance: the graphic or the name on the left, the text on the right.
        fz_rect rect = pdf_annot_rect(ctx, widget);
        if (!fz_is_empty_rect(rect)) {
            info = pdf_signature_info(ctx, (flags & PDF_SIGNATURE_SHOW_TEXT_NAME) ? name : NULL, NULL, reason, location,
                                      (flags & PDF_SIGNATURE_SHOW_DATE) ? now : -1, (flags & PDF_SIGNATURE_SHOW_LABELS) ? 1 : 0);
            list = pdf_signature_appearance_signed(ctx, rect, pdf_annot_language(ctx, widget), graphic,
                                                   graphic ? NULL : ((flags & PDF_SIGNATURE_SHOW_GRAPHIC_NAME) ? name : NULL), info, 0);
            pdf_set_annot_appearance_from_display_list(ctx, widget, "N", NULL, fz_identity, list);
        }
        pdf_dirty_annot(ctx, widget);

        pdf_obj *root = pdf_dict_get(ctx, pdf_trailer(ctx, doc), PDF_NAME(Root));
        pdf_obj *form = pdf_dict_get(ctx, root, PDF_NAME(AcroForm));
        if (!form) form = pdf_dict_put_dict(ctx, root, PDF_NAME(AcroForm), 1);
        int sigflags = pdf_dict_get_int(ctx, form, PDF_NAME(SigFlags));
        // SignaturesExist and AppendOnly; only if not set, as a change to the form after an
        // earlier signature would break it.
        if ((sigflags & 3) != 3) pdf_dict_put_int(ctx, form, PDF_NAME(SigFlags), sigflags | 3);

        pdf_obj *lock = pdf_dict_get(ctx, field, PDF_NAME(Lock));
        pdf_obj *action = pdf_dict_get(ctx, lock, PDF_NAME(Action));
        pdf_obj *names = pdf_dict_get(ctx, lock, PDF_NAME(Fields));
        if (action) lock_fields(ctx, pdf_dict_get(ctx, form, PDF_NAME(Fields)), field, action, names, 0);

        // The signature dictionary, with room for the signature. ByteRange, Contents and Filter
        // come first, in that order: saving finds them so, to fill them in.
        size_t size = signer->max_digest_size(ctx, signer);
        v = pdf_add_new_dict(ctx, doc, 10);
        pdf_dict_put(ctx, field, PDF_NAME(V), v);
        pdf_dict_put_array(ctx, v, PDF_NAME(ByteRange), 4);
        zeros = fz_calloc(ctx, size, 1);
        pdf_dict_put_string(ctx, v, PDF_NAME(Contents), zeros, size);
        pdf_dict_put(ctx, v, PDF_NAME(Filter), PDF_NAME(Adobe_PPKLite));
        pdf_dict_put(ctx, v, PDF_NAME(SubFilter), PDF_NAME(adbe_pkcs7_detached));
        pdf_dict_put(ctx, v, PDF_NAME(Type), PDF_NAME(Sig));
        pdf_dict_put_date(ctx, v, PDF_NAME(M), now);
        if (name) pdf_dict_put_text_string(ctx, v, PDF_NAME(Name), name);
        if (reason && *reason) pdf_dict_put_text_string(ctx, v, PDF_NAME(Reason), reason);
        if (location && *location) pdf_dict_put_text_string(ctx, v, PDF_NAME(Location), location);
        if (action) {
            // Which fields it locks, for readers to check later changes against.
            pdf_obj *reference = pdf_dict_put_array(ctx, v, PDF_NAME(Reference), 1);
            pdf_obj *sigref = pdf_array_push_dict(ctx, reference, 4);
            pdf_dict_put(ctx, sigref, PDF_NAME(Type), PDF_NAME(SigRef));
            pdf_dict_put(ctx, sigref, PDF_NAME(TransformMethod), PDF_NAME(FieldMDP));
            pdf_dict_put(ctx, sigref, PDF_NAME(Data), root);
            pdf_obj *params = pdf_dict_put_dict(ctx, sigref, PDF_NAME(TransformParams), 3);
            pdf_dict_put(ctx, params, PDF_NAME(Type), PDF_NAME(TransformParams));
            pdf_dict_put(ctx, params, PDF_NAME(Action), action);
            if (names) pdf_dict_put_drop(ctx, params, PDF_NAME(Fields), pdf_copy_array(ctx, names));
            pdf_dict_put(ctx, params, PDF_NAME(V), PDF_NAME(1_2));
        }
        // Saving makes the signature over the file as written.
        pdf_xref_store_unsaved_signature(ctx, doc, field, signer);
    } fz_always(ctx) {
        pdf_drop_obj(ctx, v);
        fz_free(ctx, zeros);
        fz_free(ctx, info);
        fz_drop_display_list(ctx, list);
        pdf_signature_drop_distinguished_name(ctx, dn);
    } fz_catch(ctx) {
        fz_rethrow(ctx);
    }
}

int mupdf_pdf_sign(fz_context *ctx, fz_document *doc, int pageno, int widget_index, fz_rect rect, pdf_pkcs7_signer *signer,
                   const unsigned char *graphic_png, size_t graphic_len, const char *reason, const char *location, int flags,
                   const char **out_error) {
    if (!ctx || !doc || !signer) return -1;
    pdf_page *page = NULL;
    fz_image *graphic = NULL;
    fz_buffer *buf = NULL;
    fz_var(page);
    fz_var(graphic);
    fz_var(buf);
    fz_try(ctx) {
        pdf_document *pdf = pdf_document_from_fz_document(ctx, doc);
        if (!pdf) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Only a PDF can be signed");
        // The form as an object of its own, while nothing is signed: within the catalog, adding
        // a later signature's field changes the catalog, which checks of the earlier one reject.
        pdf_obj *root = pdf_dict_get(ctx, pdf_trailer(ctx, pdf), PDF_NAME(Root));
        pdf_obj *form = pdf_dict_get(ctx, root, PDF_NAME(AcroForm));
        if (pdf_count_signatures(ctx, pdf) == 0 && !pdf_is_indirect(ctx, form)) {
            pdf_obj *indirect = pdf_add_object_drop(ctx, pdf, form ? pdf_copy_dict(ctx, form) : pdf_new_dict(ctx, pdf, 2));
            pdf_dict_put_drop(ctx, root, PDF_NAME(AcroForm), indirect);
            if (!pdf_dict_get(ctx, indirect, PDF_NAME(Fields))) pdf_dict_put_array(ctx, indirect, PDF_NAME(Fields), 1);
        }
        page = pdf_load_page(ctx, pdf, pageno);
        pdf_annot *widget = NULL;
        if (widget_index >= 0) {
            widget = pdf_first_widget(ctx, page);
            for (int i = 0; widget && i < widget_index; i++) widget = pdf_next_widget(ctx, widget);
            if (!widget || pdf_widget_type(ctx, widget) != PDF_WIDGET_TYPE_SIGNATURE)
                fz_throw(ctx, FZ_ERROR_ARGUMENT, "That isn't a signature field");
            if (pdf_widget_is_signed(ctx, widget))
                fz_throw(ctx, FZ_ERROR_ARGUMENT, "That field is signed already");
        } else {
            char name[32];
            unused_field_name(ctx, pdf, name, sizeof name);
            widget = pdf_create_signature_widget(ctx, page, name);
            pdf_set_annot_rect(ctx, widget, rect);
            pdf_obj *obj = pdf_annot_obj(ctx, widget);
            // The page it's on, which readers (and the Document tab) look for.
            pdf_dict_put(ctx, obj, PDF_NAME(P), page->obj);
            // No lock on the form's other fields, as Acrobat signs by default: MuPDF gives a new
            // field one on all of them.
            pdf_dict_del(ctx, obj, PDF_NAME(Lock));
        }
        if (graphic_png && graphic_len > 0) {
            buf = fz_new_buffer_from_copied_data(ctx, graphic_png, graphic_len);
            graphic = fz_new_image_from_buffer(ctx, buf);
        }
        sign_widget(ctx, pdf, widget, signer, graphic, reason, location, flags);
    } fz_always(ctx) {
        fz_drop_image(ctx, graphic);
        fz_drop_buffer(ctx, buf);
        fz_drop_page(ctx, (fz_page *)page);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_page_widget_is_signed(fz_context *ctx, fz_document *doc, int pageno, int widget_index) {
    if (!ctx || !doc) return 0;
    pdf_page *page = NULL;
    int is_signed = 0;
    fz_var(page);
    fz_var(is_signed);
    fz_try(ctx) {
        pdf_document *pdf = pdf_document_from_fz_document(ctx, doc);
        if (pdf) {
            page = pdf_load_page(ctx, pdf, pageno);
            pdf_annot *widget = pdf_first_widget(ctx, page);
            for (int i = 0; widget && i < widget_index; i++) widget = pdf_next_widget(ctx, widget);
            is_signed = widget && pdf_widget_type(ctx, widget) == PDF_WIDGET_TYPE_SIGNATURE && pdf_widget_is_signed(ctx, widget);
        }
    } fz_always(ctx) {
        fz_drop_page(ctx, (fz_page *)page);
    } fz_catch(ctx) {
        fz_report_error(ctx);
        is_signed = 0;
    }
    return is_signed;
}
