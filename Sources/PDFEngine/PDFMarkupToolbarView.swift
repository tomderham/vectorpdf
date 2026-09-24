import SwiftUI
import AppKit

/// A collapsible macOS-style secondary markup toolbar providing drawing tools,
/// text markup actions (highlight, underline, strikethrough), color swatches, and stroke widths.
public struct PDFMarkupToolbarView: View {
    @ObservedObject var viewModel: PDFViewerViewModel

    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
    }

    private var hasSelection: Bool {
        guard let sel = viewModel.activeSelection else { return false }
        return !sel.result.highlightQuads.isEmpty || !viewModel.additionalSelectionPages.isEmpty
    }

    public var body: some View {
        HStack(spacing: 12) {
            // 1. Tool Mode Picker [Text Select | Draw | Text | Callout | Redact | Eraser]
            Picker("Mode", selection: $viewModel.canvasMode) {
                Image(systemName: "text.cursor")
                    .tag(CanvasMode.select)
                    .help("Text Selection Mode")
                Image(systemName: "pencil.tip")
                    .tag(CanvasMode.draw)
                    .help("Draw Freehand Pen (Ink)")
                Image(systemName: "character.textbox")
                    .tag(CanvasMode.text)
                    .help("Add Text Box")
                Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                    .tag(CanvasMode.callout)
                    .help("Callout Annotation (Leader arrow pointer to text note)")
                Image(systemName: "lock.slash.fill")
                    .tag(CanvasMode.redact)
                    .help("Redact Content (Permanent - scrubs underlying text & pixels)")
                Image(systemName: "eraser")
                    .tag(CanvasMode.eraser)
                    .help("Eraser (Click or Drag to remove annotations)")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 195)

            // 2. Context-Sensitive Tool Controls
            switch viewModel.canvasMode {
            case .select:
                Divider()
                    .frame(height: 16)

                // Text Markup Quick Actions (always accessible in Select mode)
                HStack(spacing: 4) {
                    Button {
                        viewModel.highlightSelection(color: viewModel.selectedAnnotationColor)
                    } label: {
                        Image(systemName: "highlighter")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Highlight Selected Text")

                    Button {
                        viewModel.underlineSelection(color: viewModel.selectedAnnotationColor)
                    } label: {
                        Image(systemName: "underline")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Underline Selected Text")

                    Button {
                        viewModel.strikethroughSelection(color: viewModel.selectedAnnotationColor)
                    } label: {
                        Image(systemName: "strikethrough")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Strikethrough Selected Text")
                }

            case .draw:
                Divider()
                    .frame(height: 16)

                // Stroke Width Selector (only in Draw mode)
                Picker("Line Width", selection: $viewModel.drawStrokeWidth) {
                    Text("Thin").tag(CGFloat(1.5))
                    Text("Medium").tag(CGFloat(2.5))
                    Text("Thick").tag(CGFloat(4.5))
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 155)
                .help("Pen Stroke Width")

            case .text:
                Divider()
                    .frame(height: 16)

                // Font Size Slider (6 pt - 32 pt)
                HStack(spacing: 6) {
                    Text("Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.selectedFontSize, in: 6...32, step: 1)
                        .frame(width: 90)
                        .controlSize(.small)
                    Text("\(Int(viewModel.selectedFontSize)) pt")
                        .font(.caption.monospacedDigit())
                        .frame(width: 32, alignment: .leading)
                }
                .help("Text Box Font Size (6–32 pt)")

            case .callout:
                Divider()
                    .frame(height: 16)

                HStack(spacing: 6) {
                    Text("Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.selectedFontSize, in: 6...32, step: 1)
                        .frame(width: 80)
                        .controlSize(.small)
                    Text("\(Int(viewModel.selectedFontSize)) pt")
                        .font(.caption.monospacedDigit())
                        .frame(width: 32, alignment: .leading)
                    Text("• Drag target to note; click note to edit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .help("Callout Note Font Size (6–32 pt)")

            case .redact:
                Divider()
                    .frame(height: 16)

                HStack(spacing: 8) {
                    Label("Permanent Action", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                        .help("Redactions physically scrub underlying text, graphics, and image pixels from the PDF stream.")

                    Text("Drag box over area")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let count = viewModel.pendingRedactionsCount
                    Button {
                        viewModel.applyAllPendingRedactions()
                    } label: {
                        Text(count > 0 ? "Apply Redactions (\(count))" : "Apply Redactions")
                            .font(.caption.bold())
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(count == 0)
                    .help("Permanently apply pending redactions and scrub PDF content stream (cannot be undone)")
                }

            case .eraser:
                Divider()
                    .frame(height: 16)

                Text("Click or drag annotations to erase")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 3. Color Palette Swatches (shown for Select, Draw, Text, and Callout modes)
            if viewModel.canvasMode != .eraser && viewModel.canvasMode != .redact {
                Divider()
                    .frame(height: 16)

                HStack(spacing: 5) {
                    ForEach(AnnotationColor.allCases, id: \.self) { color in
                        Button {
                            viewModel.selectedAnnotationColor = color
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(nsColor: color.nsColor))
                                    .frame(width: 14, height: 14)

                                if viewModel.selectedAnnotationColor == color {
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.8), lineWidth: 1.5)
                                        .frame(width: 19, height: 19)
                                }
                            }
                            .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help(color.displayName)
                    }
                }
            }

            Spacer()

            // 5. Close Toolbar Button
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.isMarkupBarVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close Markup Toolbar (⇧⌘A)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 32)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

