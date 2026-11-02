<!-- keywords: confidentialité, données, réseau, télémétrie, statistiques, sécurité, privacy, data, network, telemetry, analytics, iCloud, security -->
<!-- source: 4fdc452a0a96 -->

# Confidentialité

VectorPDF ne comporte ni compte, ni statistiques d’utilisation, ni télémétrie, ni rapports de plantage. Vos documents sont traités sur votre Mac, et rien de leur contenu n’est envoyé au développeur.

## Ce qui utilise le réseau

- **Recherche de mises à jour :** VectorPDF demande à GitHub la dernière version environ une fois par jour, ou lorsque vous choisissez Check for Updates. La requête ne contient aucune information sur vous ou vos documents. Vous pouvez désactiver cette fonction dans [Settings](settings.md).
- **L’Agent :** rien ne quitte votre Mac avec le moteur On-Device. [Private Cloud Compute et les modèles en ligne](agent-engines.md) envoient votre question et des passages du document, uniquement lorsque vous posez une question. La configuration d’un modèle en ligne utilise aussi votre clé pour lister ses modèles et envoyer un court test.
- **iCloud :** votre état de lecture est conservé dans votre propre compte iCloud : l’emplacement du fichier, la dernière page et le dernier zoom, ainsi que les noms, les extraits et les pages de vos ancres. Les documents, leur texte intégral et les vignettes des ancres ne sont pas téléversés.
- **Les liens sur lesquels vous cliquez** s’ouvrent dans votre navigateur.
- **Services Apple :** Translation, Look Up, la parole et l’OCR sont fournis par macOS et peuvent télécharger des fichiers de langue auprès d’Apple. Handoff partage le document et la page que vous lisez avec vos autres appareils.

## Ce qui est stocké sur votre Mac

VectorPDF stocke vos préférences, vos favoris, vos groupes d’onglets, vos positions de lecture, vos ancres et votre tampon. Il conserve aussi un index des documents que vous avez utilisés avec l’Agent, des vignettes d’ancres et des copies de travail temporaires des documents dont les modifications de pages ou les caviardages ne sont pas enregistrés, qu’il supprime lorsqu’il n’en a plus besoin.

Les clés API des modèles en ligne sont stockées dans votre trousseau de session.

Pour tous les détails, consultez la [politique de confidentialité sur GitHub](https://github.com/tomderham/vectorpdf/blob/main/PRIVACY.md).
