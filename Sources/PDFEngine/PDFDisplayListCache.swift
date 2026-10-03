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

import Foundation
import MuPDFBridge

/// Thread-confined LRU cache for pre-compiled MuPDF vector display lists.
final class PDFDisplayListCache {
    private let capacity: Int
    private var cache: [Int: FZDisplayList] = [:]
    private var lruOrder: [Int] = []
    
    init(capacity: Int = 10) {
        self.capacity = capacity
    }
    
    func get(pageIndex: Int) -> FZDisplayList? {
        if let list = cache[pageIndex] {
            if let idx = lruOrder.firstIndex(of: pageIndex) {
                lruOrder.remove(at: idx)
                lruOrder.append(pageIndex)
            }
            return list
        }
        return nil
    }
    
    func insert(pageIndex: Int, list: FZDisplayList, ctx: FZContext) {
        if cache[pageIndex] != nil {
            mupdf_display_list_drop(ctx, list)
            return
        }
        
        while lruOrder.count >= capacity, !lruOrder.isEmpty {
            let oldest = lruOrder.removeFirst()
            if let dropped = cache.removeValue(forKey: oldest) {
                mupdf_display_list_drop(ctx, dropped)
            }
        }
        
        cache[pageIndex] = list
        lruOrder.append(pageIndex)
    }
    
    func removeAll(ctx: FZContext) {
        for (_, list) in cache {
            mupdf_display_list_drop(ctx, list)
        }
        cache.removeAll()
        lruOrder.removeAll()
    }
}
