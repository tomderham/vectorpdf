<!-- keywords: sign, signing, signature, signatures, handwritten signature, digital signature, sign with certificate, certificate, p12, pfx, keychain, timestamp, certify, lock fields, stamp, stamps, initials, which signature, PDF -->

# Sign a document

There are two ways to sign, and they do different things. Both are on the Sign button, the signature in the Markup toolbar (⇧⌘A).

| | Handwritten signature | Digital signature |
| --- | --- | --- |
| What it is | A picture of your signature or initials on the page | A signature made with your certificate and kept in the file |
| Shows who signed | No: anyone can paste a picture | Yes, when the certificate comes from an authority the reader trusts |
| Shows the document hasn't changed since | No | Yes |
| What you need | Nothing: draw, type or choose an image | A certificate for signing, from your organization or a certificate authority |
| Can be taken off afterwards | Yes, like a comment | Only by going back to a copy saved before signing |

A handwritten signature is enough where a picture will do, such as an informal form. Use a digital signature for contracts, approvals and anything someone may need to check later. A digital signature can show your handwritten signature in its box too.

## Add your handwritten signature

1. Show the Markup toolbar (⇧⌘A), click the Sign button, then choose Add Handwritten Signature. The first time, VectorPDF asks you to make your signature:
   - **Draw:** sign with your trackpad or mouse.
   - **Type:** enter your name or initials, and choose a font.
   - **Image:** choose a PNG or JPEG file. If you choose **Transparent background**, the page shows through the background of the image.
2. Click where you want it.

Then drag it to move it, or drag a corner to resize it. To remove it, select it and press Delete, or right-click it and choose Delete Signature.

VectorPDF keeps your signature on this Mac for next time. To change or delete it, choose VectorPDF > Settings, click General, then use the buttons next to Handwritten Signature.

## Sign with a certificate {#sign}

To sign, you need a certificate for signing with its private key. Your organization or a certificate authority can give you one, usually as a .p12 or .pfx file with a password. Certificates in your keychain can be used directly.

1. Click the Sign button in the Markup toolbar and choose Sign with Certificate, or choose Edit > Sign with Certificate. Then drag out a box on the page where the signature should go, or click for one of the usual size. Press Esc to stop. If the document has an empty signature field, you can click the field instead and choose Sign with Certificate.
2. Choose your certificate. A preview shows how the signature will look. To use a file, click **Choose Certificate File**, then type its password. The file is read for this signature only and isn't added to your keychain.
3. If you like, type a reason (such as "I approve this document") and where you're signing. If you've made a [handwritten signature](#add-your-handwritten-signature), you can show it in the field. Otherwise your name is shown.
4. If you like, choose under After Signing:
   - **Certify**, if no one has signed the document yet: say which changes keep it valid from now on: form filling, signing and comments; form filling and signing; or none. A certified document shows as certified to everyone who checks it, and later changes it doesn't allow make your signature invalid.
   - **Lock form fields**, for a form: all its fields, or those you choose, become read-only, so they keep the values you signed.
5. Click **Sign**.

Signing saves the document, so if it has unsaved changes, VectorPDF asks to save them first. They become part of what you sign. macOS may ask you to allow VectorPDF to use your certificate's key.

Unless you lock them or certify the document for less, the signature leaves the document's other form fields as they were, so others can still fill them in, sign too, or add comments without making your signature invalid. Each later signature is added after the earlier ones in the same way.

The signature is a PKCS #7 signature with SHA-256, carrying your certificate and those of the authorities that issued it. It records the time on your Mac.

To have a timestamp server vouch for when you signed, turn on **Add a timestamp** and give its address (your organization may run one; free ones include DigiCert's, `http://timestamp.digicert.com`). A timestamp lets your signature be checked as it was when you signed, even after your certificate expires. The server is sent only a fingerprint of the signature, nothing of the document. If it can't be reached, nothing is signed and the document is left as it was.

To check the signatures in a document, see [Check digital signatures](digital-signatures.md).

## Sign a form

If a form has a signature field, click **Sign** in the field, then choose Add Handwritten Signature or Sign with Certificate. See [Fill in forms](forms.md).
