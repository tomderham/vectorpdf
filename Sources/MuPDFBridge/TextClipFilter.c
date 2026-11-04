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

// A device that passes a page's drawing on to another device (structured text), leaving out the
// text the page's clipping paths hide. Text extraction doesn't clip, and MuPDF's FZ_STEXT_CLIP
// only tests each clip's bounding box: text an L-shaped viewport clips away, such as a CAD
// drawing's own copy of its sheet's legend, came out on top of the visible text. A glyph is kept
// when a point just inside it is inside every clip in force. Clips this can't test exactly
// (stroked paths, text, image masks, soft masks) keep all text, as before.

#include "TextClipFilter.h"
#include <string.h>

typedef struct
{
	fz_path *path; /* NULL for a clip that can't be tested: everything is inside it */
	fz_matrix ctm;
	int even_odd;
	fz_rect bbox;
	/* The path flattened into closed polygons in device space, when first needed. */
	int flattened;
	fz_point *pts;
	int npts, cap_pts;
	int *starts; /* first point of each polygon */
	int nsub, cap_sub;
} clip_entry;

typedef struct
{
	fz_device super;
	fz_device *target;
	clip_entry *clips;
	int len, cap;
} filter_device;

/* Flattening */

typedef struct
{
	fz_context *ctx;
	clip_entry *e;
	fz_point cur;
} flatten_arg;

static void add_point(fz_context *ctx, clip_entry *e, fz_point p)
{
	if (e->npts == e->cap_pts)
	{
		int cap = e->cap_pts ? e->cap_pts * 2 : 16;
		e->pts = fz_realloc_array(ctx, e->pts, cap, fz_point);
		e->cap_pts = cap;
	}
	e->pts[e->npts++] = fz_transform_point(p, e->ctm);
}

static void start_polygon(fz_context *ctx, clip_entry *e)
{
	if (e->nsub == e->cap_sub)
	{
		int cap = e->cap_sub ? e->cap_sub * 2 : 4;
		e->starts = fz_realloc_array(ctx, e->starts, cap, int);
		e->cap_sub = cap;
	}
	e->starts[e->nsub++] = e->npts;
}

static void fl_moveto(fz_context *ctx, void *arg_, float x, float y)
{
	flatten_arg *arg = arg_;
	arg->cur = fz_make_point(x, y);
	start_polygon(ctx, arg->e);
	add_point(ctx, arg->e, arg->cur);
}

static void fl_lineto(fz_context *ctx, void *arg_, float x, float y)
{
	flatten_arg *arg = arg_;
	arg->cur = fz_make_point(x, y);
	if (arg->e->nsub == 0)
		start_polygon(ctx, arg->e);
	add_point(ctx, arg->e, arg->cur);
}

static void fl_curveto(fz_context *ctx, void *arg_, float x1, float y1, float x2, float y2, float x3, float y3)
{
	flatten_arg *arg = arg_;
	fz_point p0 = arg->cur;
	int i;
	/* Eight straight pieces are plenty to tell inside from outside for a clip outline. */
	for (i = 1; i <= 8; i++)
	{
		float t = i / 8.0f, u = 1 - t;
		float a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
		fl_lineto(ctx, arg, a * p0.x + b * x1 + c * x2 + d * x3, a * p0.y + b * y1 + c * y2 + d * y3);
	}
}

static void fl_closepath(fz_context *ctx, void *arg)
{
	/* Polygons are closed implicitly. */
}

static void fl_rectto(fz_context *ctx, void *arg_, float x1, float y1, float x2, float y2)
{
	flatten_arg *arg = arg_;
	fl_moveto(ctx, arg, x1, y1);
	fl_lineto(ctx, arg, x2, y1);
	fl_lineto(ctx, arg, x2, y2);
	fl_lineto(ctx, arg, x1, y2);
	arg->cur = fz_make_point(x1, y1);
}

static const fz_path_walker flatten_walker = {
	fl_moveto, fl_lineto, fl_curveto, fl_closepath, NULL, NULL, NULL, fl_rectto
};

static void flatten(fz_context *ctx, clip_entry *e)
{
	flatten_arg arg = { ctx, e, { 0, 0 } };
	e->flattened = 1;
	fz_walk_path(ctx, e->path, &flatten_walker, &arg);
}

/* Inside testing */

static int inside_clip(fz_context *ctx, clip_entry *e, fz_point p)
{
	int s, winding = 0, crossings = 0;
	if (!e->path)
		return 1;
	if (p.x < e->bbox.x0 || p.x > e->bbox.x1 || p.y < e->bbox.y0 || p.y > e->bbox.y1)
		return 0;
	if (!e->flattened)
		flatten(ctx, e);
	for (s = 0; s < e->nsub; s++)
	{
		int first = e->starts[s];
		int end = s + 1 < e->nsub ? e->starts[s + 1] : e->npts;
		int i;
		for (i = first; i < end; i++)
		{
			fz_point a = e->pts[i];
			fz_point b = e->pts[i + 1 < end ? i + 1 : first];
			/* Count edges crossing the ray from p to the right. */
			if ((a.y <= p.y) != (b.y <= p.y))
			{
				float x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y);
				if (x > p.x)
				{
					crossings++;
					winding += b.y > a.y ? 1 : -1;
				}
			}
		}
	}
	return e->even_odd ? (crossings & 1) : (winding != 0);
}

static int glyph_visible(fz_context *ctx, filter_device *dev, fz_matrix trm, fz_matrix ctm)
{
	/* A point a quarter of an em along and a third up from the glyph's origin: inside the
	 * letter's body, so a glyph cut by a clip counts by where most of it is. */
	fz_point p = fz_transform_point(fz_make_point(0.25f, 0.3f), fz_concat(trm, ctm));
	int i;
	for (i = 0; i < dev->len; i++)
		if (!inside_clip(ctx, &dev->clips[i], p))
			return 0;
	return 1;
}

static int is_space(int ucs)
{
	return ucs == ' ' || ucs == 0xA0 || ucs == '\t';
}

/* Which item's position decides whether item i is shown: its own, or -1 to go with the one
 * before it. An item without a glyph (one of several characters for one glyph) goes with that
 * glyph. Spaces go with the text beside them, and a run of nothing but spaces is always kept: a
 * table cell's padding often runs past its clip, and dropping it would change how the cell's
 * text groups into lines. */
static int deciding_item(const fz_text_span *span, int i)
{
	int j;
	if (span->items[i].gid < 0)
		return -1;
	if (!is_space(span->items[i].ucs))
		return i;
	if (i > 0)
		return -1;
	for (j = 1; j < span->len; j++)
		if (span->items[j].gid >= 0 && !is_space(span->items[j].ucs))
			return j;
	return -2; /* only spaces */
}

static int item_visible(fz_context *ctx, filter_device *dev, const fz_text_span *span, int i, fz_matrix ctm, int previous)
{
	int d = deciding_item(span, i);
	fz_matrix trm = span->trm;
	if (d == -1)
		return previous;
	if (d == -2)
		return 1;
	trm.e = span->items[d].x;
	trm.f = span->items[d].y;
	return glyph_visible(ctx, dev, trm, ctm);
}

static int any_testable_clip(filter_device *dev)
{
	int i;
	for (i = 0; i < dev->len; i++)
		if (dev->clips[i].path)
			return 1;
	return 0;
}

/* The text with only its visible glyphs: the original when all of them are, NULL when none are,
 * or a new text the caller drops. */
static fz_text *visible_text(fz_context *ctx, filter_device *dev, const fz_text *text, fz_matrix ctm, int *is_new)
{
	const fz_text_span *span;
	fz_text *out = NULL;
	int hidden = 0, shown = 0;

	*is_new = 0;
	if (!any_testable_clip(dev))
		return (fz_text *)text;

	for (span = text->head; span; span = span->next)
	{
		int i, visible = 1;
		for (i = 0; i < span->len; i++)
		{
			visible = item_visible(ctx, dev, span, i, ctm, visible);
			if (visible) shown++; else hidden++;
		}
	}
	if (hidden == 0)
		return (fz_text *)text;
	if (shown == 0)
		return NULL;

	out = fz_new_text(ctx);
	fz_try(ctx)
	{
		for (span = text->head; span; span = span->next)
		{
			int i, visible = 1;
			for (i = 0; i < span->len; i++)
			{
				const fz_text_item *item = &span->items[i];
				fz_matrix trm = span->trm;
				trm.e = item->x;
				trm.f = item->y;
				visible = item_visible(ctx, dev, span, i, ctm, visible);
				if (visible)
					fz_show_glyph_aux(ctx, out, span->font, trm, item->adv, item->gid, item->ucs, item->cid,
						span->wmode, span->bidi_level, span->markup_dir, span->language);
			}
		}
	}
	fz_catch(ctx)
	{
		fz_drop_text(ctx, out);
		fz_rethrow(ctx);
	}
	*is_new = 1;
	return out;
}

/* The clip stack */

static void push_clip(fz_context *ctx, filter_device *dev, const fz_path *path, int even_odd, fz_matrix ctm)
{
	clip_entry *e;
	if (dev->len == dev->cap)
	{
		int cap = dev->cap ? dev->cap * 2 : 16;
		dev->clips = fz_realloc_array(ctx, dev->clips, cap, clip_entry);
		dev->cap = cap;
	}
	e = &dev->clips[dev->len];
	memset(e, 0, sizeof(*e));
	if (path)
	{
		e->bbox = fz_bound_path(ctx, path, NULL, ctm);
		e->path = fz_keep_path(ctx, path);
		e->ctm = ctm;
		e->even_odd = even_odd;
	}
	dev->len++;
}

static void drop_entry(fz_context *ctx, clip_entry *e)
{
	fz_drop_path(ctx, e->path);
	fz_free(ctx, e->pts);
	fz_free(ctx, e->starts);
	memset(e, 0, sizeof(*e));
}

static void pop_clip(fz_context *ctx, filter_device *dev)
{
	if (dev->len > 0)
		drop_entry(ctx, &dev->clips[--dev->len]);
}

/* Device callbacks: everything goes on to the target. */

#define TARGET(dev_) (((filter_device *)(dev_))->target)

static void f_fill_path(fz_context *ctx, fz_device *dev, const fz_path *path, int even_odd, fz_matrix ctm, fz_colorspace *cs, const float *color, float alpha, fz_color_params cp)
{
	fz_fill_path(ctx, TARGET(dev), path, even_odd, ctm, cs, color, alpha, cp);
}

static void f_stroke_path(fz_context *ctx, fz_device *dev, const fz_path *path, const fz_stroke_state *stroke, fz_matrix ctm, fz_colorspace *cs, const float *color, float alpha, fz_color_params cp)
{
	fz_stroke_path(ctx, TARGET(dev), path, stroke, ctm, cs, color, alpha, cp);
}

static void f_clip_path(fz_context *ctx, fz_device *dev, const fz_path *path, int even_odd, fz_matrix ctm, fz_rect scissor)
{
	push_clip(ctx, (filter_device *)dev, path, even_odd, ctm);
	fz_clip_path(ctx, TARGET(dev), path, even_odd, ctm, scissor);
}

static void f_clip_stroke_path(fz_context *ctx, fz_device *dev, const fz_path *path, const fz_stroke_state *stroke, fz_matrix ctm, fz_rect scissor)
{
	push_clip(ctx, (filter_device *)dev, NULL, 0, ctm);
	fz_clip_stroke_path(ctx, TARGET(dev), path, stroke, ctm, scissor);
}

static void f_fill_text(fz_context *ctx, fz_device *dev, const fz_text *text, fz_matrix ctm, fz_colorspace *cs, const float *color, float alpha, fz_color_params cp)
{
	int is_new;
	fz_text *shown = visible_text(ctx, (filter_device *)dev, text, ctm, &is_new);
	if (!shown)
		return;
	fz_try(ctx)
		fz_fill_text(ctx, TARGET(dev), shown, ctm, cs, color, alpha, cp);
	fz_always(ctx)
		if (is_new) fz_drop_text(ctx, shown);
	fz_catch(ctx)
		fz_rethrow(ctx);
}

static void f_stroke_text(fz_context *ctx, fz_device *dev, const fz_text *text, const fz_stroke_state *stroke, fz_matrix ctm, fz_colorspace *cs, const float *color, float alpha, fz_color_params cp)
{
	int is_new;
	fz_text *shown = visible_text(ctx, (filter_device *)dev, text, ctm, &is_new);
	if (!shown)
		return;
	fz_try(ctx)
		fz_stroke_text(ctx, TARGET(dev), shown, stroke, ctm, cs, color, alpha, cp);
	fz_always(ctx)
		if (is_new) fz_drop_text(ctx, shown);
	fz_catch(ctx)
		fz_rethrow(ctx);
}

static void f_ignore_text(fz_context *ctx, fz_device *dev, const fz_text *text, fz_matrix ctm)
{
	int is_new;
	fz_text *shown = visible_text(ctx, (filter_device *)dev, text, ctm, &is_new);
	if (!shown)
		return;
	fz_try(ctx)
		fz_ignore_text(ctx, TARGET(dev), shown, ctm);
	fz_always(ctx)
		if (is_new) fz_drop_text(ctx, shown);
	fz_catch(ctx)
		fz_rethrow(ctx);
}

static void f_clip_text(fz_context *ctx, fz_device *dev, const fz_text *text, fz_matrix ctm, fz_rect scissor)
{
	push_clip(ctx, (filter_device *)dev, NULL, 0, ctm);
	fz_clip_text(ctx, TARGET(dev), text, ctm, scissor);
}

static void f_clip_stroke_text(fz_context *ctx, fz_device *dev, const fz_text *text, const fz_stroke_state *stroke, fz_matrix ctm, fz_rect scissor)
{
	push_clip(ctx, (filter_device *)dev, NULL, 0, ctm);
	fz_clip_stroke_text(ctx, TARGET(dev), text, stroke, ctm, scissor);
}

static void f_fill_shade(fz_context *ctx, fz_device *dev, fz_shade *shade, fz_matrix ctm, float alpha, fz_color_params cp)
{
	fz_fill_shade(ctx, TARGET(dev), shade, ctm, alpha, cp);
}

static void f_fill_image(fz_context *ctx, fz_device *dev, fz_image *image, fz_matrix ctm, float alpha, fz_color_params cp)
{
	fz_fill_image(ctx, TARGET(dev), image, ctm, alpha, cp);
}

static void f_fill_image_mask(fz_context *ctx, fz_device *dev, fz_image *image, fz_matrix ctm, fz_colorspace *cs, const float *color, float alpha, fz_color_params cp)
{
	fz_fill_image_mask(ctx, TARGET(dev), image, ctm, cs, color, alpha, cp);
}

static void f_clip_image_mask(fz_context *ctx, fz_device *dev, fz_image *image, fz_matrix ctm, fz_rect scissor)
{
	push_clip(ctx, (filter_device *)dev, NULL, 0, ctm);
	fz_clip_image_mask(ctx, TARGET(dev), image, ctm, scissor);
}

static void f_pop_clip(fz_context *ctx, fz_device *dev)
{
	pop_clip(ctx, (filter_device *)dev);
	fz_pop_clip(ctx, TARGET(dev));
}

static void f_begin_mask(fz_context *ctx, fz_device *dev, fz_rect area, int luminosity, fz_colorspace *cs, const float *bc, fz_color_params cp)
{
	/* A soft mask is popped like a clip; its shape isn't tested. */
	push_clip(ctx, (filter_device *)dev, NULL, 0, fz_identity);
	fz_begin_mask(ctx, TARGET(dev), area, luminosity, cs, bc, cp);
}

static void f_end_mask(fz_context *ctx, fz_device *dev, fz_function *fn)
{
	fz_end_mask_tr(ctx, TARGET(dev), fn);
}

static void f_begin_group(fz_context *ctx, fz_device *dev, fz_rect area, fz_colorspace *cs, int isolated, int knockout, int blendmode, float alpha)
{
	fz_begin_group(ctx, TARGET(dev), area, cs, isolated, knockout, blendmode, alpha);
}

static void f_end_group(fz_context *ctx, fz_device *dev)
{
	fz_end_group(ctx, TARGET(dev));
}

static int f_begin_tile(fz_context *ctx, fz_device *dev, fz_rect area, fz_rect view, float xstep, float ystep, fz_matrix ctm, int id, int doc_id)
{
	return fz_begin_tile_tid(ctx, TARGET(dev), area, view, xstep, ystep, ctm, id, doc_id);
}

static void f_end_tile(fz_context *ctx, fz_device *dev)
{
	fz_end_tile(ctx, TARGET(dev));
}

static void f_render_flags(fz_context *ctx, fz_device *dev, int set, int clear)
{
	fz_render_flags(ctx, TARGET(dev), set, clear);
}

static void f_set_default_colorspaces(fz_context *ctx, fz_device *dev, fz_default_colorspaces *dcs)
{
	fz_set_default_colorspaces(ctx, TARGET(dev), dcs);
}

static void f_begin_layer(fz_context *ctx, fz_device *dev, const char *name)
{
	fz_begin_layer(ctx, TARGET(dev), name);
}

static void f_end_layer(fz_context *ctx, fz_device *dev)
{
	fz_end_layer(ctx, TARGET(dev));
}

static void f_begin_structure(fz_context *ctx, fz_device *dev, fz_structure standard, const char *raw, int idx)
{
	fz_begin_structure(ctx, TARGET(dev), standard, raw, idx);
}

static void f_end_structure(fz_context *ctx, fz_device *dev)
{
	fz_end_structure(ctx, TARGET(dev));
}

static void f_begin_metatext(fz_context *ctx, fz_device *dev, fz_metatext meta, const char *text)
{
	fz_begin_metatext(ctx, TARGET(dev), meta, text);
}

static void f_end_metatext(fz_context *ctx, fz_device *dev)
{
	fz_end_metatext(ctx, TARGET(dev));
}

static void f_drop_device(fz_context *ctx, fz_device *dev_)
{
	filter_device *dev = (filter_device *)dev_;
	while (dev->len > 0)
		pop_clip(ctx, dev);
	fz_free(ctx, dev->clips);
}

fz_device *vp_new_text_clip_filter(fz_context *ctx, fz_device *target)
{
	filter_device *dev = fz_new_derived_device(ctx, filter_device);

	dev->super.drop_device = f_drop_device;
	dev->super.fill_path = f_fill_path;
	dev->super.stroke_path = f_stroke_path;
	dev->super.clip_path = f_clip_path;
	dev->super.clip_stroke_path = f_clip_stroke_path;
	dev->super.fill_text = f_fill_text;
	dev->super.stroke_text = f_stroke_text;
	dev->super.clip_text = f_clip_text;
	dev->super.clip_stroke_text = f_clip_stroke_text;
	dev->super.ignore_text = f_ignore_text;
	dev->super.fill_shade = f_fill_shade;
	dev->super.fill_image = f_fill_image;
	dev->super.fill_image_mask = f_fill_image_mask;
	dev->super.clip_image_mask = f_clip_image_mask;
	dev->super.pop_clip = f_pop_clip;
	dev->super.begin_mask = f_begin_mask;
	dev->super.end_mask = f_end_mask;
	dev->super.begin_group = f_begin_group;
	dev->super.end_group = f_end_group;
	dev->super.begin_tile = f_begin_tile;
	dev->super.end_tile = f_end_tile;
	dev->super.render_flags = f_render_flags;
	dev->super.set_default_colorspaces = f_set_default_colorspaces;
	dev->super.begin_layer = f_begin_layer;
	dev->super.end_layer = f_end_layer;
	dev->super.begin_structure = f_begin_structure;
	dev->super.end_structure = f_end_structure;
	dev->super.begin_metatext = f_begin_metatext;
	dev->super.end_metatext = f_end_metatext;
	dev->target = target;
	return (fz_device *)dev;
}

fz_stext_page *vp_new_stext_page_clipped(fz_context *ctx, fz_page *page, fz_display_list *list, const fz_stext_options *options)
{
	fz_stext_page *text = fz_new_stext_page(ctx, page ? fz_bound_page(ctx, page) : fz_bound_display_list(ctx, list));
	fz_device *dev = NULL, *filter = NULL;

	fz_var(dev);
	fz_var(filter);
	fz_try(ctx)
	{
		dev = fz_new_stext_device(ctx, text, options);
		filter = vp_new_text_clip_filter(ctx, dev);
		if (page)
			fz_run_page_contents(ctx, page, filter, fz_identity, NULL);
		else
			fz_run_display_list(ctx, list, filter, fz_identity, fz_infinite_rect, NULL);
		fz_close_device(ctx, filter);
		fz_close_device(ctx, dev);
	}
	fz_always(ctx)
	{
		fz_drop_device(ctx, filter);
		fz_drop_device(ctx, dev);
	}
	fz_catch(ctx)
	{
		fz_drop_stext_page(ctx, text);
		fz_rethrow(ctx);
	}
	return text;
}
