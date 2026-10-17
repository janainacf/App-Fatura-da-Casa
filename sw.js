/* ═══════════════════════════════════════════════════════════════════════════
   Fatura da Casa — service worker

   Rede primeiro, cache como rede de segurança. Nunca o contrário: os dados
   são financeiros e uma tela desatualizada é pior que uma tela que não abre.

   A versão anterior já era "rede primeiro", e ainda assim o app instalado
   serviu código velho por horas. O motivo: fetch(req) passa pelo cache HTTP
   do navegador, que pode devolver a cópia guardada sem tocar no servidor —
   "rede" para o service worker, cópia velha na prática.

   Correção: navegação usa cache:'reload', que obriga a ida ao servidor.
   ═══════════════════════════════════════════════════════════════════════════ */

const CACHE = 'fatura-da-casa-v2';
const CASCA = ['./', './index.html'];

self.addEventListener('install', e => {
  /* Só a casca entra aqui. Pré-carregar manifesto e ícones pelo nome faria a
     instalação inteira falhar se um deles mudasse de nome — e o resto é
     guardado sozinho, na primeira vez que a página os pede. */
  e.waitUntil(
    caches.open(CACHE)
      .then(c => c.addAll(CASCA))
      .catch(() => {})
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;

  /* Supabase e qualquer outro domínio passam direto: dados ao vivo não se
     guardam, e servir uma resposta velha de API seria pior que falhar. */
  const mesmaOrigem = new URL(req.url).origin === self.location.origin;
  if (!mesmaOrigem) return;

  const navegacao = req.mode === 'navigate' || req.destination === 'document';

  e.respondWith((async () => {
    try {
      /* cache:'reload' ignora o cache HTTP do navegador e vai ao servidor.
         Vale para a página; para ícones e fontes o cache normal serve. */
      const resp = await fetch(navegacao ? new Request(req, { cache: 'reload' }) : req);
      if (resp && resp.ok) {
        const copia = resp.clone();
        caches.open(CACHE).then(c => c.put(req, copia)).catch(() => {});
      }
      return resp;
    } catch (err) {
      /* Sem rede: devolve o que houver guardado. */
      const guardado = await caches.match(req);
      if (guardado) return guardado;
      if (navegacao) {
        const casca = await caches.match('./index.html');
        if (casca) return casca;
      }
      throw err;
    }
  })());
});
