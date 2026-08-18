// =====================================================================
// criar-pessoa — a recepção cadastra alguém na academia dela
//
// Esta é a ÚNICA parte do sistema que roda com a chave de administração
// do Supabase, e existe por um motivo só: criar um login é a única coisa
// que o app, no celular, não pode fazer sozinho sem ganhar poder demais.
//
// A chave nunca aparece no código nem no repositório — o Supabase a injeta
// como variável de ambiente na hora que a função roda.
//
// A regra que organiza tudo aqui: a chave de administração é usada
// EXCLUSIVAMENTE para criar o login. Todo o resto (conferir quem está
// chamando, e criar o vínculo com a academia) é feito com o crachá de
// quem chamou, para que as regras do banco decidam — e não este código.
// =====================================================================

const URL_SUPA = Deno.env.get("SUPABASE_URL")!;
const SERVICO  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PUBLICA  = Deno.env.get("SUPABASE_ANON_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function resposta(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

/* Senha provisória para a recepção anotar num papel e entregar. Sem
   caracteres que se confundem à mão (O/0, I/l/1), e partida em dois
   blocos porque ninguém copia dez caracteres corridos sem errar. */
function geraSenha(): string {
  const letras = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const numeros = "23456789";
  const alfabeto = letras + numeros;
  const sorteio = new Uint32Array(8);
  crypto.getRandomValues(sorteio);
  const cru = Array.from(sorteio, (n) => alfabeto[n % alfabeto.length]).join("");
  return cru.slice(0, 4) + "-" + cru.slice(4);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return resposta({ erro: "metodo" }, 405);

  const cracha = req.headers.get("Authorization") ?? "";
  if (!cracha.startsWith("Bearer ")) return resposta({ erro: "sem_cracha" }, 401);

  let corpo: Record<string, unknown>;
  try {
    corpo = await req.json();
  } catch {
    return resposta({ erro: "corpo_invalido" }, 400);
  }

  const academia_id = String(corpo.academia_id ?? "").trim();
  const nome        = String(corpo.nome ?? "").trim();
  const email       = String(corpo.email ?? "").trim().toLowerCase();
  const telefone    = String(corpo.telefone ?? "").replace(/\D/g, "");
  const papeis      = Array.isArray(corpo.papeis) && corpo.papeis.length
                        ? (corpo.papeis as string[])
                        : ["aluno"];

  if (!academia_id) return resposta({ erro: "falta_academia" }, 400);
  if (nome.length < 2) return resposta({ erro: "falta_nome" }, 400);
  if (!email.includes("@")) return resposta({ erro: "falta_email" }, 400);

  const comMeuCracha = { apikey: PUBLICA, Authorization: cracha };

  // ---- 1. quem está chamando? Pergunta usando o crachá dele ------------
  const quem = await fetch(`${URL_SUPA}/auth/v1/user`, { headers: comMeuCracha });
  if (!quem.ok) return resposta({ erro: "cracha_invalido" }, 401);
  const usuario = await quem.json();

  // ---- 2. ele pode cadastrar nesta academia? --------------------------
  // A consulta vai com o crachá dele, então quem responde é a regra do
  // banco. Se ele não pertence à academia, volta vazio e acabou.
  const consulta = await fetch(
    `${URL_SUPA}/rest/v1/vinculos?select=papeis` +
      `&academia_id=eq.${encodeURIComponent(academia_id)}` +
      `&pessoa_id=eq.${encodeURIComponent(usuario.id)}&ativo=is.true`,
    { headers: comMeuCracha },
  );
  const vinculos = consulta.ok ? await consulta.json() : [];
  const meusPapeis: string[] = vinculos[0]?.papeis ?? [];

  // O dono do sistema precisa entrar aqui: academia recém-criada não tem
  // ninguém dentro, então sem isto ela nasceria sem ninguém capaz de
  // cadastrar o primeiro admin. A consulta vai com o crachá dele, e a
  // coluna `suporte` só se muda pelo painel — não dá para forjar.
  const souSuporte = await fetch(
    `${URL_SUPA}/rest/v1/pessoas?select=suporte&id=eq.${encodeURIComponent(usuario.id)}`,
    { headers: comMeuCracha },
  ).then((r) => r.ok ? r.json() : []).then((l) => l[0]?.suporte === true)
   .catch(() => false);

  const podeCadastrar = souSuporte || meusPapeis.some((p) =>
    ["recepcao", "gestor", "admin"].includes(p)
  );
  if (!podeCadastrar) return resposta({ erro: "sem_permissao" }, 403);

  // Dar papel que não seja "aluno" é do admin. Isto é conferido aqui E na
  // regra do banco, porque a criação do vínculo abaixo vai com o crachá
  // dele — a checagem daqui só serve para devolver um erro mais claro.
  const ehAdmin = souSuporte || meusPapeis.includes("admin");
  if (!ehAdmin && papeis.some((p) => p !== "aluno")) {
    return resposta({ erro: "so_admin_da_papel" }, 403);
  }

  // ---- 3. cria o login. Único ponto com a chave de administração -------
  const senha = geraSenha();
  const criacao = await fetch(`${URL_SUPA}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      apikey: SERVICO,
      Authorization: `Bearer ${SERVICO}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      email,
      password: senha,
      email_confirm: true,           // não há e-mail para confirmar
      // `trocar_senha` faz o app pedir uma senha nova no primeiro acesso.
      // Sem isto, a senha que a recepção anotou no papel seria definitiva —
      // e existiria para sempre uma pessoa a mais capaz de entrar na conta.
      user_metadata: { nome, telefone, trocar_senha: true },
    }),
  });

  if (!criacao.ok) {
    const det = await criacao.text();
    const jaExiste = det.includes("already been registered") ||
                     det.includes("already exists");
    return resposta(
      { erro: jaExiste ? "email_ja_usado" : "nao_criou_login", detalhe: det.slice(0, 200) },
      jaExiste ? 409 : 400,
    );
  }
  const novo = await criacao.json();

  // ---- 4. vincula à academia, com o crachá de quem chamou -------------
  // De propósito: assim é a regra do banco que decide, não este código.
  const vinculo = await fetch(`${URL_SUPA}/rest/v1/vinculos`, {
    method: "POST",
    headers: { ...comMeuCracha, "Content-Type": "application/json", Prefer: "return=representation" },
    body: JSON.stringify({ academia_id, pessoa_id: novo.id, papeis }),
  });

  if (!vinculo.ok) {
    // Não pode sobrar login solto: desfaz o que acabou de ser criado.
    await fetch(`${URL_SUPA}/auth/v1/admin/users/${novo.id}`, {
      method: "DELETE",
      headers: { apikey: SERVICO, Authorization: `Bearer ${SERVICO}` },
    });
    const det = await vinculo.text();
    return resposta({ erro: "nao_vinculou", detalhe: det.slice(0, 200) }, 400);
  }

  return resposta({
    ok: true,
    pessoa_id: novo.id,
    nome,
    email,
    papeis,
    senha_provisoria: senha,
  });
});
