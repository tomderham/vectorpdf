// Replaces every letter on every page of a PDF with a pseudo-random letter of the same case and
// a similar width from the same font, keeping digits, punctuation, spacing and layout. It makes
// a test fixture with a real document's layout (columns, tables, line numbers) but none of its
// words. The replacement is chosen per occurrence (not a fixed cipher), so the original text
// can't be recovered. Metadata, outlines and annotations are removed.
//
// Usage: mutool run scramble_text.js <input.pdf> <output.pdf> [seed]

var input = scriptArgs[0], output = scriptArgs[1];
var seed = scriptArgs.length > 2 ? parseInt(scriptArgs[2], 10) : 802;

function random() {   // Park–Miller: deterministic for a given seed, exact in doubles (MuJS has no Math.imul)
    seed = (seed * 16807) % 2147483647;
    return (seed - 1) / 2147483646;
}

function bytesOf(buffer) {
    var out = [];
    for (var i = 0, n = buffer.getLength(); i < n; i++) out.push(buffer.readByte(i));
    return out;
}

function textOf(bytes) {
    var s = "";
    for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
    return s;
}

// Character codes -> Unicode, from a ToUnicode CMap (bfchar and bfrange entries).
function parseToUnicode(stream) {
    var map = {};
    var text = textOf(bytesOf(stream.readStream()));
    var hex = function (h) { return parseInt(h, 16); };
    var sections = text.split(/begin(bfchar|bfrange)/);
    for (var i = 1; i < sections.length; i += 2) {
        var body = sections[i + 1].split(/endbf/)[0];
        if (sections[i] === "bfchar") {
            var re = /<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>/g, m;
            while ((m = re.exec(body))) map[hex(m[1])] = hex(m[2].slice(0, 4));
        } else {
            var rr = /<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<([0-9A-Fa-f]+)>|\[([^\]]*)\])/g, r;
            while ((r = rr.exec(body))) {
                var lo = hex(r[1]), hi = hex(r[2]);
                if (r[4] !== undefined) {
                    var start = hex(r[4].slice(0, 4));
                    for (var c = lo; c <= hi; c++) map[c] = start + (c - lo);
                } else {
                    var items = r[5].match(/<([0-9A-Fa-f]+)>/g) || [];
                    for (var k = 0; k < items.length && lo + k <= hi; k++) map[lo + k] = hex(items[k].slice(1, 5));
                }
            }
        }
    }
    return map;
}

// Glyph widths by character code, for simple and CID fonts.
function parseWidths(font) {
    var widths = {};
    if (font.get("Subtype").asName() === "Type0") {
        var desc = font.get("DescendantFonts").get(0);
        var w = desc.get("W");
        if (w && w.isArray()) {
            for (var i = 0; i < w.length;) {
                var first = w.get(i).asNumber(), next = w.get(i + 1);
                if (next.isArray()) {
                    for (var j = 0; j < next.length; j++) widths[first + j] = next.get(j).asNumber();
                    i += 2;
                } else {
                    var last = next.asNumber(), width = w.get(i + 2).asNumber();
                    for (var c = first; c <= last; c++) widths[c] = width;
                    i += 3;
                }
            }
        }
    } else {
        var fw = font.get("Widths"), fc = font.get("FirstChar");
        if (fw && fw.isArray()) for (var k = 0; k < fw.length; k++) widths[fc.asNumber() + k] = fw.get(k).asNumber();
    }
    return widths;
}

// For each font: its code width (1 or 2 bytes) and, per case, the letter codes it has.
var fontInfoCache = {};
function fontInfo(font) {
    var key = font.isIndirect() ? font.asIndirect() : String(Math.random());
    if (fontInfoCache[key]) return fontInfoCache[key];
    var isCID = font.get("Subtype").asName() === "Type0";
    var toUnicode = {};
    var tu = font.get("ToUnicode");
    if (tu && tu.isStream()) toUnicode = parseToUnicode(tu);
    else if (!isCID) for (var c = 32; c < 256; c++) toUnicode[c] = c;   // WinAnsi letters are ASCII
    var widths = parseWidths(font);
    var lower = [], upper = [];
    for (var code in toUnicode) {
        var u = String.fromCharCode(toUnicode[code]);
        if (!/[A-Za-z]/.test(u) || widths[code] === undefined) continue;
        (u === u.toLowerCase() ? lower : upper).push({ code: parseInt(code, 10), width: widths[code] });
    }
    var info = { bytes: isCID ? 2 : 1, toUnicode: toUnicode, widths: widths, lower: lower, upper: upper };
    fontInfoCache[key] = info;
    return info;
}

function replacementFor(info, code) {
    var u = info.toUnicode[code];
    if (u === undefined) return code;
    var ch = String.fromCharCode(u);
    if (!/[A-Za-z]/.test(ch)) return code;
    var pool = ch === ch.toLowerCase() ? info.lower : info.upper;
    var width = info.widths[code];
    var close = pool.filter(function (g) { return Math.abs(g.width - width) <= Math.max(40, width * 0.15); });
    if (close.length === 0) return code;
    return close[Math.floor(random() * close.length)].code;
}

// --- Content stream tokenizer: enough to find text strings and the font in use. ---

function isWhite(b) { return b === 0 || b === 9 || b === 10 || b === 12 || b === 13 || b === 32; }
function isDelim(b) { return b === 40 || b === 41 || b === 60 || b === 62 || b === 91 || b === 93 || b === 123 || b === 125 || b === 47 || b === 37; }

function readLiteral(bytes, i) {   // bytes[i] === '('; returns [decoded bytes, next index]
    var out = [], depth = 1;
    i++;
    while (i < bytes.length) {
        var b = bytes[i++];
        if (b === 92) {
            var e = bytes[i++];
            if (e >= 48 && e <= 55) {
                var v = e - 48;
                for (var k = 0; k < 2 && bytes[i] >= 48 && bytes[i] <= 55; k++) v = v * 8 + bytes[i++] - 48;
                out.push(v & 255);
            } else if (e === 110) out.push(10);
            else if (e === 114) out.push(13);
            else if (e === 116) out.push(9);
            else if (e === 98) out.push(8);
            else if (e === 102) out.push(12);
            else if (e === 13) { if (bytes[i] === 10) i++; }
            else if (e === 10) { }
            else out.push(e);
        } else if (b === 40) { depth++; out.push(b); }
        else if (b === 41) { if (--depth === 0) break; out.push(b); }
        else out.push(b);
    }
    return [out, i];
}

function readHex(bytes, i) {   // bytes[i] === '<'
    var digits = "";
    i++;
    while (i < bytes.length && bytes[i] !== 62) { if (!isWhite(bytes[i])) digits += String.fromCharCode(bytes[i]); i++; }
    if (digits.length % 2) digits += "0";
    var out = [];
    for (var k = 0; k < digits.length; k += 2) out.push(parseInt(digits.slice(k, k + 2), 16));
    return [out, i + 1];
}

function hexString(bytes) {
    var s = "<";
    for (var i = 0; i < bytes.length; i++) s += (bytes[i] < 16 ? "0" : "") + bytes[i].toString(16);
    return s + ">";
}

function scrambleString(bytes, info) {
    if (!info) return bytes;
    var out = [];
    for (var i = 0; i + info.bytes <= bytes.length; i += info.bytes) {
        var code = info.bytes === 2 ? (bytes[i] << 8) | bytes[i + 1] : bytes[i];
        var r = replacementFor(info, code);
        if (info.bytes === 2) out.push(r >> 8, r & 255); else out.push(r);
    }
    return out;
}

// Rewrites a content stream, returning the new bytes as a string. `fonts` is the resources'
// /Font dictionary.
function scrambleContent(bytes, fonts) {
    var out = "", i = 0, current = null, lastName = null;
    while (i < bytes.length) {
        var b = bytes[i];
        if (b === 37) {   // comment
            while (i < bytes.length && bytes[i] !== 10 && bytes[i] !== 13) i++;
        } else if (b === 40) {
            var lit = readLiteral(bytes, i);
            out += hexString(scrambleString(lit[0], current));
            i = lit[1];
        } else if (b === 60 && bytes[i + 1] !== 60) {
            var hx = readHex(bytes, i);
            out += hexString(scrambleString(hx[0], current));
            i = hx[1];
        } else if (b === 60 || b === 62) {
            out += String.fromCharCode(b, bytes[i + 1]);
            i += 2;
        } else if (b === 47) {   // name
            var start = i++;
            while (i < bytes.length && !isWhite(bytes[i]) && !isDelim(bytes[i])) i++;
            var name = textOf(bytes.slice(start, i));
            lastName = name.slice(1);
            out += name;
        } else if (isWhite(b) || isDelim(b)) {
            out += String.fromCharCode(b);
            i++;
        } else {   // number or operator
            var s = i;
            while (i < bytes.length && !isWhite(bytes[i]) && !isDelim(bytes[i])) i++;
            var tok = textOf(bytes.slice(s, i));
            if (tok === "Tf" && fonts && lastName) {
                var f = fonts.get(lastName);
                current = f && !f.isNull() ? fontInfo(f) : null;
            } else if (tok === "BI") {   // inline image: copy through to EI untouched
                var end = textOf(bytes).indexOf("EI", i);
                out += tok + textOf(bytes.slice(i, end + 2));
                i = end + 2;
                continue;
            }
            out += tok;
        }
    }
    return out;
}

function stringToBuffer(s) {
    var buf = new Buffer();
    for (var i = 0; i < s.length; i++) buf.writeByte(s.charCodeAt(i));
    return buf;
}

var seenForms = {};
function scrambleResources(resources) {
    if (!resources || resources.isNull()) return;
    var xobjects = resources.get("XObject");
    if (xobjects && xobjects.isDictionary()) {
        xobjects.forEach(function (xo) {
            if (!xo.isStream() || xo.get("Subtype").asName() !== "Form") return;
            var id = xo.asIndirect();
            if (seenForms[id]) return;
            seenForms[id] = true;
            var res = xo.get("Resources");
            xo.writeStream(stringToBuffer(scrambleContent(bytesOf(xo.readStream()), res.get("Font"))));
            scrambleResources(res);
        });
    }
}

var doc = Document.openDocument(input);
for (var p = 0; p < doc.countPages(); p++) {
    var page = doc.findPage(p);
    var resources = page.get("Resources");
    var fonts = resources.get("Font");
    var contents = page.get("Contents");
    var streams = contents.isArray() ? [] : [contents];
    if (contents.isArray()) for (var k = 0; k < contents.length; k++) streams.push(contents.get(k));
    // Concatenate (a string can span stream boundaries), then store as one stream.
    var all = [];
    streams.forEach(function (st) { all = all.concat(bytesOf(st.readStream())); all.push(10); });
    page.put("Contents", doc.addStream(stringToBuffer(scrambleContent(all, fonts)), {}));
    scrambleResources(resources);
    page.delete("Annots");
    page.delete("PieceInfo");
    page.delete("Metadata");
}
var root = doc.getTrailer().get("Root");
["Outlines", "Metadata", "Names", "OpenAction", "PageLabels", "StructTreeRoot", "MarkInfo", "AcroForm", "PieceInfo"].forEach(function (k) { root.delete(k); });
doc.getTrailer().delete("Info");
doc.save(output, "garbage=4,compress,sanitize");
