/* Service worker do Meu Treino.
   Guarda o app no aparelho para abrir sem internet, mas continua buscando
   a versão nova quando há sinal — assim uma atualização não fica presa.
   Ao publicar uma alteração, troque o número da versão abaixo. */

const VERSAO = "meu-treino-v12";
/* O Meu TAF mora no mesmo endereço (mateusvazzoller.github.io), em outra
   pasta, e o navegador guarda o cache POR ENDEREÇO — os dois service
   workers enxergam a mesma prateleira. Sem este prefixo, a faxina do
   `activate` abaixo apagaria o cache do outro app, e ele pararia de
   funcionar sem internet até ser aberto de novo com sinal. */
const PREFIXO = "meu-treino-";
const ARQUIVOS = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon-192-maskable.png",
  "./icons/icon-maskable-512.png",
  "./icons/icon-mono-512.png",
  "./icons/apple-touch-icon.png",
  "./sons/despertador.mp3",
  "./sons/apito.mp3",
  "./sons/gongo.mp3"
];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches.open(VERSAO)
      .then((c) => c.addAll(ARQUIVOS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((ks) => Promise.all(
        ks.filter((k) => k.startsWith(PREFIXO) && k !== VERSAO).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

/* A página pergunta qual versão está no comando, para mostrar em Ajustes. */
self.addEventListener("message", (e) => {
  const d = e.data || {};
  if (d.q === "versao" && e.ports && e.ports[0]) {
    e.ports[0].postMessage({ versao: VERSAO });
  }
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;

  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;   // vídeos e links externos passam direto

  /* A página em si: rede primeiro, para pegar atualização;
     sem sinal, cai no que está guardado. */
  if (req.mode === "navigate") {
    e.respondWith(
      fetch(req)
        .then((res) => {
          const copia = res.clone();
          caches.open(VERSAO).then((c) => c.put("./index.html", copia));
          return res;
        })
        .catch(() => caches.match("./index.html").then((r) => r || caches.match("./")))
    );
    return;
  }

  /* Ícones e manifest: o que está guardado serve, e atualiza por trás. */
  e.respondWith(
    caches.match(req).then((cache) => {
      const rede = fetch(req)
        .then((res) => {
          if (res && res.status === 200) {
            const copia = res.clone();
            caches.open(VERSAO).then((c) => c.put(req, copia));
          }
          return res;
        })
        .catch(() => cache);
      return cache || rede;
    })
  );
});
