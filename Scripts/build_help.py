#!/usr/bin/env python3
"""Builds VectorPDF's Apple Help book from docs/guide/*.md.

Uses only the Python standard library, plus Xcode's hiutil for the search indexes.
The converter supports just the Markdown the guide uses: headings, paragraphs, bold,
italics, inline code, links, images, bullet and numbered lists (nested by two spaces),
tables, fenced code blocks and blockquotes.

Tips only draws its own sidebar for Apple's online books, so the book draws one in the page and
connects it to the sidebar button in Tips' toolbar.
"""

import argparse
import html
import json
import plistlib
import re
import shutil
import subprocess
from pathlib import Path

BOOK_TITLE = "VectorPDF User Guide"
ICON = "icon_256x256.png"

PAGE_TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
{apple_title}<title>{title}</title>
<link rel="stylesheet" href="style.css">
</head>
<body{body_class}>
<aside id="toc"></aside>
<section>
<main>
{body}
</main>
</section>
<script src="toc.js"></script>
</body>
</html>
"""

STYLESHEET = """:root {
    color-scheme: light dark;
    --sidebar: #ececec;
    --selected: rgba(0, 0, 0, 0.11);
    --hover: rgba(0, 0, 0, 0.05);
    --link: #0066cc;
    --line: rgba(127, 127, 127, 0.3);
    --note: rgba(127, 127, 127, 0.11);
    --warning: rgba(255, 159, 10, 0.16);
    --text: #1d1d1f;
}
@media (prefers-color-scheme: dark) {
    :root {
        --sidebar: #2b2b2d; --selected: rgba(255, 255, 255, 0.14); --hover: rgba(255, 255, 255, 0.06);
        --link: #4da3ff; --text: #f5f5f7;
    }
}
html, body { height: 100%; margin: 0; }
body { display: flex; color: var(--text); font: 15px/1.5 -apple-system, sans-serif; }
a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }

#toc { flex: 0 0 245px; box-sizing: border-box; height: 100%; padding: 8px; overflow-y: auto;
       background: var(--sidebar); border-right: 1px solid var(--line); font-size: 14px; line-height: 1.3;
       -webkit-user-select: none; user-select: none; }
body.toc-hidden #toc { display: none; }
#toc ul { list-style: none; margin: 0; padding: 0; }
#toc a, #toc summary { display: block; position: relative; padding: 7px 10px 7px 20px; margin-bottom: 1px;
                       border-radius: 8px; color: inherit; cursor: default; }
#toc details a { padding-left: 32px; }
#toc a:hover, #toc summary:hover { background: var(--hover); text-decoration: none; }
#toc .current, #toc .current:hover { background: var(--selected); }
#toc summary { list-style: none; }
#toc summary::-webkit-details-marker { display: none; }
#toc summary::before { content: ""; position: absolute; left: 8px; top: 12px; width: 5px; height: 5px;
                       border-top: 1.5px solid; border-right: 1.5px solid; opacity: 0.6;
                       transform: rotate(45deg); transition: transform 0.12s; }
#toc details[open] > summary::before { transform: translateY(-1px) rotate(135deg); }
@media (max-width: 640px) { #toc { display: none; } }

section { flex: 1; min-width: 0; height: 100%; overflow-y: auto; box-sizing: border-box; padding: 28px 48px 64px; }
main { max-width: 680px; margin: 0 auto; }
h1 { font-size: 2.1em; line-height: 1.15; letter-spacing: -0.01em; margin: 0.4em 0 0.6em; }
h2 { font-size: 1.35em; line-height: 1.25; margin-top: 1.9em; }
h3 { font-size: 1.05em; margin-top: 1.5em; }
li { margin: 0.25em 0; }
code { font: 0.92em ui-monospace, Menlo, monospace; }
pre { padding: 10px 12px; overflow-x: auto; background: var(--note); border-radius: 8px; }
table { border-collapse: collapse; width: 100%; margin: 1em 0; }
th, td { text-align: left; vertical-align: top; padding: 6px 10px; border-bottom: 1px solid var(--line); }
img { max-width: 100%; height: auto; }
blockquote { margin: 1.2em 0; padding: 10px 14px; border-radius: 10px; background: var(--note); }
blockquote p { margin: 0; }
blockquote.warning { background: var(--warning); }

.landing h1 { font-size: 3em; margin: 0 0 0.1em; }
.landing .hero { display: flex; align-items: center; justify-content: space-between; gap: 24px;
                 padding: 16px 0 28px; margin-bottom: 8px; border-bottom: 1px solid var(--line); }
.landing .hero p { margin: 0; font-size: 1.4em; }
.landing .hero img { width: 128px; height: 128px; }
"""

# Fills in the sidebar. It's a script so that the sidebar's text isn't indexed on every page,
# which would make every page match a search for any page's title. Each page is a full load, so
# the sidebar's state is kept in session storage.
TOC_SCRIPT = """document.getElementById("toc").innerHTML = {toc};
var page = location.pathname.split("/").pop();
document.querySelectorAll("#toc a").forEach(function (a) {{
    if (a.getAttribute("href") !== page) return;
    a.className = "current";
    var group = a.closest("details");
    if (group) group.open = true;
}});

function load(key) {{
    try {{ return sessionStorage.getItem(key); }} catch (e) {{ return null; }}
}}
function store(key, value) {{
    try {{ sessionStorage.setItem(key, value); }} catch (e) {{}}
}}
function openGroups() {{
    try {{ return JSON.parse(load("openGroups")) || []; }} catch (e) {{ return []; }}
}}
document.querySelectorAll("#toc details").forEach(function (group) {{
    var name = group.querySelector("summary").textContent;
    if (openGroups().indexOf(name) >= 0) group.open = true;
    group.addEventListener("toggle", function () {{
        var names = openGroups().filter(function (n) {{ return n !== name; }});
        if (group.open) names.push(name);
        store("openGroups", JSON.stringify(names));
    }});
}});

var toc = document.getElementById("toc");
toc.scrollTop = Number(load("tocScroll")) || 0;
toc.addEventListener("scroll", function () {{ store("tocScroll", toc.scrollTop); }});

function setSidebarHidden(hidden) {{
    document.body.classList.toggle("toc-hidden", hidden);
    store("tocHidden", hidden ? "true" : "false");
}}
setSidebarHidden(load("tocHidden") === "true");
if ("HelpViewer" in window) {{
    window.HelpViewer.showTOCButton(true,
        function () {{ setSidebarHidden(false); }},
        function () {{ setSidebarHidden(true); }});
}}
"""


def inline(text):
    code_spans = []

    def stash_code(match):
        code_spans.append(f"<code>{html.escape(match.group(1), quote=False)}</code>")
        return f"\0{len(code_spans) - 1}\0"

    def convert_link(match):
        target = match.group(2)

        # Guide pages link to each other as .md, so they work on GitHub too
        if not re.match(r"[a-z]+:", target):
            target = re.sub(r"(?:^|(?<=/))README\.md", "index.html", target)
            target = re.sub(r"\.md(#|$)", r".html\1", target)

        return f'<a href="{html.escape(target)}">{match.group(1)}</a>'

    text = re.sub(r"`([^`]+)`", stash_code, text)
    text = html.escape(text, quote=False)
    text = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)\)", r'<img alt="\1" src="\2">', text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", convert_link, text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*([^*\s][^*]*)\*(?![\w*])", r"<em>\1</em>", text)
    return re.sub(r"\0(\d+)\0", lambda match: code_spans[int(match.group(1))], text)


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", re.sub(r"[*`]", "", text).lower()).strip("-")


def parse_list(lines, start, indent):
    pattern = re.compile(r"^( *)([-*]|\d+\.) +(.*)$")
    tag = "ol" if pattern.match(lines[start]).group(2)[0].isdigit() else "ul"
    output = [f"<{tag}>"]
    i = start

    while i < len(lines):
        match = pattern.match(lines[i])

        if match is None or len(match.group(1)) < indent:
            break

        if len(match.group(1)) > indent:
            nested, i = parse_list(lines, i, len(match.group(1)))
            output[-1] = output[-1].removesuffix("</li>") + "\n" + nested + "</li>"
            continue

        output.append(f"<li>{inline(match.group(3))}</li>")
        i += 1

    output.append(f"</{tag}>")
    return "\n".join(output), i


def table_cells(line):
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def convert(markdown):
    lines = markdown.splitlines()
    output = []
    i = 0

    while i < len(lines):
        line = lines[i]

        if not line.strip():
            i += 1
        elif line.startswith("```"):
            end = lines.index("```", i + 1)
            code = html.escape("\n".join(lines[i + 1:end]), quote=False)
            output.append(f"<pre><code>{code}</code></pre>")
            i = end + 1
        elif (heading := re.match(r"^(#{1,3}) +(.*)$", line)):
            level = len(heading.group(1))
            text = heading.group(2)
            output.append(f'<h{level} id="{slug(text)}">{inline(text)}</h{level}>')
            i += 1
        elif re.match(r"^ *([-*]|\d+\.) +", line):
            block, i = parse_list(lines, i, 0)
            output.append(block)
        elif line.startswith("> "):
            quote = []

            while i < len(lines) and lines[i].startswith("> "):
                quote.append(lines[i][2:].strip())
                i += 1

            text = " ".join(quote)
            css = ' class="warning"' if text.startswith("**Warning") else ""
            output.append(f"<blockquote{css}><p>{inline(text)}</p></blockquote>")
        elif line.startswith("|"):
            header = table_cells(line)
            i += 2
            rows = []

            while i < len(lines) and lines[i].startswith("|"):
                rows.append(table_cells(lines[i]))
                i += 1

            head = "".join(f"<th>{inline(cell)}</th>" for cell in header)
            body = "".join("<tr>" + "".join(f"<td>{inline(cell)}</td>" for cell in row) + "</tr>\n" for row in rows)
            output.append(f"<table>\n<thead><tr>{head}</tr></thead>\n<tbody>\n{body}</tbody>\n</table>")
        else:
            paragraph = []

            while i < len(lines) and lines[i].strip() and not re.match(r"^(#{1,3} |```|> |\||( *)([-*]|\d+\.) +)", lines[i]):
                paragraph.append(lines[i].strip())
                i += 1

            output.append(f"<p>{inline(' '.join(paragraph))}</p>")

    return "\n".join(output)


def toc_html(guide_dir):
    """The index page's headings and links are the sidebar's groups and pages."""
    output = ['<ul><li><a href="index.html">Welcome</a></li>']
    in_group = False

    for line in (guide_dir / "README.md").read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            if in_group:
                output.append("</ul></details></li>")
            output.append(f"<li><details><summary>{html.escape(line[3:])}</summary><ul>")
            in_group = True
        elif (entry := re.match(r"^- \[([^\]]+)\]\(([^)]+)\.md\)", line)):
            output.append(f'<li><a href="{entry.group(2)}.html">{html.escape(entry.group(1))}</a></li>')

    return "".join(output) + "</ul></details></li></ul>"


def page_title(markdown, fallback):
    match = re.search(r"^# +(.*)$", markdown, re.MULTILINE)
    return match.group(1) if match else fallback


def landing(markdown):
    """The index page's title and first paragraph form a hero beside the app icon."""
    title, tagline, rest = markdown.split("\n\n", 2)
    return (f'<div class="hero"><div><h1>{html.escape(title[2:])}</h1><p>{inline(tagline)}</p></div>'
            f'<img src="{ICON}" alt=""></div>\n{convert(rest)}')


def check_links(guide_dir):
    """Fails the build on a link to a page or heading that doesn't exist, or a page not in the sidebar."""
    problems = []
    pages = {path.name: path.read_text(encoding="utf-8") for path in guide_dir.glob("*.md")}
    anchors = {name: {slug(h) for h in re.findall(r"^#{1,3} +(.*)$", text, re.MULTILINE)} for name, text in pages.items()}

    for name, text in pages.items():
        for target in re.findall(r"\]\(([^)\s]+)\)", text):
            if re.match(r"[a-z]+:", target):
                continue

            page, _, fragment = target.partition("#")
            page = page or name

            if page not in pages:
                problems.append(f"{name}: no page {page}")
            elif fragment and fragment not in anchors[page]:
                problems.append(f"{name}: no heading #{fragment} in {page}")

    for name in pages:
        if name != "README.md" and f"({name})" not in pages["README.md"]:
            problems.append(f"{name}: not listed in README.md")

    if problems:
        raise SystemExit("error: problems in the guide:\n  " + "\n  ".join(problems))


def build_book(guide_dir, resources_dir, version, bundle_id, icon):
    check_links(guide_dir)

    book = resources_dir / "VectorPDF.help"
    shutil.rmtree(book, ignore_errors=True)

    pages_dir = book / "Contents" / "Resources" / "en.lproj"
    pages_dir.mkdir(parents=True)

    with open(book / "Contents" / "Info.plist", "wb") as info:
        plistlib.dump({
            "CFBundleDevelopmentRegion": "en",
            "CFBundleIdentifier": bundle_id,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": BOOK_TITLE,
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": version,
            "CFBundleSignature": "hbwr",
            "CFBundleVersion": version,
            "HPDBookAccessPath": "index.html",
            "HPDBookCSIndexPath": "VectorPDF.cshelpindex",
            "HPDBookIconPath": ICON,
            "HPDBookIndexPath": "VectorPDF.helpindex",
            "HPDBookTitle": BOOK_TITLE,
            "HPDBookType": "3",
        }, info)

    (pages_dir / "style.css").write_text(STYLESHEET, encoding="utf-8")
    (pages_dir / "toc.js").write_text(TOC_SCRIPT.format(toc=json.dumps(toc_html(guide_dir))), encoding="utf-8")
    shutil.copy(icon, pages_dir / ICON)

    for source in sorted(guide_dir.glob("*.md")):
        markdown = source.read_text(encoding="utf-8")
        title = page_title(markdown, source.stem)
        is_index = source.name == "README.md"
        target = pages_dir / ("index.html" if is_index else source.with_suffix(".html").name)

        target.write_text(PAGE_TEMPLATE.format(
            # The help viewer uses this tag to find the book's title page
            apple_title=f'<meta name="AppleTitle" content="{BOOK_TITLE}">\n' if is_index else "",
            title=html.escape(title),
            body_class=' class="landing"' if is_index else "",
            body=landing(markdown) if is_index else convert(markdown)), encoding="utf-8")

    images = guide_dir / "images"

    if images.is_dir():
        shutil.copytree(images, pages_dir / "images")

    # Spotlight-format index (required since macOS 10.14), plus the older format
    subprocess.run(["hiutil", "-I", "corespotlight", "-Caf", str(pages_dir / "VectorPDF.cshelpindex"), str(pages_dir)], check=True)
    subprocess.run(["hiutil", "-I", "lsm", "-Caf", str(pages_dir / "VectorPDF.helpindex"), str(pages_dir)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--guide", type=Path, required=True, help="folder containing the guide's Markdown files")
    parser.add_argument("--resources", type=Path, required=True, help="the app bundle's Resources folder")
    parser.add_argument("--version", required=True, help="VectorPDF version")
    parser.add_argument("--bundle-id", required=True, help="the help book's bundle identifier")
    parser.add_argument("--icon", type=Path, required=True, help="PNG of the app icon")
    args = parser.parse_args()

    build_book(args.guide, args.resources, args.version, args.bundle_id, args.icon)


if __name__ == "__main__":
    main()
