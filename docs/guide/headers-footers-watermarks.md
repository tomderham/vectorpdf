<!-- keywords: header, headers, footer, footers, Chinese, Japanese, Korean, Hindi, Arabic, any language, logo, picture watermark, image watermark, page numbers, page numbering, Bates, Bates numbers, Bates numbering, watermark, watermarks, DRAFT, CONFIDENTIAL, stamp text, legal, discovery, PDF -->

# Headers, footers, Bates numbers and watermarks

You can put text at the top and bottom of pages, such as a title, page numbers or Bates numbers, and a watermark such as DRAFT or CONFIDENTIAL across them. Choose Edit > Headers, Footers and Watermark, fill in the parts you want, then click **Add**. A preview beside the settings shows the page you're reading as it will look, with its own page and Bates numbers; use the arrows under it to see other pages.

VectorPDF keeps what you chose in the document, so you can change the headers, footers and watermark later or take them off. Choose Edit > Headers, Footers and Watermark again, make your changes, then click **Update**. To take them all off, click **Remove All**.

The changes become part of the file when you [save](save.md).

## Header and footer

Type in any of the six boxes: the left, center and right of the header and of the footer. Leave a box empty to put nothing there.

To add a page number or another value that changes from page to page, click in a box, then choose from the **Insert** menu:

| Insert | Shows |
| --- | --- |
| Page Number | The page's number, counting from the first page marked. See [Pages and numbers](#pages-and-numbers). |
| Page Count | How many pages the document has |
| Bates Number | The page's Bates number |
| Date | Today's date |
| File Name | The document's file name |

Each appears in the box as a word in double angle brackets, such as `<<page>>`. For example, type `Page `, insert Page Number, type ` of `, then insert Page Count, to get "Page 3 of 12".

You can choose the font, size and color of the text, and the margins: how far the header is from the top of the page, the footer from the bottom, and both from the sides, in points (72 points is an inch).

Text can be in any language, such as Chinese, Hindi or Arabic. Where the chosen font doesn't have its characters, a font on your Mac that does is used, and the characters used are saved in the document so it looks the same everywhere.

## Watermark

A watermark is text or a picture. For text, type it; press Return for a second line. For a picture, such as a logo, choose **Picture**, click **Choose Picture**, then set its width as a share of the page's. Then choose:

- **Font** and **Color**.
- **As large as fits the page**, or a size of your own.
- **Opacity:** how strongly it shows. A light watermark leaves the page readable.
- **Angle:** horizontal, diagonal or vertical.
- **Behind the page's content:** draws the watermark under the page's text and pictures rather than over them. A page that has a background, such as a scanned page, hides a watermark behind it.

## Pages and numbers {#pages-and-numbers}

- **Pages:** all pages, odd or even pages, and from one page to another. Leave From or To empty for the first or last page.
- **First page marked is page:** the number Page Number gives the first page marked. The numbers go up by one for each page marked.
- **Bates numbers:** a prefix, such as a case or company name, the number of digits, the number to start at, and a suffix. Bates numbers go up by one for each page marked, and are padded with zeros, such as ACME-000001. Insert Bates Number in a header or footer to show them.

## Mark several files

To number a set of documents for discovery, with Bates numbers running on from one file to the next, set up the marks, then click **Apply to Other Files**. Choose the PDFs, then a folder for the marked copies; the files themselves aren't changed. They're marked in order of their names, so name them in the order they should be numbered. When it's done, VectorPDF says which Bates numbers were used, and lists any file it couldn't mark, such as one that needs a password.

## Good to know

- Headers, footers and watermarks are part of the page, not [comments](draw-and-notes.md), so they're printed and they show in other apps. They're marked as page decoration, which screen readers can skip. You can search and select their text.
- The margins are measured on the page as it's shown, so on a page that was rotated, the header is still at the top.
- Headers, footers and watermarks added by other apps, such as Adobe Acrobat, can be taken off too, if the app marked them as such (most do): when VectorPDF finds some, **Remove them** appears under Pages & Numbers, and the preview shows the page without them. Once removed, they come back only if you revert to the saved document.
- Adding them to a [digitally signed](digital-signatures.md) document changes what was signed, so its signatures become invalid.
