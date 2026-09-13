//
//  PDFThumbnailGridView.swift
//  VectorPDF
//
//  Created for VectorPDF.
//

import SwiftUI
import AppKit

public struct PDFThumbnailGridView: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @State private var hoveredPageIndex: Int? = nil

    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        guard let doc = viewModel.document, doc.pageCount > 0 else {
            return AnyView(
                ContentUnavailableView(
                    "No Pages",
                    systemImage: "doc",
                    description: Text("Document has no pages")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        let pageCount = doc.pageCount

        return AnyView(
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(0..<pageCount, id: \.self) { pageIndex in
                            let isCurrent = viewModel.currentPageIndex == pageIndex
                            let isHovered = hoveredPageIndex == pageIndex

                            VStack(spacing: 6) {
                                thumbnailCard(for: pageIndex, doc: doc, isCurrent: isCurrent)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(
                                                isCurrent ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.6) : Color.gray.opacity(0.3)),
                                                lineWidth: isCurrent ? 2.5 : 1
                                            )
                                    )
                                    .shadow(color: isCurrent ? Color.accentColor.opacity(0.3) : Color.black.opacity(0.12), radius: isCurrent ? 4 : 2, x: 0, y: 1)

                                Text("\(pageIndex + 1)")
                                    .font(isCurrent ? .caption.bold() : .caption)
                                    .foregroundColor(isCurrent ? .accentColor : .secondary)
                            }
                            .id(pageIndex)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                hoveredPageIndex = hovering ? pageIndex : nil
                            }
                            .onTapGesture {
                                viewModel.jumpToPage(pageIndex)
                            }
                            .onAppear {
                                viewModel.requestThumbnail(for: pageIndex)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: viewModel.currentPageIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
                .onAppear {
                    proxy.scrollTo(viewModel.currentPageIndex, anchor: .center)
                }
            }
        )
    }

    @ViewBuilder
    private func thumbnailCard(for pageIndex: Int, doc: PDFDocumentCore, isCurrent: Bool) -> some View {
        let bounds = doc.pageBounds[pageIndex]
        let aspect = (bounds.width > 0 && bounds.height > 0) ? (bounds.width / bounds.height) : (612.0 / 792.0)
        let cardWidth: CGFloat = 130
        let cardHeight: CGFloat = cardWidth / aspect

        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(nsColor: .windowBackgroundColor))

            if let img = viewModel.thumbnailImages[pageIndex] {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }
}

