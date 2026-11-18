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

// Editing the outline (bookmarks) through MuPDF's outline iterator, which keeps what it doesn't
// change of an entry: its colour, style, and an action other than going to a page. An entry is
// found by its path: its index among its siblings at each level, from the top.

#include "MuPDFBridge.h"
#include <string.h>

// Moves `iter` to `path`. With `allow_end`, the last index may be one past the last entry there
// (or 0 under an entry with none), a place to insert at. Throws if there's nothing there.
static void go_to(fz_context *ctx, fz_outline_iterator *iter, const int *path, int depth, int allow_end) {
    if (depth < 1) fz_throw(ctx, FZ_ERROR_ARGUMENT, "No outline entry given");
    for (int level = 0; level < depth; level++) {
        if (level > 0 && fz_outline_iterator_down(ctx, iter) < 0)
            fz_throw(ctx, FZ_ERROR_ARGUMENT, "No such outline entry");
        for (int i = 0; i < path[level]; i++) {
            if (fz_outline_iterator_next(ctx, iter) < 0)
                fz_throw(ctx, FZ_ERROR_ARGUMENT, "No such outline entry");
        }
        int at_item = fz_outline_iterator_item(ctx, iter) != NULL;
        int is_last = level == depth - 1;
        if (!at_item && !(is_last && allow_end))
            fz_throw(ctx, FZ_ERROR_ARGUMENT, "No such outline entry");
    }
}

static fz_outline_iterator *new_iterator(fz_context *ctx, fz_document *doc) {
    fz_outline_iterator *iter = fz_new_outline_iterator(ctx, doc);
    if (!iter) fz_throw(ctx, FZ_ERROR_ARGUMENT, "This document's outline can't be edited");
    return iter;
}

char *mupdf_outline_page_uri(fz_context *ctx, fz_document *doc, int page, float y) {
    if (!ctx || !doc) return NULL;
    char *uri = NULL;
    fz_try(ctx)
        uri = fz_format_link_uri(ctx, doc, fz_make_link_dest_xyz(0, page, 0, y, 0));
    fz_catch(ctx) {
        fz_report_error(ctx);
        uri = NULL;
    }
    return uri;
}

int mupdf_outline_insert(fz_context *ctx, fz_document *doc, const int *path, int depth, const char *title, const char *uri, const char **out_error) {
    if (!ctx || !doc || !title) return -1;
    fz_outline_iterator *iter = NULL;
    fz_var(iter);
    fz_try(ctx) {
        iter = new_iterator(ctx, doc);
        go_to(ctx, iter, path, depth, 1);
        fz_outline_item item = { (char *)title, (char *)uri, 0, 0, 0, 0, 0 };
        fz_outline_iterator_insert(ctx, iter, &item);
    } fz_always(ctx) {
        fz_drop_outline_iterator(ctx, iter);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_outline_update(fz_context *ctx, fz_document *doc, const int *path, int depth, const char *title, const char *uri, const char **out_error) {
    if (!ctx || !doc) return -1;
    fz_outline_iterator *iter = NULL;
    char *old_title = NULL, *old_uri = NULL;
    fz_var(iter);
    fz_var(old_title);
    fz_var(old_uri);
    fz_try(ctx) {
        iter = new_iterator(ctx, doc);
        go_to(ctx, iter, path, depth, 0);
        fz_outline_item *current = fz_outline_iterator_item(ctx, iter);
        old_title = current->title ? fz_strdup(ctx, current->title) : NULL;
        old_uri = current->uri ? fz_strdup(ctx, current->uri) : NULL;
        fz_outline_item item = *current;
        item.title = title ? (char *)title : old_title;
        item.uri = uri ? (char *)uri : old_uri;
        fz_outline_iterator_update(ctx, iter, &item);
    } fz_always(ctx) {
        fz_free(ctx, old_title);
        fz_free(ctx, old_uri);
        fz_drop_outline_iterator(ctx, iter);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

// An entry and those under it, copied out of the outline to put back elsewhere.
typedef struct copied_entry {
    fz_outline_item item;
    struct copied_entry *children;
    struct copied_entry *next;
} copied_entry;

static void drop_copy(fz_context *ctx, copied_entry *entry) {
    while (entry) {
        copied_entry *next = entry->next;
        drop_copy(ctx, entry->children);
        fz_free(ctx, entry->item.title);
        fz_free(ctx, entry->item.uri);
        fz_free(ctx, entry);
        entry = next;
    }
}

// Copies the entry `iter` is at, with those under it; leaves `iter` where it was.
static copied_entry *copy_entry(fz_context *ctx, fz_outline_iterator *iter, int depth) {
    if (depth > 64) fz_throw(ctx, FZ_ERROR_LIMIT, "The outline is nested too deeply");
    fz_outline_item *item = fz_outline_iterator_item(ctx, iter);
    if (!item) return NULL;
    copied_entry *copy = fz_malloc_struct(ctx, copied_entry);
    fz_try(ctx) {
        copy->item = *item;
        copy->item.title = item->title ? fz_strdup(ctx, item->title) : NULL;
        copy->item.uri = NULL;
        copy->item.uri = item->uri ? fz_strdup(ctx, item->uri) : NULL;
        if (fz_outline_iterator_down(ctx, iter) == 0) {
            copied_entry **tail = &copy->children;
            do {
                *tail = copy_entry(ctx, iter, depth + 1);
                if (*tail) tail = &(*tail)->next;
            } while (fz_outline_iterator_next(ctx, iter) == 0);
            fz_outline_iterator_up(ctx, iter);
        } else if (fz_outline_iterator_item(ctx, iter) == NULL) {
            // Down to an empty place under a childless entry: back up to it.
            fz_outline_iterator_up(ctx, iter);
        }
    } fz_catch(ctx) {
        drop_copy(ctx, copy);
        fz_rethrow(ctx);
    }
    return copy;
}

// Inserts `entries` before where `iter` is, with those under each; leaves `iter` where it was.
static void insert_copy(fz_context *ctx, fz_outline_iterator *iter, copied_entry *entries) {
    for (copied_entry *entry = entries; entry; entry = entry->next) {
        fz_outline_iterator_insert(ctx, iter, &entry->item);
        if (entry->children) {
            // To the entry just inserted, into it, and back.
            fz_outline_iterator_prev(ctx, iter);
            fz_outline_iterator_down(ctx, iter);
            insert_copy(ctx, iter, entry->children);
            fz_outline_iterator_up(ctx, iter);
            fz_outline_iterator_update(ctx, iter, &entry->item);  // its open state, now it has children
            fz_outline_iterator_next(ctx, iter);
        }
    }
}

int mupdf_outline_delete(fz_context *ctx, fz_document *doc, const int *path, int depth, const char **out_error) {
    if (!ctx || !doc) return -1;
    fz_outline_iterator *iter = NULL;
    fz_var(iter);
    fz_try(ctx) {
        iter = new_iterator(ctx, doc);
        go_to(ctx, iter, path, depth, 0);
        fz_outline_iterator_delete(ctx, iter);
    } fz_always(ctx) {
        fz_drop_outline_iterator(ctx, iter);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

int mupdf_outline_move(fz_context *ctx, fz_document *doc, const int *from, int from_depth, const int *to, int to_depth, const char **out_error) {
    if (!ctx || !doc) return -1;
    fz_outline_iterator *iter = NULL;
    copied_entry *copy = NULL;
    fz_var(iter);
    fz_var(copy);
    fz_try(ctx) {
        iter = new_iterator(ctx, doc);
        go_to(ctx, iter, from, from_depth, 0);
        copy = copy_entry(ctx, iter, 0);
        fz_outline_iterator_delete(ctx, iter);
        fz_drop_outline_iterator(ctx, iter);
        iter = NULL;
        // `to` is a place in the outline as it is without the entry.
        iter = new_iterator(ctx, doc);
        go_to(ctx, iter, to, to_depth, 1);
        insert_copy(ctx, iter, copy);
    } fz_always(ctx) {
        drop_copy(ctx, copy);
        fz_drop_outline_iterator(ctx, iter);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}
