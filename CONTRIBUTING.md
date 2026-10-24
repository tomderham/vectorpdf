# Contributing to VectorPDF

Thanks for helping. VectorPDF is a small project with one maintainer, so focused bug reports and small, well-tested pull requests are the most useful contributions.

## Reporting bugs

[Open an issue](https://github.com/tomderham/vectorpdf/issues) and include:

- VectorPDF version (*VectorPDF → About VectorPDF*) and macOS version.
- What you did, what you expected, and what happened.
- **A PDF that shows the problem**, if you can share one. Most bugs in a PDF reader depend on the document. If yours is confidential, say what produced it (LaTeX, Word, AutoCAD, a scanner, …), or try to reproduce it with a public file.
- For crashes, the crash report from *Console.app → Crash Reports*.

Feature requests are welcome as issues too. Say what you're trying to do, not just the feature you want.

## Building

Requirements: an Apple Silicon Mac with macOS 15 or later and Xcode 27 (Swift 6).

```bash
./Vendor/build-mupdf.sh   # once: downloads, verifies, and builds MuPDF (~1–2 min)
swift build
swift test
./Scripts/build_app_bundle.sh debug   # VectorPDF.app, for trying changes in the real app
```

See [Vendor/README.md](Vendor/README.md) to change the MuPDF version.

## Pull requests

- Open an issue first for anything larger than a bug fix, so we can agree on the approach before you spend time on it.
- Keep each pull request to one change. Match the style of the code around it.
- Add or update tests for behavior you change. `swift test` must pass with no new warnings. If you touched windows, tabs, or click handling, also run `VECTORPDF_UI_TESTS=1 swift test`, which includes the tests that open real windows (marked `@Test(.showsWindows)`).
- Check the change in the app, not only in tests, if it affects UI or rendering.
- Don't commit build output (`.build/`, `*.app`, `*.dmg`) or `Vendor/MuPDF.xcframework`.

By contributing, you agree that your contribution is licensed under the project's [AGPL-3.0](LICENSE) license.

## Code layout

| Path | What's there |
| --- | --- |
| `Sources/MuPDFBridge/` | C wrapper over MuPDF. Everything that touches `fz_*` / `pdf_*` APIs. |
| `Sources/PDFEngine/PDFDocumentCore.swift` | Swift API over the bridge: open, render, edit, save. |
| `Sources/PDFEngine/PDFRenderActor.swift`, `PDFSearchActor.swift` | Background rendering and search, each with its own MuPDF context. |
| `Sources/PDFEngine/PDFViewerViewModel*.swift` | Per-window document state. The class and its stored properties are in `PDFViewerViewModel.swift`; behavior is split by feature into extensions (`+Search`, `+Redaction`, `+Measurement`, `+PageEditing`, …). |
| `Sources/PDFEngine/PDFCanvasView*.swift` | The AppKit view that draws pages and handles input, split the same way (`+Drawing`, `+Mouse`, `+Keyboard`, `+ContextMenu`, …). |
| `Sources/PDFEngine/*Toolbar*.swift`, `PDFUI.swift` | SwiftUI chrome. |
| `Sources/VectorPDF/main.swift` | App entry point and menus. |
| `Tests/PDFEngineTests/` | Swift Testing suites. Fixtures are generated in code; see `writeRawPDF` in `RedactionSafetyTests.swift` for hand-built PDFs. |

New code for an existing feature goes in that feature's extension file. Stored properties have to stay in the main class declaration.

## Rules that keep the project healthy

- **No personal data in the repo.** Never commit real file paths (`/Users/<you>/…`), email addresses, or account names, including in tests and fixtures. Use `/Users/example/…`, `FileManager.default.homeDirectoryForCurrentUser`, and `user@example.com`.
- **Tests must run headless.** Anything that shows a modal (`NSAlert.runModal()`, save panels) must be skipped under the test runner; see `PDFViewerViewModel.isRunningTests`.
- **UI code is `@MainActor`.** MuPDF contexts are not thread-safe: use the existing actors or `PDFDocumentCore`'s lock rather than sharing a context.
- **Redaction and saving are safety-critical.** Changes to `mupdf_page_apply_redaction_rects` or the save options in `MuPDFBridge.c` need a test in `RedactionSafetyTests.swift` showing that redacted content is absent from the saved file's bytes.
- **Keep menus uncluttered.** Specialist tools (measurement, takeoff) belong in their toolbars.

## Security issues

If you find a way that redacted or encrypted content can be recovered, please don't post the details in a public issue. Use GitHub's private vulnerability reporting (*Security → Report a vulnerability*) on the repository instead.
