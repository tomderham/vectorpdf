<!-- keywords: redact, redaction, redactions, remove, black out, sensitive, SSN, credit card, email, phone, date, find and redact, PDF -->

# Redact sensitive content

Redaction permanently removes content from a PDF. VectorPDF deletes the text, image pixels and line art under the redacted area from the file, along with any annotations and form fields that touch it. It doesn't just cover them with a box, and earlier revisions aren't kept when you save.

> **Warning:** Redaction takes effect as soon as you apply it, and there's no Undo. Your original file doesn't change until you save, so to start again, close the document without saving. Keep a copy of the original, and use Save As to save the redacted version under a new name.

Press ⌥⌘R, or choose View > Show Redact Toolbar.

## Redact an area

1. Choose **Redact Region**.
2. Choose Black or White as the redact color.
3. Drag across the area to redact.

## Find and redact

1. Choose **Find & Redact**.
2. Choose what to look for:
   - **Text / Phrase**, with Match Case and Whole Word options.
   - **Custom Regular Expression**, such as `[A-Z]{3}-\d{5}`.
   - **Social Security Number (SSN)**, **Credit Card Number**, **Email Address**, **Phone Number** or **Date**. These find common formats automatically.
3. Click Find.
4. Check the matches. Click one to see it on its page, and deselect any you want to keep.
5. Choose an action:
   - **Redact** removes the content and leaves a black or white box.
   - **Remove** removes the content and leaves no box.
6. Click **Redact Selected** or **Remove Selected**.

> **Warning:** Automatic detection can miss things, especially unusual formats or text in images. Check the document before you share it. Text on scanned pages needs to be redacted with Redact Region.

## Save the result

Press ⇧⌘S to save the redacted document under a new name. Saving also deletes the document's [Agent](agent.md) search index, which could contain the removed text.
