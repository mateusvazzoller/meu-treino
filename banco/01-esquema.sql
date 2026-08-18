-- =====================================================================
-- Meu Treino — estrutura do banco
--
-- Rode este arquivo UMA VEZ, inteiro, no SQL Editor do Supabase.
-- Ele cria as nove tabelas, as regras de permissão e as travas.
--
-- A ideia que atravessa o arquivo inteiro: as regras moram AQUI, não na
-- tela. O app pode pedir o que quiser — o banco só devolve o que a
-- pessoa tem direito de ver, e só aceita o que ela tem direito de mudar.
-- Uma checagem feita só no app se contorna pelo menu de desenvolvedor do
-- navegador; esta aqui, não.
-- =====================================================================

create schema if not exists app;
comment on schema app is
  'Funções internas usadas pelas regras de permissão. Não fica exposta na API.';

-- =====================================================================
-- 1. TIPOS
-- =====================================================================

create type papel as enum ('aluno', 'professor', 'recepcao', 'gestor', 'admin');

create type forma_pagamento as enum
  ('dinheiro', 'pix', 'cartao', 'transferencia', 'outro');

create type tipo_lancamento as enum ('pagamento', 'estorno');

-- =====================================================================
-- 2. TABELAS
-- =====================================================================

-- ---- academias: cada cliente do sistema --------------------------------
create table academias (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null check (length(trim(nome)) > 0),
  cnpj        text,
  ativa       boolean not null default true,
  criada_em   timestamptz not null default now()
);

-- ---- pessoas: um ser humano, um login ----------------------------------
-- A pessoa existe UMA VEZ no sistema inteiro, não uma vez por academia.
-- Quem dá aula em duas academias é a mesma pessoa, com dois vínculos.
create table pessoas (
  id          uuid primary key references auth.users(id) on delete cascade,
  nome        text not null check (length(trim(nome)) > 0),
  email       text not null,
  telefone    text,                  -- só dígitos; ver app.normaliza_telefone
  nascimento  date,
  cpf         text,                  -- opcional: só faz falta quando houver cobrança
  endereco    jsonb,                 -- {cep, logradouro, numero, complemento, bairro, cidade, uf}
  suporte     boolean not null default false,
  criado_em   timestamptz not null default now()
);
comment on column pessoas.suporte is
  'Dono do sistema: cria academias e nomeia o primeiro admin de cada uma. '
  'Só se muda à mão pelo painel — existe uma trava impedindo pela API.';

create unique index pessoas_telefone_unico on pessoas (telefone)
  where telefone is not null;
create unique index pessoas_cpf_unico on pessoas (cpf)
  where cpf is not null;

-- ---- vinculos: a pessoa DENTRO de uma academia -------------------------
-- É a peça central. Separa uma academia da outra e guarda os papéis.
-- `papeis` é lista porque acumular é o normal: a recepcionista que também
-- dá aula, o professor que cobre o caixa. O admin já pode tudo sozinho.
create table vinculos (
  id           uuid primary key default gen_random_uuid(),
  academia_id  uuid not null references academias(id) on delete cascade,
  pessoa_id    uuid not null references pessoas(id) on delete cascade,
  papeis       papel[] not null default array['aluno']::papel[],
  ativo        boolean not null default true,
  criado_em    timestamptz not null default now(),
  unique (academia_id, pessoa_id),
  check (array_length(papeis, 1) >= 1)
);
-- As tabelas de baixo declaram `unique (id, academia_id)` só para permitir
-- a chave estrangeira composta: assim "pertencer à mesma academia" fica
-- amarrado na estrutura, e não apenas na regra de permissão.

-- ---- fichas: o treino prescrito ----------------------------------------
create table fichas (
  id            uuid primary key default gen_random_uuid(),
  academia_id   uuid not null references academias(id) on delete cascade,
  professor_id  uuid not null references pessoas(id),
  nome          text not null check (length(trim(nome)) > 0),
  semanas       int not null default 4 check (semanas between 1 and 52),
  conteudo      jsonb not null default '[]'::jsonb,
  criada_em     timestamptz not null default now(),
  atualizada_em timestamptz not null default now(),
  unique (id, academia_id)
);

-- ---- atribuicoes: qual aluno faz qual ficha ----------------------------
create table atribuicoes (
  id            uuid primary key default gen_random_uuid(),
  academia_id   uuid not null references academias(id) on delete cascade,
  ficha_id      uuid not null,
  aluno_id      uuid not null references pessoas(id) on delete cascade,
  professor_id  uuid not null references pessoas(id),
  inicio        date not null default current_date,
  fim           date,
  ativa         boolean not null default true,
  criada_em     timestamptz not null default now(),
  unique (id, academia_id),
  -- a ficha atribuída TEM que ser da mesma academia. Isto é estrutura,
  -- não confiança: nem um erro no código consegue furar.
  foreign key (ficha_id, academia_id) references fichas (id, academia_id) on delete cascade,
  check (fim is null or fim >= inicio)
);

-- ---- registros: o que o aluno marcou -----------------------------------
-- Mesmo formato de chave que o app já usa no celular hoje
-- ("w1|a1|b2|0"), para migrar sem inventar modelo novo.
create table registros (
  id             uuid primary key default gen_random_uuid(),
  academia_id    uuid not null references academias(id) on delete cascade,
  atribuicao_id  uuid not null,
  aluno_id       uuid not null references pessoas(id) on delete cascade,
  chave          text not null check (length(chave) > 0),
  valor          jsonb not null,
  atualizado_em  timestamptz not null default now(),
  unique (atribuicao_id, chave),
  foreign key (atribuicao_id, academia_id) references atribuicoes (id, academia_id) on delete cascade
);

-- ---- planos: o que a academia vende ------------------------------------
create table planos (
  id           uuid primary key default gen_random_uuid(),
  academia_id  uuid not null references academias(id) on delete cascade,
  nome         text not null check (length(trim(nome)) > 0),
  valor        numeric(10,2) not null check (valor >= 0),
  meses        int not null default 1 check (meses > 0),
  ativo        boolean not null default true,
  criado_em    timestamptz not null default now(),
  unique (id, academia_id)
);

-- ---- matriculas: o aluno num plano -------------------------------------
create table matriculas (
  id              uuid primary key default gen_random_uuid(),
  academia_id     uuid not null references academias(id) on delete cascade,
  aluno_id        uuid not null references pessoas(id) on delete cascade,
  plano_id        uuid not null,
  inicio          date not null default current_date,
  fim             date,
  dia_vencimento  int not null default 10 check (dia_vencimento between 1 and 28),
  ativa           boolean not null default true,
  criada_em       timestamptz not null default now(),
  unique (id, academia_id),
  foreign key (plano_id, academia_id) references planos (id, academia_id),
  check (fim is null or fim >= inicio)
);

-- ---- lancamentos: o pagamento anotado ----------------------------------
-- SÓ CRESCE. Não se edita e não se apaga — errou, lança um estorno.
-- É o que permite responder "para onde foi aquele R$ 120" seis meses
-- depois. As travas estão na seção 5.
create table lancamentos (
  id              uuid primary key default gen_random_uuid(),
  academia_id     uuid not null references academias(id) on delete cascade,
  matricula_id    uuid,
  aluno_id        uuid not null references pessoas(id),
  tipo            tipo_lancamento not null default 'pagamento',
  valor           numeric(10,2) not null check (valor > 0),
  forma           forma_pagamento not null,
  competencia     date not null,     -- sempre dia 1 do mês de referência
  pago_em         date not null default current_date,
  estorna_id      uuid references lancamentos(id),
  observacao      text,
  registrado_por  uuid not null references pessoas(id),
  criado_em       timestamptz not null default now(),
  foreign key (matricula_id, academia_id) references matriculas (id, academia_id),
  check (tipo = 'pagamento' and estorna_id is null
      or tipo = 'estorno'   and estorna_id is not null)
);

create index lancamentos_busca on lancamentos (academia_id, competencia, aluno_id);
create index matriculas_ativas on matriculas (academia_id, ativa) where ativa;
create index vinculos_pessoa on vinculos (pessoa_id) where ativo;
create index atribuicoes_aluno on atribuicoes (aluno_id, ativa) where ativa;

-- =====================================================================
-- 3. FUNÇÕES QUE AS REGRAS USAM
--
-- Todas levam `set search_path` fixo: sem isso, alguém que consiga criar
-- uma tabela em outro schema pode fazer a função ler a tabela errada. O
-- verificador do Supabase (get_advisors) acusa quem esquecer.
--
-- Todas são SECURITY DEFINER de propósito: elas precisam ler `vinculos`
-- sem passar pelas regras de `vinculos`, senão a regra chamaria a função
-- que consultaria a tabela que dispara a regra — e o banco entra em
-- recursão infinita.
-- =====================================================================

create or replace function app.e_suporte()
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select p.suporte from pessoas p where p.id = auth.uid()), false)
$$;

-- A pessoa tem ALGUM dos papéis pedidos nesta academia?
create or replace function app.tem_papel(p_academia uuid, p_papeis papel[])
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from vinculos v
     where v.academia_id = p_academia
       and v.pessoa_id   = auth.uid()
       and v.ativo
       and v.papeis && p_papeis
  ) or app.e_suporte()
$$;

-- A pessoa participa desta academia, de qualquer jeito?
create or replace function app.e_membro(p_academia uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from vinculos v
     where v.academia_id = p_academia and v.pessoa_id = auth.uid() and v.ativo
  ) or app.e_suporte()
$$;

-- Em quais academias eu mando o suficiente para enxergar o cadastro
-- dos outros? Usada na regra de `pessoas`.
create or replace function app.academias_que_administro()
returns setof uuid
language sql stable security definer set search_path = public, pg_temp as $$
  select v.academia_id from vinculos v
   where v.pessoa_id = auth.uid() and v.ativo
     and v.papeis && array['professor','recepcao','gestor','admin']::papel[]
$$;

-- Fulano participa desta academia? Precisa ser SECURITY DEFINER: usada
-- dentro das regras para impedir que alguém matricule, atribua ficha ou
-- lance pagamento para uma pessoa que não é da academia dele.
create or replace function app.e_membro_de(p_academia uuid, p_pessoa uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from vinculos v
     where v.academia_id = p_academia and v.pessoa_id = p_pessoa and v.ativo
  )
$$;

create or replace function app.normaliza_telefone(t text)
returns text
language sql immutable set search_path = public, pg_temp as $$
  select nullif(regexp_replace(coalesce(t, ''), '\D', '', 'g'), '')
$$;

-- =====================================================================
-- 4. ENTRAR PELO TELEFONE
--
-- O login continua sendo e-mail + senha; o telefone é só um apelido.
-- Quem digita o número, o servidor descobre a qual conta pertence e o
-- app entra com o e-mail correspondente. Assim não há SMS nem custo.
--
-- ATENÇÃO — o preço disso: quem souber o telefone de alguém descobre o
-- e-mail dela. Exigir 10 dígitos evita varredura preguiçosa, mas não
-- resolve quem já tem uma lista de números. Se isso incomodar, apague
-- esta função e o login passa a ser só por e-mail.
-- =====================================================================

create or replace function public.email_por_telefone(p_telefone text)
returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select p.email from pessoas p
   where p.telefone = app.normaliza_telefone(p_telefone)
     and length(app.normaliza_telefone(p_telefone)) >= 10
   limit 1
$$;
grant execute on function public.email_por_telefone(text) to anon, authenticated;

-- =====================================================================
-- 5. AS TRAVAS
-- Regras que nenhuma tela, nenhum app e nenhum erro de código furam.
-- =====================================================================

-- ---- 5.1 pessoa nova ganha ficha de cadastro sozinha -------------------
-- O nome vem do que a pessoa digitou no cadastro. O app manda em `nome`,
-- mas fluxos de login social devolvem `name` ou `full_name` — aceitar os
-- três evita cadastro nascer sem nome por causa do rótulo do campo. O
-- reserva (pedaço antes do @) só entra quando não veio nome nenhum, que é
-- o caso de quem foi criado à mão pelo painel do Supabase, que não tem
-- campo de nome.
create or replace function app.ao_criar_usuario()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  n text;
begin
  n := coalesce(
         nullif(trim(new.raw_user_meta_data->>'nome'), ''),
         nullif(trim(new.raw_user_meta_data->>'name'), ''),
         nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
         split_part(new.email, '@', 1)
       );
  insert into public.pessoas (id, nome, email, telefone)
  values (new.id, n, new.email,
          app.normaliza_telefone(new.raw_user_meta_data->>'telefone'));
  return new;
end $$;

create trigger criar_pessoa_no_cadastro
  after insert on auth.users
  for each row execute function app.ao_criar_usuario();

-- ---- 5.2 ninguém se torna dono do sistema pela API ---------------------
create or replace function app.trava_suporte()
returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if new.suporte is distinct from old.suporte and auth.uid() is not null then
    raise exception 'A marca de suporte só muda pelo painel do Supabase.';
  end if;
  return new;
end $$;

create trigger trava_suporte
  before update on pessoas
  for each row execute function app.trava_suporte();

-- ---- 5.3 ninguém muda o próprio papel ----------------------------------
-- Vale inclusive para o admin. Sem isto, "sou aluno" vira "sou admin"
-- com uma chamada à API.
create or replace function app.trava_autopromocao()
returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if auth.uid() is not null and old.pessoa_id = auth.uid()
     and new.papeis is distinct from old.papeis then
    raise exception 'Ninguém muda o próprio papel. Peça a outro admin.';
  end if;
  return new;
end $$;

create trigger trava_autopromocao
  before update on vinculos
  for each row execute function app.trava_autopromocao();

-- ---- 5.4 uma academia nunca fica sem admin -----------------------------
-- Se o último admin se rebaixar por engano, a academia trava e só se
-- resolve à mão no painel. Melhor recusar a alteração.
create or replace function app.trava_ultimo_admin()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  alvo uuid := coalesce(old.academia_id, new.academia_id);
begin
  -- academia sendo apagada inteira: os vínculos vão junto, tudo bem
  if not exists (select 1 from academias a where a.id = alvo) then
    return null;
  end if;
  if not exists (
    select 1 from vinculos v
     where v.academia_id = alvo and v.ativo
       and v.papeis && array['admin']::papel[]
  ) then
    raise exception 'A academia ficaria sem nenhum admin. Nomeie outro antes.';
  end if;
  return null;
end $$;

create trigger trava_ultimo_admin
  after update or delete on vinculos
  for each row execute function app.trava_ultimo_admin();

-- ---- 5.5 papéis sem repetição e sempre na mesma ordem ------------------
create or replace function app.arruma_papeis()
returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  new.papeis := (
    select array_agg(distinct p order by p) from unnest(new.papeis) as p
  );
  if new.papeis is null or array_length(new.papeis, 1) < 1 then
    raise exception 'O vínculo precisa de pelo menos um papel.';
  end if;
  return new;
end $$;

create trigger arruma_papeis
  before insert or update on vinculos
  for each row execute function app.arruma_papeis();

-- ---- 5.6 lançamento não se edita nem se apaga --------------------------
create or replace function app.trava_lancamento()
returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  raise exception 'Lançamento não se altera nem se apaga. Registre um estorno.';
end $$;

create trigger trava_lancamento
  before update or delete on lancamentos
  for each row execute function app.trava_lancamento();

-- ---- 5.7 competência sempre no dia 1, e quem anotou é quem está logado --
create or replace function app.arruma_lancamento()
returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  new.competencia := date_trunc('month', new.competencia)::date;
  if auth.uid() is not null then
    new.registrado_por := auth.uid();
  end if;
  return new;
end $$;

create trigger arruma_lancamento
  before insert on lancamentos
  for each row execute function app.arruma_lancamento();

-- ---- 5.8 carimbo de atualização ----------------------------------------
-- Duas funções quase iguais em vez de uma esperta: os nomes das colunas
-- diferem por uma letra e resolver isso com jsonb dentro do gatilho é o
-- tipo de truque que ninguém entende quando quebrar.
create or replace function app.carimba_ficha()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin new.atualizada_em := now(); return new; end $$;

create or replace function app.carimba_registro()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin new.atualizado_em := now(); return new; end $$;

create trigger carimba before update on fichas
  for each row execute function app.carimba_ficha();
create trigger carimba before update on registros
  for each row execute function app.carimba_registro();

-- =====================================================================
-- 6. AS REGRAS DE PERMISSÃO
--
-- A partir daqui, tudo é proibido por padrão: o que não tiver regra
-- explícita, ninguém vê e ninguém muda.
-- =====================================================================

alter table academias   enable row level security;
alter table pessoas     enable row level security;
alter table vinculos    enable row level security;
alter table fichas      enable row level security;
alter table atribuicoes enable row level security;
alter table registros   enable row level security;
alter table planos      enable row level security;
alter table matriculas  enable row level security;
alter table lancamentos enable row level security;

-- ---- academias ---------------------------------------------------------
create policy "membro vê a academia" on academias
  for select using (app.e_membro(id));
create policy "só o suporte cria academia" on academias
  for insert with check (app.e_suporte());
create policy "admin edita a própria academia" on academias
  for update using (app.tem_papel(id, array['admin']::papel[]));
create policy "só o suporte apaga academia" on academias
  for delete using (app.e_suporte());

-- ---- pessoas -----------------------------------------------------------
-- O aluno vê a si mesmo. Professor, recepção, gestor e admin veem o
-- cadastro de quem compartilha academia com eles. Um aluno NÃO vê outro.
create policy "vejo a mim e a quem eu administro" on pessoas
  for select using (
    id = auth.uid()
    or app.e_suporte()
    or exists (
      select 1 from vinculos v
       where v.pessoa_id = pessoas.id and v.ativo
         and v.academia_id in (select app.academias_que_administro())
    )
  );
create policy "edito o meu cadastro" on pessoas
  for update using (
    id = auth.uid()
    or app.e_suporte()
    or exists (
      select 1 from vinculos v
       where v.pessoa_id = pessoas.id and v.ativo
         and app.tem_papel(v.academia_id, array['recepcao','gestor','admin']::papel[])
    )
  );

-- ---- vinculos ----------------------------------------------------------
create policy "vejo meus vínculos e os de quem administro" on vinculos
  for select using (
    pessoa_id = auth.uid()
    or app.tem_papel(academia_id, array['professor','recepcao','gestor','admin']::papel[])
  );
create policy "admin cria vínculo" on vinculos
  for insert with check (app.tem_papel(academia_id, array['admin']::papel[]));
create policy "admin muda vínculo" on vinculos
  for update using (app.tem_papel(academia_id, array['admin']::papel[]));
create policy "admin remove vínculo" on vinculos
  for delete using (app.tem_papel(academia_id, array['admin']::papel[]));

-- ---- fichas ------------------------------------------------------------
create policy "vejo as fichas que me interessam" on fichas
  for select using (
    app.tem_papel(academia_id, array['professor','recepcao','gestor','admin']::papel[])
    or exists (
      select 1 from atribuicoes a
       where a.ficha_id = fichas.id and a.aluno_id = auth.uid() and a.ativa
    )
  );
-- A ficha nasce no nome de quem a criou. Só o admin monta em nome de outro.
create policy "professor cria ficha" on fichas
  for insert with check (
    app.tem_papel(academia_id, array['professor','admin']::papel[])
    and (professor_id = auth.uid()
         or app.tem_papel(academia_id, array['admin']::papel[]))
  );
create policy "professor edita a própria ficha" on fichas
  for update using (
    professor_id = auth.uid() or app.tem_papel(academia_id, array['admin']::papel[])
  );
create policy "professor apaga a própria ficha" on fichas
  for delete using (
    professor_id = auth.uid() or app.tem_papel(academia_id, array['admin']::papel[])
  );

-- ---- atribuicoes -------------------------------------------------------
create policy "vejo as minhas atribuições" on atribuicoes
  for select using (
    aluno_id = auth.uid()
    or app.tem_papel(academia_id, array['professor','recepcao','gestor','admin']::papel[])
  );
-- Duas checagens além do papel: a ficha sai no nome de quem atribuiu, e o
-- aluno tem que ser da MESMA academia — sem isso, dava para entregar treino
-- a um aluno de outra academia só sabendo o id dele.
create policy "professor atribui ficha" on atribuicoes
  for insert with check (
    app.tem_papel(academia_id, array['professor','admin']::papel[])
    and app.e_membro_de(academia_id, aluno_id)
    and (professor_id = auth.uid()
         or app.tem_papel(academia_id, array['admin']::papel[]))
  );
create policy "professor mexe na própria atribuição" on atribuicoes
  for update using (
    professor_id = auth.uid() or app.tem_papel(academia_id, array['admin']::papel[])
  );
create policy "professor remove a própria atribuição" on atribuicoes
  for delete using (
    professor_id = auth.uid() or app.tem_papel(academia_id, array['admin']::papel[])
  );

-- ---- registros ---------------------------------------------------------
-- Quem registra é o aluno. O professor e a gestão leem, mas não escrevem
-- no lugar dele.
create policy "vejo os registros que me dizem respeito" on registros
  for select using (
    aluno_id = auth.uid()
    or app.tem_papel(academia_id, array['professor','gestor','admin']::papel[])
  );
create policy "o aluno registra o que fez" on registros
  for insert with check (aluno_id = auth.uid() and app.e_membro(academia_id));
create policy "o aluno corrige o que registrou" on registros
  for update using (aluno_id = auth.uid());
create policy "o aluno apaga o que registrou" on registros
  for delete using (
    aluno_id = auth.uid() or app.tem_papel(academia_id, array['admin']::papel[])
  );

-- ---- planos ------------------------------------------------------------
create policy "membro vê os planos" on planos
  for select using (app.e_membro(academia_id));
create policy "gestor cria plano" on planos
  for insert with check (app.tem_papel(academia_id, array['gestor','admin']::papel[]));
create policy "gestor edita plano" on planos
  for update using (app.tem_papel(academia_id, array['gestor','admin']::papel[]));
create policy "gestor apaga plano" on planos
  for delete using (app.tem_papel(academia_id, array['gestor','admin']::papel[]));

-- ---- matriculas --------------------------------------------------------
create policy "vejo a minha matrícula" on matriculas
  for select using (
    aluno_id = auth.uid()
    or app.tem_papel(academia_id, array['recepcao','gestor','admin']::papel[])
  );
create policy "recepção matricula" on matriculas
  for insert with check (
    app.tem_papel(academia_id, array['recepcao','gestor','admin']::papel[])
    and app.e_membro_de(academia_id, aluno_id)
  );
create policy "recepção mexe na matrícula" on matriculas
  for update using (
    app.tem_papel(academia_id, array['recepcao','gestor','admin']::papel[])
  );

-- ---- lancamentos -------------------------------------------------------
-- Note que não existe regra de UPDATE nem de DELETE. Sem regra, o banco
-- recusa — e a trava 5.6 recusa de novo, para o caso de alguém criar uma
-- regra sem querer no futuro.
create policy "vejo os meus pagamentos" on lancamentos
  for select using (
    aluno_id = auth.uid()
    or app.tem_papel(academia_id, array['recepcao','gestor','admin']::papel[])
  );
create policy "recepção anota pagamento" on lancamentos
  for insert with check (
    app.tem_papel(academia_id, array['recepcao','gestor','admin']::papel[])
    and app.e_membro_de(academia_id, aluno_id)
  );

-- =====================================================================
-- 7. QUEM ESTÁ DEVENDO
--
-- Sem cobrança automática, a inadimplência é só uma consulta: matrícula
-- ativa que não tem lançamento no mês. A visão herda as regras das
-- tabelas de baixo — quem não pode ver a matrícula não vê a linha.
-- =====================================================================

create or replace view inadimplencia
with (security_invoker = true) as
select
  m.academia_id,
  m.id            as matricula_id,
  m.aluno_id,
  p.nome          as aluno,
  pl.nome         as plano,
  pl.valor,
  c.competencia,
  make_date(
    extract(year from c.competencia)::int,
    extract(month from c.competencia)::int,
    m.dia_vencimento
  ) as vencimento
from matriculas m
join pessoas p  on p.id = m.aluno_id
join planos pl  on pl.id = m.plano_id
cross join lateral (
  -- os dois extremos vão para `date` na mão: misturar date com timestamptz
  -- dentro de greatest/coalesce dá erro de tipo no Postgres
  select generate_series(
    greatest(
      date_trunc('month', m.inicio)::date,
      date_trunc('month', current_date - interval '11 months')::date
    ),
    date_trunc('month', coalesce(m.fim, current_date))::date,
    interval '1 month'
  )::date as competencia
) c
where m.ativa
  and not exists (
    select 1 from lancamentos l
     where l.matricula_id = m.id
       and l.competencia  = c.competencia
       and l.tipo = 'pagamento'
       and not exists (select 1 from lancamentos e where e.estorna_id = l.id)
  );

comment on view inadimplencia is
  'Meses em aberto por matrícula ativa, últimos 12 meses. Pagamento '
  'estornado volta a contar como em aberto.';

-- =====================================================================
-- PRONTO.
--
-- Falta uma coisa que NÃO dá para fazer por aqui: nomear o primeiro dono
-- do sistema. Depois de criar a sua conta pelo app, rode no SQL Editor:
--
--   update pessoas set suporte = true where email = 'seu@email.com';
--
-- A trava 5.2 impede que isso aconteça por qualquer outro caminho — é de
-- propósito. Sem essa linha, ninguém consegue criar a primeira academia.
-- =====================================================================
