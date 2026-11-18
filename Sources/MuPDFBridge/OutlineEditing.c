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
#include "TextClipFilter.h"
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

// MARK: Copies for Undo: an entry and those under it as a flat list, each with its level.

static int count_copy(copied_entry *entry) {
    int n = 0;
    for (; entry; entry = entry->next) n += 1 + count_copy(entry->children);
    return n;
}

// Moves the strings of `entry` and those under it into `out` from `*at`, leaving them NULL.
static void flatten_copy(copied_entry *entry, int level, vp_outline_entry *out, int *at) {
    for (; entry; entry = entry->next) {
        vp_outline_entry *e = &out[(*at)++];
        e->level = level;
        e->title = entry->item.title;
        e->uri = entry->item.uri;
        e->is_open = entry->item.is_open;
        e->flags = entry->item.flags;
        e->r = entry->item.r;
        e->g = entry->item.g;
        e->b = entry->item.b;
        entry->item.title = NULL;
        entry->item.uri = NULL;
        flatten_copy(entry->children, level + 1, out, at);
    }
}

// Builds entries from `list[*at]` on that are at `level`, with those under each.
static copied_entry *unflatten(fz_context *ctx, const vp_outline_entry *list, int count, int *at, int level) {
    copied_entry *first = NULL, **tail = &first;
    fz_try(ctx) {
        while (*at < count && list[*at].level == level) {
            const vp_outline_entry *e = &list[(*at)++];
            copied_entry *entry = fz_malloc_struct(ctx, copied_entry);
            *tail = entry;
            tail = &entry->next;
            entry->item.title = e->title ? fz_strdup(ctx, e->title) : NULL;
            entry->item.uri = e->uri ? fz_strdup(ctx, e->uri) : NULL;
            entry->item.is_open = e->is_open;
            entry->item.flags = e->flags;
            entry->item.r = e->r;
            entry->item.g = e->g;
            entry->item.b = e->b;
            if (*at < count && list[*at].level > level) {
                if (list[*at].level != level + 1) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Outline entries skip a level");
                entry->children = unflatten(ctx, list, count, at, level + 1);
            }
        }
    } fz_catch(ctx) {
        drop_copy(ctx, first);
        fz_rethrow(ctx);
    }
    return first;
}

int mupdf_outline_copy(fz_context *ctx, fz_document *doc, const int *path, int depth, vp_outline_entry **out, int *out_count, const char **out_error) {
    if (!ctx || !doc || !out || !out_count) return -1;
    *out = NULL;
    *out_count = 0;
    fz_outline_iterator *iter = NULL;
    copied_entry *copy = NULL;
    fz_var(iter);
    fz_var(copy);
    fz_try(ctx) {
        iter = new_iterator(ctx, doc);
        go_to(ctx, iter, path, depth, 0);
        copy = copy_entry(ctx, iter, 0);
        int n = count_copy(copy);
        *out = fz_malloc_array(ctx, n, vp_outline_entry);
        int at = 0;
        flatten_copy(copy, 0, *out, &at);
        *out_count = n;
    } fz_always(ctx) {
        drop_copy(ctx, copy);
        fz_drop_outline_iterator(ctx, iter);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

void mupdf_outline_entries_free(fz_context *ctx, vp_outline_entry *entries, int count) {
    if (!ctx || !entries) return;
    for (int i = 0; i < count; i++) {
        fz_free(ctx, entries[i].title);
        fz_free(ctx, entries[i].uri);
    }
    fz_free(ctx, entries);
}

int mupdf_outline_insert_entries(fz_context *ctx, fz_document *doc, const int *path, int depth, const vp_outline_entry *entries, int count, const char **out_error) {
    if (!ctx || !doc || !entries || count < 1) return -1;
    fz_outline_iterator *iter = NULL;
    copied_entry *copy = NULL;
    fz_var(iter);
    fz_var(copy);
    fz_try(ctx) {
        int at = 0;
        copy = unflatten(ctx, entries, count, &at, entries[0].level);
        if (at != count) fz_throw(ctx, FZ_ERROR_ARGUMENT, "Outline entries out of order");
        iter = new_iterator(ctx, doc);
        go_to(ctx, iter, path, depth, 1);
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

int mupdf_outline_set(fz_context *ctx, fz_document *doc, const int *path, int depth, const vp_outline_entry *entry, const char **out_error) {
    if (!ctx || !doc || !entry) return -1;
    fz_outline_iterator *iter = NULL;
    fz_var(iter);
    fz_try(ctx) {
        iter = new_iterator(ctx, doc);
        go_to(ctx, iter, path, depth, 0);
        fz_outline_item item = { entry->title, entry->uri, entry->is_open, entry->flags, entry->r, entry->g, entry->b };
        fz_outline_iterator_update(ctx, iter, &item);
    } fz_always(ctx) {
        fz_drop_outline_iterator(ctx, iter);
    } fz_catch(ctx) {
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

// MARK: Headings from a tagged PDF's structure (H, H1–H6)

int mupdf_pdf_is_tagged(fz_context *ctx, fz_document *doc) {
    pdf_document *pdf = pdf_specifics(ctx, doc);
    if (!pdf) return 0;
    int tagged = 0;
    fz_try(ctx)
        tagged = pdf_dict_get(ctx, pdf_dict_get(ctx, pdf_trailer(ctx, pdf), PDF_NAME(Root)), PDF_NAME(StructTreeRoot)) != NULL;
    fz_catch(ctx) {
        fz_report_error(ctx);
        tagged = 0;
    }
    return tagged;
}

static int heading_level(fz_structure standard) {
    switch (standard) {
    case FZ_STRUCTURE_H: return 0;
    case FZ_STRUCTURE_H1: return 1;
    case FZ_STRUCTURE_H2: return 2;
    case FZ_STRUCTURE_H3: return 3;
    case FZ_STRUCTURE_H4: return 4;
    case FZ_STRUCTURE_H5: return 5;
    case FZ_STRUCTURE_H6: return 6;
    default: return -1;
    }
}

// Appends the text under `block` and those after it to `buf`, lines apart by spaces.
static void collect_text(fz_context *ctx, fz_stext_block *block, fz_buffer *buf, fz_rect *bbox, int depth) {
    if (depth > 64) return;
    for (; block; block = block->next) {
        if (block->type == FZ_STEXT_BLOCK_TEXT) {
            for (fz_stext_line *line = block->u.t.first_line; line; line = line->next) {
                if (buf->len > 0) fz_append_byte(ctx, buf, ' ');
                for (fz_stext_char *ch = line->first_char; ch; ch = ch->next)
                    fz_append_rune(ctx, buf, ch->c);
                *bbox = fz_union_rect(*bbox, line->bbox);
            }
        } else if (block->type == FZ_STEXT_BLOCK_STRUCT && block->u.s.down) {
            collect_text(ctx, block->u.s.down->first_block, buf, bbox, depth + 1);
        }
    }
}

typedef struct {
    vp_tagged_heading *list;
    int count, cap;
} heading_list;

static void find_headings(fz_context *ctx, fz_stext_block *block, heading_list *out, int depth) {
    if (depth > 64) return;
    for (; block; block = block->next) {
        if (block->type != FZ_STEXT_BLOCK_STRUCT || !block->u.s.down) continue;
        fz_stext_struct *s = block->u.s.down;
        int level = heading_level(s->standard);
        if (level < 0) {
            find_headings(ctx, s->first_block, out, depth + 1);
            continue;
        }
        fz_buffer *buf = fz_new_buffer(ctx, 64);
        fz_rect bbox = fz_empty_rect;
        fz_try(ctx) {
            collect_text(ctx, s->first_block, buf, &bbox, depth + 1);
            if (buf->len > 0 && !fz_is_empty_rect(bbox)) {
                if (out->count == out->cap) {
                    int cap = out->cap ? out->cap * 2 : 16;
                    out->list = fz_realloc_array(ctx, out->list, cap, vp_tagged_heading);
                    out->cap = cap;
                }
                vp_tagged_heading *h = &out->list[out->count];
                h->level = level;
                h->bbox = bbox;
                h->text = fz_malloc(ctx, buf->len + 1);
                memcpy(h->text, buf->data, buf->len);
                h->text[buf->len] = 0;
                out->count++;
            }
        } fz_always(ctx) {
            fz_drop_buffer(ctx, buf);
        } fz_catch(ctx) {
            fz_rethrow(ctx);
        }
    }
}

int mupdf_page_tagged_headings(fz_context *ctx, fz_document *doc, int pageno, vp_tagged_heading **out, int *out_count, const char **out_error) {
    if (!ctx || !doc || !out || !out_count) return -1;
    *out = NULL;
    *out_count = 0;
    fz_page *page = NULL;
    fz_stext_page *stext = NULL;
    heading_list list = { NULL, 0, 0 };
    fz_var(page);
    fz_var(stext);
    fz_var(list);
    fz_try(ctx) {
        page = fz_load_page(ctx, doc, pageno);
        fz_stext_options opts;
        memset(&opts, 0, sizeof(opts));
        opts.flags = FZ_STEXT_COLLECT_STRUCTURE;
        stext = vp_new_stext_page_clipped(ctx, page, NULL, &opts);
        find_headings(ctx, stext->first_block, &list, 0);
        *out = list.list;
        *out_count = list.count;
    } fz_always(ctx) {
        fz_drop_stext_page(ctx, stext);
        fz_drop_page(ctx, page);
    } fz_catch(ctx) {
        mupdf_tagged_headings_free(ctx, list.list, list.count);
        if (out_error) *out_error = fz_caught_message(ctx);
        return -1;
    }
    return 0;
}

void mupdf_tagged_headings_free(fz_context *ctx, vp_tagged_heading *list, int count) {
    if (!ctx || !list) return;
    for (int i = 0; i < count; i++) fz_free(ctx, list[i].text);
    fz_free(ctx, list);
}
