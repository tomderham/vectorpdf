<!-- keywords: Kurzbefehle, Siri, Spotlight, Automatisierung, Aktion, Aktionen, fragen, suchen, Seiten extrahieren, Dokument öffnen, Arbeitsablauf, Shortcuts, automation, action, actions, App Intents, ask, search, extract pages, open document, workflow -->
<!-- source: 0598b760c342 -->

# VectorPDF mit Kurzbefehlen und Siri verwenden

VectorPDF fügt der App „Kurzbefehle“ Aktionen hinzu, sodass du sie in deinen eigenen Kurzbefehlen sowie über Spotlight und Siri verwenden kannst.

| Aktion | Funktion |
| --- | --- |
| Ask About Document | Stellt dem [Agenten](agent.md) eine Frage und gibt seine Antwort mit Seitenangaben zurück |
| Search Document | Findet Text wie das Suchfeld und gibt jeden Treffer mit seiner Seitenzahl zurück |
| Extract Pages | Erstellt ein neues PDF aus einigen Seiten eines PDFs, etwa `1-3, 5` |
| Open Document | Öffnet ein Dokument in VectorPDF, auf einer Seite, wenn du eine angibst |

Wenn du für Ask, Search oder Extract Pages kein Dokument wählst, verwendet die Aktion das vorderste Dokument in VectorPDF.

## Eine Aktion in einem Kurzbefehl verwenden

1. Öffne die App „Kurzbefehle“ und erstelle oder öffne einen Kurzbefehl.
2. Suche in der Aktionsliste nach VectorPDF und ziehe eine Aktion in deinen Kurzbefehl.
3. Fülle die Aktion aus. Um eine Datei aus einem früheren Schritt des Kurzbefehls zu verwenden, etwa aus einer Aktion, die eine Datei abruft, klicke auf „Document“ und wähle sie aus.

Jede Aktion gibt weiter, was sie zurückgibt: die Antwort, die Liste der Treffer oder das neue PDF. Du kannst es dann an eine andere Aktion übergeben, etwa eine, die ein PDF erstellt, eine Notiz ergänzt oder eine Nachricht sendet.

Wenn die Aktionen von VectorPDF nicht erscheinen, öffne VectorPDF einmal, beende dann „Kurzbefehle“ und öffne die App erneut.

## Siri fragen

Du kannst Siri diese Sätze sagen oder eintippen. Siri fragt nach allem, was sonst noch nötig ist, etwa nach deiner Frage. Die Sätze sind auf Englisch, da VectorPDF noch nicht übersetzt ist; sie funktionieren also, wenn Siri auf Englisch eingestellt ist:

- "Ask VectorPDF about this document"
- "Search this document in VectorPDF"
- "Extract pages in VectorPDF"
- "Open a document in VectorPDF"

Du findest die Aktionen auch, indem du ihre Namen in Spotlight eingibst.

## Die einzelnen Aktionen

- **Ask About Document** öffnet das Dokument in VectorPDF, falls es nicht geöffnet ist, hinter dem Fenster, in dem du arbeitest. Frage und Antwort erscheinen auch im Tab „Ask About This Document“ des Dokuments, sodass du die Quellen lesen und Folgefragen stellen kannst. Der Agent muss eingeschaltet sein, und die Antwort kommt von der Engine, die du unter [Festlegen, wie der Agent antwortet](agent-engines.md) gewählt hast. Wenn keine Antworten erstellt werden können, gibt die Aktion die am besten passenden Textstellen zurück.
- **Search Document** verwendet Smart Search und deine [Ignored Search Patterns](search.md#ignore-clutter-in-the-text), mit „Match Case“ und „Whole Words“, wenn du sie einschaltest. Die Aktion gibt bis zu 100 Treffer zurück und sagt, wie viele es insgesamt sind. Ein geöffnetes Dokument wird so durchsucht, wie es in VectorPDF ist, mit seinen ungesicherten Änderungen und nur den eingeblendeten Ebenen; andere Dokumente werden durchsucht, ohne sie zu öffnen.
- **Extract Pages** nimmt Seiten und Bereiche, durch Kommas getrennt. Ein Bereich wie `5-` reicht bis zur letzten Seite, und `3-1` liefert die Seiten in umgekehrter Reihenfolge. Die Aktion liest die Datei so, wie sie zuletzt gesichert wurde, und ändert sie nicht. Das neue PDF wird nach dem Dokument und den Seiten benannt, etwa „Report (Pages 1-3, 5).pdf“.
- **Open Document** holt den Tab des Dokuments nach vorne, wenn es bereits geöffnet ist.

Ein passwortgeschütztes Dokument muss in VectorPDF geöffnet und sein Passwort eingegeben sein, bevor Search Document es durchsuchen kann. Extract Pages kann keine passwortgeschützten Dokumente verwenden.

> **Hinweis:** Was eine Aktion zurückgibt, geht an Kurzbefehle oder Siri und von dort an das, was dein Kurzbefehl als Nächstes tut. Ask About Document sendet nur das, was auch der Agent senden würde, wenn du in VectorPDF fragst. Siehe [Datenschutz](privacy.md).
