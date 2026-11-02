# Translating the user guide

The guide is machine-translated. VectorPDF's own interface is English only for now, so readers
need to match what they read against English labels on screen.

Each language is a folder in `docs/guide`, named for its `.lproj`, with a `strings.json` and the
translated pages. Tips chooses the language by itself, and the app doesn't need to declare it.

## Translating a page

1. Keep the file name, and start with the page's comments:
   - `<!-- keywords: ... -->`: the translated keywords, followed by the English ones, so a search
     works in either language.
   - `<!-- source: ... -->`: `source_hash()` of the English page, from `Scripts/build_help.py`.
2. Translate the text, including warnings.
3. Keep exactly as they are: menu names and paths, button, setting, tab and toolbar names, every
   shortcut, file names, code, and product names (VectorPDF, Tips, Finder, Link Peek, iCloud).
4. Keep every link target. If a heading is linked to with `#`, keep its target by ending the
   translated heading with `{#english-slug}`.
5. Keep the same structure of headings, lists, tables and blockquotes. In a blockquote, translate
   `**Note:**` and `**Warning:**` too.

The top page says the guide is machine-translated. No other page needs to.

## What the build checks

The build fails if a translation drops a shortcut, a menu path or a bold label, breaks a link, or
leaves out a page from its sidebar. When an English page changes, its translations stop matching
their source hash. The build warns and uses the English page until they're translated again.
