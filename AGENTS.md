# VectorPDF Agent Instructions & Repository Guidelines

## ⚠️ STRICT PRIVACY & PERSONAL IDENTIFIER DIRECTIVE

**CRITICAL RULE:**
- **NEVER** hardcode or commit personal file paths (e.g. `/Users/<username>/...`), personal email addresses (`*@gmail.com`, etc.), or private usernames into tests, fixtures, source code, scripts, or documentation.
- When writing tests or examples that simulate local filesystem paths or cloud storage accounts (such as iCloud Drive, Google Drive, OneDrive, Dropbox, Box):
  - Always use generic dummy usernames and mock domains:
    - Path prefix: `/Users/example/...` or `FileManager.default.homeDirectoryForCurrentUser` (dynamically evaluated at runtime)
    - Cloud account IDs: `user@example.com`, `user@domain.com`, `GoogleDrive-user@example.com`
  - Never copy paste real file paths from user prompt logs or error transcripts into committed test files.

---

## Architecture & Codebase Guidelines

1. **Framework & Engine:**
   - VectorPDF is a native macOS PDF application built in Swift and SwiftUI, backed by a C MuPDF bridge (`MuPDFBridge`) and Swift engine layer (`PDFEngine`).
   - All AppKit / UI interactions must be `@MainActor`-safe.
   - The vendored MuPDF is 1.28.5 **plus cherry-picked upstream fixes** in `Vendor/patches/` (store thread-safety, Bug 709849). When a MuPDF release includes them, rebase onto that tag and delete the patches — see "Backported patches" in `Vendor/README.md`.
   - Never empty MuPDF's store (`fz_empty_store`): it is shared by every cloned context, and emptying it frees items other threads are using. Its size limit bounds memory on its own.
   - Structured text comes from `vp_new_stext_page_clipped` (`TextClipFilter.c`), not `fz_new_stext_page_from_page`: it leaves out text the page's clipping paths hide, which MuPDF keeps. Load structured text through it everywhere, or hidden text turns up in selection and search.
   - Search workers use independent contexts (`mupdf_context_create_independent`) rather than clones, so they don't contend on the allocation lock. They share nothing with other contexts but the FreeType lock: never pass a document, page or other MuPDF object between them, and never clone one.

2. **Windowing & Native Appearance:**
   - Windows use a unified toolbar with tab bar support via `PDFViewerWindow` and `DocumentWindowing`.
   - Window top bar color follows macOS Preview styling with `NSColor.topWindowBarColor`.
   - Native segmented controls, capsules, and toolbars adapt across macOS versions.

3. **Menu Organization:**
   - Keep menus clean and uncluttered. Advanced engineering tools (e.g. scale calibration, takeoff summary tables) belong in their respective toolbars (such as the Measurement toolbar) rather than cluttering global menus.

4. **Testing:**
   - Run tests using `swift test`. Tests that put real windows on screen are marked `@Test(.showsWindows)` and skipped by default; run them with `VECTORPDF_UI_TESTS=1 swift test --no-parallel` before a release or after changing windowing, tabs, or click handling. They need `--no-parallel` because they share one app: a window that opens a document closes other tests' empty windows.
   - Tests that send key events a view deliberately ignores should end its responder chain with `KeySinkResponder` (in `TestTraits.swift`), or AppKit beeps.
   - Headless test execution: Alerts (such as `NSAlert.runModal()`) must be guarded by checking `ProcessInfo` test runner environment variables to prevent headless test hangs.
   - After changing MuPDF, the bridge, or how documents are used across threads, run the concurrency stress test: `VECTORPDF_STRESS_TESTS=1 swift test --filter ConcurrencyStress`.
   - After changing search or text extraction, compare times with `VECTORPDF_BENCHMARKS=1 swift test --filter SearchBenchmark` (`VECTORPDF_SEARCH_WORKERS=1` for the serial baseline).
   - Always run tests and verify zero regressions before committing.

5. **User Guide:**
   - The help book is built from the Markdown in `docs/guide/` by `Scripts/build_help.py`, which `Scripts/build_app_bundle.sh` runs. When a feature, menu item, shortcut or setting changes, update the guide in the same commit. When a command is on a context menu, say so in the guide as well as giving its keyboard shortcut, and keep `right-click-menus.md` up to date. New pages must be listed in `docs/guide/README.md`, which sets the sidebar; the build fails on broken links. Each page starts with a `<!-- keywords: ... -->` comment for Tips search.
   - Translations live in `docs/guide/<language>/`; see `docs/translating-the-guide.md`. Interface labels stay in English in them until the app is localized.
   - Tips only shows the book when the app is in `/Applications`; running elsewhere isn't supported for Help. Test with a separate `BUNDLE_ID` copy rather than replacing an installed app.
