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

#ifndef VP_TEXT_CLIP_FILTER_H
#define VP_TEXT_CLIP_FILTER_H

#include "include/MuPDFBridge.h"

// A device passing everything on to target except the text the clipping paths in force hide.
fz_device *vp_new_text_clip_filter(fz_context *ctx, fz_device *target);

// Structured text of a page's contents, or of a display list when page is NULL, without the
// text its clipping paths hide (see TextClipFilter.c).
fz_stext_page *vp_new_stext_page_clipped(fz_context *ctx, fz_page *page, fz_display_list *list, const fz_stext_options *options);

#endif
