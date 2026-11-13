<!-- keywords: document tab, form fields, fields, signatures, signed, digital signature, certified, links, hyperlinks, URLs, web links, named destinations, destinations, contents, sidebar -->

# Form fields, signatures, links and destinations

The Document tab (a box) at the top of the sidebar lists what a document holds besides its pages. Choose what it shows from the menu at the top of the tab:

- **Layers:** see [Show and hide layers](layers.md).
- **Attachments:** see [Files attached to a PDF](attachments.md).
- **Form Fields:** every field in a form, with its value, and its signatures.
- **Links:** every link, with the text it's on and where it goes.
- **Destinations:** the named places in the document that links can point to.

Form Fields, Links and Destinations are listed only when you turn on **List form fields, links and destinations in the sidebar** in VectorPDF > Settings > General. Most documents have links, so otherwise the tab would appear for nearly every one.

The menu offers only what the document has, and the tab appears only when it has at least one of these.

## Form fields and signatures

Fields are listed page by page, by the name the form gives them. Each shows its value, and **Required** when the form says it must be filled in. Hold the pointer over a field to see its full name and type. Click a field to go to it on the page; it's outlined for a moment. To fill in fields, see [Fill in forms](forms.md). The list shows the new values as you type.

A signature field shows who signed it and when, as the signature records them, or **Not signed**. It also says whether the file was saved again after it was signed, which can change what was signed, and whether the signature certifies the document and which changes it allows.

> **Note:** VectorPDF doesn't check the signature's certificate, so it can't tell you whether a signature is valid. Use a program that validates signatures, such as Adobe Acrobat Reader, for that.

## Links

Links are listed page by page, as soon as each page is read, so a long document's first links show straight away. Use the buttons above the list to show **All** links, **Web** links only, or links **In Document**, and type in **Filter** to find a link by its text or address.

| To | Do this |
| --- | --- |
| Show a link on its page | Click it |
| Follow a link | Double-click it. A web link opens in your browser. |
| Copy a web address | Right-click the link, then choose Copy Address |

## Destinations

Destinations are named places in a document, such as `section.2` or `figure.3`. LaTeX and other programs make them for links to point to. Click a destination to go to it. To copy its name, right-click it and choose Copy Name.
