# Privacy

VectorPDF is a document reader, and the documents you open are yours. It has no accounts, no analytics, no telemetry, and no crash reporting. The app does not send your documents or anything extracted from them to the developer, or to any third party unless you choose an online model for the Agent tab (see below).

This page lists everything the app does that involves the network or stores data.

## Network access

**Update checks.** VectorPDF asks the GitHub API (`api.github.com`) for the latest release of this repository: automatically about once a day, or when you choose *Check for Updates*. The request contains no information about you or your documents. Like any web request, it reveals your IP address to GitHub. If you accept an update, the DMG is downloaded from GitHub to the temporary folder (see below) and opened for you to install. Turn off automatic checks in **Settings → Automatically check for updates**.

**Agent tab: Private Cloud Compute (optional).** The Agent tab answers questions about the open document. It finds relevant passages on your Mac using Apple's on-device language embeddings. To write an answer, it uses Apple Intelligence:
- **On-Device** runs entirely on your Mac.
- **Private Cloud Compute** (macOS 27, in builds signed with Apple's Private Cloud Compute entitlement; the downloadable DMG isn't, so it always answers on-device) sends your question and the selected passages to Apple's Private Cloud Compute servers. Apple says this data is used only to fulfill the request, is not stored, and is not accessible to Apple. See [Apple's Private Cloud Compute documentation](https://security.apple.com/documentation/private-cloud-compute).
- **Online Model (your API key)** (macOS 27) sends your question, the selected passages (or the whole text of a short document), and the earlier questions and answers in the conversation to the service you choose (OpenAI, Google Gemini, or OpenRouter), using your own API key. That service's privacy policy and terms apply, and requests are billed to your account with it. Your API key is stored in your Mac's login keychain and sent only to that service. VectorPDF also uses the key to ask the service for its list of models when you enter it, and sends a short test request when you choose a model. If the service can't answer, VectorPDF answers on-device.
  - **Free Gemini keys:** under [Google's Gemini API terms](https://ai.google.dev/gemini-api/terms), Google uses what you send to its free (unpaid) service to improve its products, and human reviewers may read it. Google asks you not to send sensitive, confidential, or personal information to the free service. This doesn't apply to keys from a Cloud project with billing enabled, or to use in the EEA, Switzerland, or the UK.

Choose the engine in **Settings → AI Synthesis Engine**, or turn the Agent tab off entirely with **Settings → Use Agent**. Apart from the online model setup checks described above, nothing is sent until you ask a question.

**iCloud sync of reading positions.** When you're signed in to iCloud, VectorPDF also keeps each document's reading state in Apple's iCloud key-value store, so another Mac signed in to the same Apple Account opens it where you left off. For each document you open, that state is:
- where the file is: its path inside iCloud Drive or a cloud-storage folder (Dropbox, Google Drive, OneDrive, Box), or its full path for other files
- the last page and zoom
- your anchors: their names, the short text excerpt each one shows, and the page they point to

The document, its full text, and anchor thumbnails are not uploaded. The data goes only to your own iCloud account, under Apple's [iCloud terms](https://www.apple.com/legal/internet-services/icloud/), and is not accessible to the developer. To keep it on your Mac, turn off **Settings → Sync reading positions with iCloud**. That also deletes VectorPDF's entries from your iCloud.

**Links you click.** Opening a web link in a PDF hands it to your default browser.

**Apple system services.** Translation, Look Up, text-to-speech, and OCR (making scanned pages searchable) are provided by Apple's frameworks (Translation, Dictionary, speech synthesis, and Vision), under Apple's terms. These frameworks may download language assets from Apple. Handoff advertises the document you're reading, and your page in it, to your other devices signed in to the same Apple Account, through Apple's Handoff service.

## Data stored on your Mac

- **Preferences, favorites, and tab groups**: in the app's preferences (`UserDefaults`). Recent documents are kept by macOS, as for any document app.
- **Reading positions and anchors**: per document, in the app's preferences, and synced through iCloud unless you turn that off (see above).
- **Saved signature image**: in the app's preferences.
- **Agent search index**: `~/Library/Application Support/VectorPDF/SemanticIndex/`. Text embeddings of documents you've used the Agent tab with, so they don't need re-indexing. A document's index is deleted when you redact or save it.
- **Anchor thumbnails**: `~/Library/Caches/VectorPDFSnapshotThumbnails/`.
- **Temporary files**: in your user account's temporary folder. Open it with `open "$TMPDIR"` in Terminal; it's under `/var/folders/`, not `/tmp`. Every name starts with `VectorPDF`:
  - `VectorPDF-working-<id>.pdf`: a working copy of a document with unsaved page edits or redactions. It holds the whole document as edited so far.
  - `VectorPDF-save-<id>-<name>.pdf`, `VectorPDF-flatten-<id>.pdf`, `VectorPDF-print-<id>.pdf`, and `VectorPDF-docx-<id>` folders: short-lived copies made while saving, flattening, printing, or exporting to Word.
  - `VectorPDF_Update.dmg`: the last downloaded update.

  VectorPDF deletes the working and short-lived copies when it's done with them (the update stays until the next one replaces it), but a crash or forced quit can leave some behind. With VectorPDF closed, they're safe to delete: `rm -rf "$TMPDIR"/VectorPDF*`.

To remove everything, quit VectorPDF, delete the folders and temporary files above, and run `defaults delete com.thomasderham.vectorpdf` in Terminal. Turn off iCloud sync in Settings first if you also want VectorPDF's entries removed from iCloud.

## Questions

Open an issue at <https://github.com/tomderham/vectorpdf/issues>. The source code is public, so every claim on this page can be checked.
