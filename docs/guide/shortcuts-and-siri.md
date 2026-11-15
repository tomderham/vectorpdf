<!-- keywords: Shortcuts, Siri, Spotlight, automation, action, actions, App Intents, ask, search, extract pages, open document, workflow -->

# Use VectorPDF with Shortcuts and Siri

VectorPDF adds actions to the Shortcuts app, so you can use them in your own shortcuts and from Spotlight and Siri.

| Action | What it does |
| --- | --- |
| Ask About Document | Asks the [Agent](agent.md) a question and returns its answer, with page citations |
| Search Document | Finds text, as the search field does, and returns each match with its page number |
| Extract Pages | Makes a new PDF from some of a PDF's pages, such as `1-3, 5` |
| Open Document | Opens a document in VectorPDF, at a page if you give one |

If you don't choose a document for Ask, Search or Extract Pages, the action uses the front document in VectorPDF.

## Use an action in a shortcut

1. Open the Shortcuts app, then create a shortcut or open one.
2. Search the actions list for VectorPDF, then drag an action into your shortcut.
3. Fill in the action. To use a file from earlier in the shortcut, such as one from Get File, click Document and choose it.

Each action passes on what it returns: the answer, the list of matches, or the new PDF. You can then send it to another action, such as Make PDF, Add to Note or Send Message.

If the VectorPDF actions don't appear, open VectorPDF once, then quit and reopen Shortcuts.

## Ask Siri

You can say or type these to Siri. Siri asks for anything else it needs, such as your question. The phrases are in English, as VectorPDF isn't translated yet, so they work when Siri's language is English:

- "Ask VectorPDF about this document"
- "Search this document in VectorPDF"
- "Extract pages in VectorPDF"
- "Open a document in VectorPDF"

You can also find the actions by typing their names in Spotlight.

## About each action

- **Ask About Document** opens the document in VectorPDF if it isn't open, behind the window you're working in. The question and answer also appear in the document's Ask About This Document tab, so you can read the sources and ask follow-up questions. It needs the Agent turned on, and answers with the engine you've chosen in [Choose how the Agent answers](agent-engines.md). Where answers can't be generated, it returns the best-matching passages.
- **Search Document** uses Smart Search and your [Ignored Search Patterns](search.md#ignore-clutter-in-the-text), with Match Case and Whole Words if you turn them on. It returns up to 100 matches, and says how many there are in all. It searches an open document as it is in VectorPDF, with its unsaved changes and only the layers shown; other documents are searched without opening them.
- **Extract Pages** lists pages and ranges with commas. A range such as `5-` runs to the last page, and `3-1` gives the pages in reverse order. It reads the file as last saved, and doesn't change it. The new PDF is named after the document and pages, such as "Report (Pages 1-3, 5).pdf".
- **Open Document** brings the document's tab to the front if it's already open.

A password-protected document must be open in VectorPDF, with its password entered, before Search Document can search it. Extract Pages can't use password-protected documents.

> **Note:** What an action returns goes to Shortcuts or Siri, and from there to whatever your shortcut does next. Ask About Document sends only what the Agent would send when you ask in VectorPDF. See [Privacy](privacy.md).
