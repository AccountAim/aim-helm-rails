# The chat island and everything it imports load on demand, so only the chat page fetches them.
pin "vue",
    to: "https://cdn.jsdelivr.net/npm/vue@3.5.22/dist/vue.esm-browser.prod.js",
    preload: false
pin "marked",
    to: "https://cdn.jsdelivr.net/npm/marked@15.0.7/lib/marked.esm.js",
    preload: false
pin "dompurify",
    to: "https://cdn.jsdelivr.net/npm/dompurify@3.4.14/dist/purify.es.mjs",
    preload: false
pin "pdfjs-dist",
    to: "https://cdn.jsdelivr.net/npm/pdfjs-dist@6.2.108/build/pdf.mjs",
    preload: false
pin "xlsx",
    to: "https://cdn.sheetjs.com/xlsx-0.20.3/package/xlsx.mjs",
    preload: false
pin_all_from AimHelmRails::Engine.root.join("app/javascript/aim_helm_rails"),
             under: "aim_helm_rails", preload: false
pin_all_from AimHelmRails::Engine.root.join("app/javascript/controllers"), under: "controllers"
