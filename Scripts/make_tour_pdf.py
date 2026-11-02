#!/usr/bin/env python3
"""Generates Resources/VectorPDF Tour.pdf, the sample document the app offers to new users.

Needs reportlab (pip install reportlab). Run it from the repository root, and commit the PDF.

Destinations use hyperref's names (equation.1, figure.1, cite.iso32000, ...) because those decide
how much context Link Peek shows.
"""
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import inch
from reportlab.pdfbase import pdfdoc
from reportlab.platypus import (BaseDocTemplate, Flowable, Frame, ListFlowable, ListItem, PageBreak,
                                PageTemplate, Paragraph, Spacer, Table, TableStyle)

BODY_FONT, BOLD_FONT, ITALIC_FONT = "Times-Roman", "Times-Bold", "Times-Italic"
LINK = "#1a4fd0"

body = ParagraphStyle("body", fontName=BODY_FONT, fontSize=12, leading=16, spaceAfter=9)
title = ParagraphStyle("title", fontName=BOLD_FONT, fontSize=24, leading=29, spaceAfter=6)
subtitle = ParagraphStyle("subtitle", fontName=ITALIC_FONT, fontSize=13, leading=17, spaceAfter=16)
heading = ParagraphStyle("heading", fontName=BOLD_FONT, fontSize=15, leading=19, spaceBefore=12,
                         spaceAfter=6, keepWithNext=1)
caption = ParagraphStyle("caption", fontName=BOLD_FONT, fontSize=11, leading=14, alignment=TA_CENTER,
                         spaceBefore=8, spaceAfter=6, keepWithNext=1)
equation = ParagraphStyle("equation", fontName=ITALIC_FONT, fontSize=13, leading=17, alignment=TA_CENTER)


def link(text, destination):
    return f'<a href="#{destination}" color="{LINK}">{text}</a>'


# reportlab writes a link's page and position, which loses the destination's name. Write the name
# instead, and list the names in the catalog's /Dests.
write_destination = pdfdoc.Destination.format
pdfdoc.Destination.format = lambda self, document: f"/{self.name}".encode()


class NamedDestinations(pdfdoc.PDFObject):
    def __init__(self, canvas):
        self.canvas = canvas

    def format(self, document):
        entries = [b"/%s %s" % (name.encode(), write_destination(destination, document))
                   for name, destination in sorted(self.canvas._destinations.items())]
        return b"<< " + b" ".join(entries) + b" >>"


class Tour(BaseDocTemplate):
    def beforeDocument(self):
        self.canv._doc.Catalog.Dests = NamedDestinations(self.canv)

    def afterFlowable(self, flowable):
        key = getattr(flowable, "outline_key", None)
        if key:
            self.canv.addOutlineEntry(flowable.getPlainText(), key, level=0)


def section(text, key):
    paragraph = Paragraph(f'<a name="{key}"/>{text}', heading)
    paragraph.outline_key = key
    return paragraph


class PlanFigure(Flowable):
    """A room plan at 1:50, drawn to scale so it can be measured in the app."""

    MM = 72 / 25.4
    WIDTH, DEPTH = 160 * MM, 100 * MM  # 8 m by 5 m at 1:50

    def wrap(self, available_width, available_height):
        return available_width, self.DEPTH + 34

    def draw(self):
        c = self.canv
        x = (self._frame._width - self.WIDTH) / 2
        y = 26
        c.setLineWidth(2.2)
        c.rect(x, y, self.WIDTH, self.DEPTH)
        door = 18 * self.MM
        c.setStrokeColor(colors.white)
        c.setLineWidth(3)
        c.line(x + 20 * self.MM, y + self.DEPTH, x + 20 * self.MM + door, y + self.DEPTH)
        c.setStrokeColor(colors.black)
        c.setLineWidth(0.8)
        c.arc(x + 20 * self.MM - door, y + self.DEPTH - door, x + 20 * self.MM + door,
              y + self.DEPTH + door, 270, 90)
        c.line(x + 20 * self.MM, y + self.DEPTH, x + 20 * self.MM, y + self.DEPTH - door)
        c.setLineWidth(0.6)
        c.line(x, y - 12, x + self.WIDTH, y - 12)
        c.line(x, y - 16, x, y - 8)
        c.line(x + self.WIDTH, y - 16, x + self.WIDTH, y - 8)
        c.setFont(BODY_FONT, 10)
        c.drawCentredString(x + self.WIDTH / 2, y - 25, "8.00 m")


def bullets(items):
    return ListFlowable([ListItem(Paragraph(item, body), leftIndent=16) for item in items],
                        bulletType="bullet", start="•", leftIndent=16)


story = [
    Paragraph("A Short Tour of VectorPDF", title),
    Paragraph("Five minutes with what sets it apart. All of it works on your own PDFs.",
              subtitle),

    section("1  Follow a reference and stay on your page", "section.1"),
    Paragraph("Hold <b>Command</b> and move the pointer over each blue reference. Its target appears "
              "where you are, and disappears when you let go.", body),
    bullets([
        f"An equation: the conversion in {link('Equation (1)', 'equation.1')}.",
        f"A figure: the plan in {link('Figure 1', 'figure.1')}.",
        f"A table: the scales in {link('Table 1', 'table.1')}.",
        f"A section: the start of {link('Section 4', 'section.4')}.",
        f"A citation: the PDF standard, {link('[1]', 'cite.iso32000')}.",
    ]),
    Paragraph(f"Hold Command and click {link('Figure 1', 'figure.1')} to open it in a window of its own, "
              "beside this one.", body),

    section("2  Search for what the page really says", "section.2"),
    Paragraph("Press <b>Command-F</b> and search for <i>end to end</i>. Smart Search finds "
              "end-to-end and the end to<br/>end that breaks across this line too. Results appear in the "
              "sidebar as they're found.", body),

    section("3  Keep your place", "section.3"),
    Paragraph("Select this sentence and press <b>Command-B</b> to save it as an anchor. Open the Anchors "
              "tab in the sidebar and click the anchor to come straight back, from anywhere in this "
              "document or in another tab.", body),
    Paragraph("Then select some text and press <b>Shift-Command-H</b> to highlight it, or press "
              "<b>Shift-Command-A</b> to show the Markup toolbar. This is your own copy of the tour, so "
              "mark it up however you like.", body),
    Paragraph("When you're ready, press <b>Command-O</b> and open a document of your own.", body),

    PageBreak(),

    section("4  Measuring a drawing", "section.4"),
    Paragraph("The rest of this document is a small worked example, there to give the references on the "
              f"first page somewhere to go. A drawing's scale relates a length on the page to the real "
              f"length, as in {link('Equation (1)', 'equation.1')}.", body),
    Table([[Paragraph('<a name="equation.1"/><i>L</i> = <i>d</i> × <i>n</i>', equation),
            Paragraph("(1)", ParagraphStyle("number", parent=body, alignment=2, spaceAfter=0))]],
          colWidths=[5.5 * inch, 1 * inch], style=TableStyle([("VALIGN", (0, 0), (-1, -1), "MIDDLE")])),
    Spacer(1, 6),
    Paragraph("Here <i>L</i> is the real length, <i>d</i> is the length measured on the drawing, and "
              "<i>n</i> is the scale's denominator. At 1:50, a line 160 mm long on the page is 8 m long "
              "in the building.", body),
    Paragraph('<a name="figure.1"/>Figure 1. A room drawn at 1:50', caption),
    PlanFigure(),
    Spacer(1, 10),
    Paragraph("This plan is drawn to scale. To try it, show the Measurement toolbar, calibrate from the "
              "8.00 m dimension, and measure the room's area.", body),

    PageBreak(),

    section("5  Common scales", "section.5"),
    Paragraph(f"{link('Table 1', 'table.1')} lists scales in common use, with what 10 mm on the page "
              f"represents. PDF stores this as a viewport with a measure dictionary {link('[1]', 'cite.iso32000')}, "
              "so other PDF apps can read a scale that's saved in the file.", body),
    Paragraph('<a name="table.1"/>Table 1. Common drawing scales', caption),
    Table([["Scale", "10 mm on the page", "Typical use"],
           ["1:5", "50 mm", "Construction details"],
           ["1:20", "200 mm", "Sections and elevations"],
           ["1:50", "500 mm", "Floor plans"],
           ["1:100", "1 m", "Building plans"],
           ["1:500", "5 m", "Site plans"]],
          colWidths=[1.1 * inch, 1.7 * inch, 2.4 * inch],
          style=TableStyle([("FONT", (0, 0), (-1, -1), BODY_FONT, 11),
                            ("FONT", (0, 0), (-1, 0), BOLD_FONT, 11),
                            ("LINEABOVE", (0, 0), (-1, 0), 1, colors.black),
                            ("LINEBELOW", (0, 0), (-1, 0), 0.6, colors.black),
                            ("LINEBELOW", (0, -1), (-1, -1), 1, colors.black),
                            ("TOPPADDING", (0, 0), (-1, -1), 4),
                            ("BOTTOMPADDING", (0, 0), (-1, -1), 4)])),

    section("References", "section.6"),
    Paragraph('<a name="cite.iso32000"/>[1] ISO 32000-2:2020, <i>Document management — Portable document '
              "format — Part 2: PDF 2.0</i>. International Organization for Standardization.", body),
]

doc = Tour("Resources/VectorPDF Tour.pdf", pagesize=letter, leftMargin=inch, rightMargin=inch,
           topMargin=inch, bottomMargin=inch, title="A Short Tour of VectorPDF", author="VectorPDF",
           invariant=1, displayDocTitle=1)
doc.addPageTemplates(PageTemplate(frames=[Frame(inch, inch, 6.5 * inch, 9 * inch, id="page", leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)]))
doc.build(story)
