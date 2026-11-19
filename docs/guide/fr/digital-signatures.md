<!-- keywords: vérifier des signatures numériques, horodatage, serveur d’horodatage, certifier, verrouiller les champs, signature numérique, signatures numériques, signer, signer avec un certificat, certificat, trousseau, signé, signataire, certifié, certification, valide, non valide, vérifier, valider, confiance, identité, falsifié, modifié, digital signature, digital signatures, sign, signing, sign with certificate, p12, pfx, keychain, signed, certificate, certified, valid, invalid, verify, validate, trust, identity, timestamp, PKCS, CAdES, PAdES, tampered, changed, check signature -->
<!-- source: 9299a883126e -->

# Vérifier des signatures numériques

Une signature numérique indique qui a signé un document et qu’il n’a pas changé depuis. Pour signer un PDF avec votre propre certificat, consultez [Signer avec un certificat](stamps.md#sign). Quand vous ouvrez un PDF signé, VectorPDF vérifie ses signatures et affiche ce qu’il a trouvé dans une barre au-dessus de la page :

- **La signature est valide :** le document n’a pas changé depuis sa signature, et le certificat du signataire a été émis par une autorité à laquelle votre Mac fait confiance.
- **L’identité du signataire n’est pas vérifiée sur ce Mac :** le document n’a pas changé, mais rien ne garantit qui l’a signé. Consultez [Pourquoi l’identité d’un signataire peut ne pas être vérifiée](#signer-identity).
- **Non valide :** le document a été modifié après sa signature, ou la signature ne lui correspond pas.

Cliquez sur **Signature Details** pour voir chaque signature dans l’onglet Document de la barre latérale. Pour masquer la barre, cliquez sur son bouton de fermeture.

> **Remarque :** Une [signature manuscrite](stamps.md) est une image de signature, pas une signature numérique.

## Ce que VectorPDF vérifie

Pour chaque signature, la liste de l’onglet Document indique :

- Si les parties du fichier qu’elle a signées sont exactement telles qu’elles ont été signées.
- Si le fichier a été enregistré de nouveau après la signature, et si ces modifications font partie de celles que la signature autorise. Remplir des champs de formulaire, ajouter des signatures et ajouter ou modifier des annotations sont généralement autorisés. Une signature de certification peut autoriser moins de modifications. Si des annotations ont été ajoutées après la signature, la liste l’indique : une annotation peut masquer ce qui a été signé.
- Qui l’a signée, selon le nom figurant dans son certificat, et qui a émis le certificat. Le nom que le logiciel de signature a écrit dans le document est aussi affiché lorsqu’il est différent.
- Quand elle a été signée. Une heure fournie par une autorité d’horodatage est garantie si l’horodatage porte sur cette signature et que votre Mac fait confiance à son autorité ; sinon, la liste indique pourquoi il n’est pas pris en compte. Une heure provenant de l’ordinateur du signataire n’est pas garantie.
- Le motif et le lieu indiqués par le signataire, le cas échéant.

Cliquez sur une signature pour y accéder sur la page. Pour voir ses certificats, cliquez sur **Show Certificate**, ou cliquez dessus avec le bouton droit et choisissez Show Certificate.

VectorPDF vérifie le fichier tel qu’il a été enregistré pour la dernière fois : les modifications non enregistrées ne sont donc pas prises en compte. Il vérifie de nouveau à chaque enregistrement.

## Pourquoi l’identité d’un signataire peut ne pas être vérifiée {#signer-identity}

N’importe qui peut créer un certificat contenant n’importe quel nom. Une signature ne prouve qui a signé que si le certificat a été émis par une autorité qui a vérifié son identité, et que votre Mac fait confiance à cette autorité. VectorPDF utilise les certificats auxquels votre Mac fait confiance, dans Trousseau d’accès.

De nombreux PDF signés utilisent des certificats d’autorités auxquelles Adobe Acrobat fait confiance, mais pas macOS : VectorPDF indique alors que leurs signataires ne sont pas vérifiés. Le document peut néanmoins n’avoir pas changé depuis sa signature. Pour faire confiance à une autorité, ajoutez son certificat à Trousseau d’accès et réglez-le sur « Toujours approuver », mais seulement si vous êtes sûr qu’il est authentique.

VectorPDF ne se connecte pas à Internet pour vérifier si un certificat a été révoqué. Ainsi, personne n’apprend que vous avez ouvert le document.

## Enregistrer un document signé

Lorsque vous enregistrez un document signé, VectorPDF ajoute vos modifications après la partie signée du fichier et laisse cette partie telle qu’elle était, afin que les signatures restent valides dans la mesure où les modifications sont autorisées. Supprimer du contenu par [caviardage](redact.md) réécrit tout le fichier : les signatures du document deviennent alors non valides.

## Types de signatures vérifiés

VectorPDF vérifie les signatures PDF habituelles : signatures PKCS #7 et CAdES (PAdES). Il ne vérifie pas encore les horodatages de document ni les anciennes signatures X.509 RSA. Elles sont indiquées comme **Not checked**.
