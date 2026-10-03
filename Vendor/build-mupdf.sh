#!/bin/bash
# Builds MuPDF from its official source tarball into a vendored, self-contained
# XCFramework (Vendor/MuPDF.xcframework) plus public headers
# (Sources/MuPDFBridge/include/mupdf), so `swift build` needs no Homebrew MuPDF
# install. Re-run this whenever bumping MUPDF_VERSION to a new upstream tag.
#
# Usage:
#   ./Vendor/build-mupdf.sh [version]
#
# The optional [version] argument overrides MUPDF_VERSION below for one-off
# builds without editing this file.
set -euo pipefail

MUPDF_VERSION="${1:-1.28.3}"
# Expected sha256 of https://mupdf.com/downloads/archive/mupdf-${MUPDF_VERSION}-source.tar.gz
# Update this whenever MUPDF_VERSION changes (the script prints the actual
# hash of whatever it downloads, so you can copy it in after reviewing).
MUPDF_SHA256="${MUPDF_SHA256:-37c3209dc0e06fa4f3781ed44839ad933a9e6143eb4731f99e069204715bcef2}"

# Architectures to build. Currently Apple Silicon only; add "x86_64" here (and
# lipo the resulting static libs together before the libtool step) if Intel
# Mac support is ever needed.
ARCHS=("arm64")
MACOS_MIN="14.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$SCRIPT_DIR/.build-tmp"
DOWNLOAD_URL="https://mupdf.com/downloads/archive/mupdf-${MUPDF_VERSION}-source.tar.gz"
TARBALL="$WORK_DIR/mupdf-${MUPDF_VERSION}-source.tar.gz"
SRC_DIR="$WORK_DIR/mupdf-${MUPDF_VERSION}"

echo "==> Building MuPDF ${MUPDF_VERSION} for: ${ARCHS[*]}"
mkdir -p "$WORK_DIR"

if [ ! -f "$TARBALL" ]; then
  echo "==> Downloading $DOWNLOAD_URL"
  curl -L --fail -o "$TARBALL" "$DOWNLOAD_URL"
fi

ACTUAL_SHA256="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$MUPDF_SHA256" ]; then
  echo "error: sha256 mismatch for $TARBALL"
  echo "  expected: $MUPDF_SHA256"
  echo "  actual:   $ACTUAL_SHA256"
  echo "If you intentionally bumped MUPDF_VERSION, verify the tarball is legitimate,"
  echo "then update MUPDF_SHA256 in this script to the 'actual' value above."
  rm -f "$TARBALL"
  exit 1
fi

if [ ! -d "$SRC_DIR" ]; then
  echo "==> Extracting $TARBALL"
  mkdir -p "$SRC_DIR"
  tar xzf "$TARBALL" -C "$SRC_DIR" --strip-components=1
fi

cd "$SRC_DIR"

LIB_PATHS=()
for ARCH in "${ARCHS[@]}"; do
  echo "==> make libs (arch=$ARCH, mujs=no, tesseract=no [default])"
  make -j"$(getconf _NPROCESSORS_ONLN)" build=release mujs=no OS=macos \
    CC="clang -arch $ARCH -mmacosx-version-min=$MACOS_MIN" \
    CXX="clang++ -arch $ARCH -mmacosx-version-min=$MACOS_MIN" \
    libs
  LIB_PATHS+=("build/release/libmupdf.a" "build/release/libmupdf-third.a")
done

OUT_DIR="$WORK_DIR/out"
mkdir -p "$OUT_DIR"
COMBINED_LIB="$OUT_DIR/libMuPDF-${ARCHS[0]}.a"

echo "==> Combining libmupdf.a + libmupdf-third.a into a single static archive"
# NOTE: if ARCHS ever includes more than one architecture, lipo the per-arch
# combined libs together into a single universal .a before this step instead
# of passing all object archives to one libtool invocation.
libtool -static -o "$COMBINED_LIB" "${LIB_PATHS[@]}"

XCFRAMEWORK_OUT="$OUT_DIR/MuPDF.xcframework"
rm -rf "$XCFRAMEWORK_OUT"
echo "==> Creating XCFramework"
xcodebuild -create-xcframework \
  -library "$COMBINED_LIB" \
  -output "$XCFRAMEWORK_OUT"

echo "==> Installing into repo"
rm -rf "$REPO_ROOT/Vendor/MuPDF.xcframework"
cp -R "$XCFRAMEWORK_OUT" "$REPO_ROOT/Vendor/MuPDF.xcframework"

rm -rf "$REPO_ROOT/Sources/MuPDFBridge/include/mupdf"
cp -R "$SRC_DIR/include/mupdf" "$REPO_ROOT/Sources/MuPDFBridge/include/mupdf"

# Sanity check: warn if upstream added a new header-guardless X-macro-style
# snippet header (like mupdf/pdf/name-table.h) that isn't yet declared
# `textual` in include/module.modulemap — Clang Modules will otherwise
# corrupt its mid-declaration textual inclusion with cryptic parse errors
# ("expected identifier") at the #include site in whatever header pulls it in.
echo "==> Checking for un-guarded headers that may need a 'textual header' entry in module.modulemap"
UNGUARDED=()
while IFS= read -r -d '' hdr; do
  if ! grep -qE '^\s*#\s*(pragma once|ifndef)' "$hdr"; then
    UNGUARDED+=("${hdr#"$REPO_ROOT/Sources/MuPDFBridge/include/"}")
  fi
done < <(find "$REPO_ROOT/Sources/MuPDFBridge/include/mupdf" -name "*.h" -print0)
for hdr in "${UNGUARDED[@]}"; do
  if ! grep -qF "\"$hdr\"" "$REPO_ROOT/Sources/MuPDFBridge/include/module.modulemap"; then
    echo "  WARNING: $hdr has no include guard and is not yet marked 'textual' in module.modulemap."
    echo "           Add: textual header \"$hdr\"  (see the existing name-table.h entry for why)."
  fi
done

# Sanity check: warn about any vendored header that isn't transitively
# #included by fitz.h/pdf.h — an `umbrella header` sweeps every physical file
# under the directory into the module regardless, so anything unreachable
# produces a "does not include header" warning at every build unless it's
# declared `exclude header` in module.modulemap (see the html.h/ucdn.h/
# helpers/* entries there for the currently-known set).
echo "==> Checking for vendored headers unreachable from fitz.h/pdf.h (would warn at build unless excluded)"
python3 - "$REPO_ROOT/Sources/MuPDFBridge/include" << 'PYEOF'
import re, sys, os
include_dir = sys.argv[1]
mupdf_dir = os.path.join(include_dir, "mupdf")
modulemap_path = os.path.join(include_dir, "module.modulemap")
modulemap = open(modulemap_path, encoding="utf-8").read()

all_headers = []
for root, _, files in os.walk(mupdf_dir):
    for f in files:
        if f.endswith(".h"):
            rel = os.path.relpath(os.path.join(root, f), mupdf_dir)
            all_headers.append(rel.replace(os.sep, "/"))

reachable = set()
def visit(relpath):
    if relpath in reachable:
        return
    full = os.path.join(mupdf_dir, relpath)
    if not os.path.isfile(full):
        return
    reachable.add(relpath)
    text = open(full, encoding="utf-8", errors="ignore").read()
    for m in re.finditer(r'#\s*include\s*["<]mupdf/([^">]+)[">]', text):
        visit(m.group(1))
visit("fitz.h")
visit("pdf.h")

unreachable = sorted(h for h in all_headers if h not in reachable)
unhandled = [h for h in unreachable if f'"mupdf/{h}"' not in modulemap]
if unhandled:
    print("  WARNING: the following headers are unreachable from fitz.h/pdf.h and not yet")
    print("           declared 'exclude header' in module.modulemap (will warn at every build):")
    for h in unhandled:
        print(f'             exclude header "mupdf/{h}"')
else:
    print("  OK: all unreachable headers are already excluded.")
PYEOF

echo "==> Done. Vendored:"
echo "  Vendor/MuPDF.xcframework ($(du -sh "$REPO_ROOT/Vendor/MuPDF.xcframework" | cut -f1))"
echo "  Sources/MuPDFBridge/include/mupdf ($(find "$REPO_ROOT/Sources/MuPDFBridge/include/mupdf" -name '*.h' | wc -l | tr -d ' ') headers)"
echo ""
echo "Update Vendor/MUPDF_VERSION and commit both paths above."
echo "(Build tree left at $WORK_DIR for inspection/reuse; safe to delete.)"
