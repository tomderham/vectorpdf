<!-- keywords: settings, preferences, options, updates, update, check for updates, browser, author, annotation author, storage, disk space, clear, remove data, delete data, uninstall -->

# Settings

Choose VectorPDF > Settings, or press ⌘,.

| Setting | What it does |
| --- | --- |
| Annotation Author | The name saved on your annotations and replies. If it's empty, VectorPDF uses your Mac user name. |
| Use Agent | Shows the [Ask About This Document](agent.md) tab in the sidebar, on macOS 26 or later. |
| AI Synthesis Engine | Chooses [what writes the Agent's answers](agent-engines.md), on macOS 27. |
| PDF Color | Sets [how pages look](pdf-colors.md): Follow System, Light, Dark or Sepia. |
| Open Links In | Chooses the browser for web links. |
| Ignored Search Patterns | Lists text that [Smart Search looks past](search.md#ignore-clutter-in-the-text). |
| Digital Stamp | Creates, changes or deletes your [stamp](stamps.md). |
| Sync reading positions with iCloud | Keeps your [page, zoom, anchors](reading-positions.md) and [recent searches](search.md) on your other Macs. |
| Storage | Shows the space VectorPDF's data takes, and [clears it](#free-up-space-or-remove-data). |
| Automatically check for updates | Checks GitHub for a new version about once a day. Click Check Now to check at any time. |

## Free up space or remove data

Settings shows, under Storage, how much space each kind of data takes:

- **Agent indexes:** what the Agent builds to answer questions about a document. Click Clear to delete them; a document is indexed again the next time you use the Agent with it. VectorPDF keeps them under 500 MB, deleting the least recently used first, and deletes a document's index when the document is gone.
- **Reading history:** each document's last page, zoom, anchors and recent searches. Click Clear to forget them, on this Mac and in iCloud.
- **Temporary files:** copies made while editing, saving, printing or exporting, and downloaded updates. VectorPDF deletes any left behind the next time it opens.

To remove everything VectorPDF has stored, click Remove All VectorPDF Data. This also removes your settings, favorites, tab groups, stamp and API keys, then quits VectorPDF. Your documents aren't touched. Save or close any document with unsaved changes first.

## Update VectorPDF

Choose VectorPDF > Check for Updates. If there's a new version, click Download. When it has downloaded, click **Quit and Open Installer**, then drag VectorPDF to your Applications folder.
