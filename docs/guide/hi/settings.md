<!-- keywords: सेटिंग्ज़, प्राथमिकताएँ, विकल्प, अपडेट, अपडेट जाँचें, ब्राउज़र, लेखक, ऐनोटेशन लेखक, स्टोरेज, डिस्क स्थान, साफ़ करें, डेटा हटाएँ, अनइंस्टॉल, settings, preferences, options, updates, update, check for updates, browser, author, annotation author, storage, disk space, clear, remove data, delete data, uninstall -->
<!-- source: 95e6c661738e -->

# सेटिंग्ज़

VectorPDF > Settings चुनें, या ⌘, दबाएँ।

| सेटिंग | यह क्या करती है |
| --- | --- |
| Annotation Author | वह नाम जो आपके ऐनोटेशन और जवाबों के साथ सहेजा जाता है। खाली होने पर VectorPDF आपके Mac उपयोगकर्ता नाम का उपयोग करता है। |
| Use Agent | macOS 26 या उसके बाद के संस्करण पर साइडबार में [Ask About This Document](agent.md) टैब दिखाती है। |
| AI Synthesis Engine | macOS 27 पर चुनती है कि [Agent के जवाब कौन लिखेगा](agent-engines.md)। |
| PDF Color | सेट करती है कि [पेज कैसे दिखें](pdf-colors.md): Follow System, Light, Dark या Sepia। |
| Open Links In | वेब लिंक के लिए ब्राउज़र चुनती है। |
| Ignored Search Patterns | वह टेक्स्ट दिखाती है जिसे [Smart Search अनदेखा करता है](search.md#ignore-clutter-in-the-text)। |
| Digital Stamp | आपका [स्टैम्प](stamps.md) बनाती है, बदलती है या हटाती है। |
| Sync reading positions with iCloud | आपके [पेज, ज़ूम, ऐंकर](reading-positions.md) और [हाल की खोजों](search.md) को आपके दूसरे Mac पर भी रखता है। |
| Storage | दिखाता है कि VectorPDF का डेटा कितनी जगह लेता है, और [उसे साफ़ करता है](#free-up-space-or-remove-data)। |
| Automatically check for updates | लगभग दिन में एक बार GitHub पर नया संस्करण जाँचती है। किसी भी समय जाँचने के लिए Check Now पर क्लिक करें। |

## जगह खाली करें या डेटा हटाएँ {#free-up-space-or-remove-data}

Storage के अंतर्गत, सेटिंग्स दिखाती हैं कि हर तरह का डेटा कितनी जगह लेता है:

- **Agent इंडेक्स:** किसी दस्तावेज़ के बारे में सवालों के जवाब देने के लिए Agent जो बनाता है। उन्हें हटाने के लिए Clear पर क्लिक करें; अगली बार जब आप उस दस्तावेज़ के साथ Agent का उपयोग करेंगे, तो वह फिर से इंडेक्स होगा। VectorPDF इन्हें 500 MB से कम रखता है, सबसे पहले सबसे कम हाल में उपयोग किए गए हटाकर, और दस्तावेज़ न रहने पर उसका इंडेक्स हटा देता है।
- **पढ़ने का इतिहास:** हर दस्तावेज़ का आखिरी पेज, ज़ूम, ऐंकर और हाल की खोजें। इन्हें इस Mac पर और iCloud में भुलाने के लिए Clear पर क्लिक करें।
- **अस्थायी फ़ाइलें:** संपादित, सहेजते, प्रिंट या एक्सपोर्ट करते समय बनी कॉपियाँ, और डाउनलोड किए गए अपडेट। VectorPDF अगली बार खुलने पर बची हुई फ़ाइलें हटा देता है।

VectorPDF ने जो कुछ भी सहेजा है, उसे हटाने के लिए Remove All VectorPDF Data पर क्लिक करें। इससे आपकी सेटिंग्स, पसंदीदा, टैब समूह, स्टैम्प और API कुंजियाँ भी हट जाती हैं, फिर VectorPDF बंद हो जाता है। आपके दस्तावेज़ों को छुआ नहीं जाता। पहले बिना सहेजे बदलावों वाले दस्तावेज़ सहेजें या बंद करें।

## VectorPDF अपडेट करें

VectorPDF > Check for Updates चुनें। अगर कोई नया संस्करण है, तो Download पर क्लिक करें। डाउनलोड होने के बाद **Quit and Open Installer** पर क्लिक करें, फिर VectorPDF को अपने ऐप्लिकेशन फ़ोल्डर में ड्रैग करें।
