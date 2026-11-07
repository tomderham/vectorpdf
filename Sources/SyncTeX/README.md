# SyncTeX parser

The official SyncTeX parser by Jérôme Laurens, vendored for SyncTeX support (forward and backward
search between a PDF and its TeX source). Skim, TeXShop, Zathura and Sioyek use the same code.

- Upstream: <https://github.com/jlaurens/synctex>, commit
  [`04cf8e3e`](https://github.com/jlaurens/synctex/commit/04cf8e3e8665ff203248d7af78ee1129afbc1b64)
  (6 June 2026), parser version 1.31 (`synctex_version.h`).
- Licence: MIT (`LICENSE`).
- Files taken unchanged except as noted: `synctex_parser.c`, `synctex_parser_utils.c`,
  `synctex_parser_advanced.h`, `synctex_parser_utils.h`, and in `include/`, `synctex_parser.h`
  and `synctex_version.h`.
- `synctex_parser_local.h` is VectorPDF's own (upstream's is for TeX Live); `Package.swift`
  defines `SYNCTEX_USE_LOCAL_HEADER` so the parser reads it.
- It reads `.synctex.gz` with the system's zlib (`-lz`). MuPDF's static library has its own zlib
  but without the `gz*` functions the parser uses; the two don't clash.

## The one change

`synctex_parser.c` calls `setlocale(LC_NUMERIC, "C")` around each `strtod`, then puts the locale
back. `setlocale` changes a process-wide setting and isn't thread-safe, and VectorPDF parses on a
background thread while other threads run. So `HAVE_SETLOCALE` is left undefined, and the two
`strtod` calls (in `_synctex_scan_float_and_dimension` and `_synctex_scan_post_scriptum`) are
`strtod_l` with a C locale made once (`_synctex_c_locale()` in `synctex_parser_local.h`). When
updating, take upstream's files and make the same two replacements.
