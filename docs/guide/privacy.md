# Privacy

VectorPDF has no accounts, analytics, telemetry or crash reporting. Your documents are processed on your Mac, and nothing from them is sent to the developer.

## What uses the network

- **Update checks:** VectorPDF asks GitHub for the latest version about once a day, or when you choose Check for Updates. The request has no information about you or your documents. You can turn this off in [Settings](settings.md).
- **The Agent:** nothing leaves your Mac with the On-Device engine. [Private Cloud Compute and online models](agent-engines.md) send your question and passages from the document, and only when you ask a question. Setting up an online model also uses your key to list its models and send a short test.
- **iCloud:** your reading state is kept in your own iCloud account: where the file is, the last page and zoom, and your anchors' names, excerpts and pages. Documents, their full text and anchor thumbnails aren't uploaded.
- **Links you click** open in your browser.
- **Apple services:** Translation, Look Up, speech and OCR are provided by macOS and may download language files from Apple. Handoff shares the document and page you're reading with your other devices.

## What's stored on your Mac

VectorPDF stores your preferences, favorites, tab groups, reading positions, anchors and stamp. It also keeps an index for documents you've used with the Agent, thumbnails of anchors, and temporary working copies of documents with unsaved page edits or redactions, which it deletes when it's finished with them.

Online model API keys are stored in your login keychain.

For the full details, see the [privacy policy on GitHub](https://github.com/tomderham/vectorpdf/blob/main/PRIVACY.md).
