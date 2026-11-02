<!-- keywords: IA, intelligence artificielle, moteur, sur l’appareil, modèle en ligne, clé API, Agent, AI, engine, on-device, Private Cloud Compute, online model, API key, OpenAI, Gemini, OpenRouter -->
<!-- source: dbbd02de21b5 -->

# Choisir comment l’Agent répond

La recherche des passages pertinents s’effectue toujours sur votre Mac. Vous pouvez choisir ce qui rédige la réponse dans VectorPDF > Settings > AI Synthesis Engine. Ce réglage nécessite macOS 27.

| Moteur | Fonctionnement | Ce qui quitte votre Mac |
| --- | --- | --- |
| On-Device | Apple Intelligence sur votre Mac | Rien |
| Private Cloud Compute | Les serveurs d’Apple, pour des réponses plus longues et plus détaillées | Votre question et les passages utilisés, qui sont envoyés au service Private Cloud Compute d’Apple |
| Online Model (your API key) | Un service de votre choix, facturé sur votre compte auprès de ce service | Votre question, les passages (ou tout le texte d’un document court) et la conversation précédente |

Sous macOS 26, l’Agent répond sur l’appareil.

Private Cloud Compute n’apparaît que dans les copies de VectorPDF signées pour ce service. La version que vous téléchargez sur GitHub répond sur l’appareil.

## Utiliser un modèle en ligne

1. Dans Settings, réglez AI Synthesis Engine sur Online Model.
2. Choisissez un service : OpenAI, Google Gemini ou OpenRouter.
3. Saisissez votre clé API. Un lien permet d’en obtenir une auprès de chaque service. La clé est stockée dans votre trousseau de session.
4. Choisissez un modèle.

Si le service ne peut pas répondre, VectorPDF répond sur l’appareil.

> **Attention :** La politique de confidentialité et les conditions du service s’appliquent à ce que vous envoyez. Avec les clés Gemini gratuites, Google peut utiliser ce que vous envoyez pour améliorer ses produits, et des personnes peuvent le consulter. N’envoyez donc pas de documents confidentiels. Consultez [Confidentialité](privacy.md).
