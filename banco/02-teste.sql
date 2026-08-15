-- =====================================================================
-- Meu Treino — teste das regras de permissão
--
-- Prova que uma academia não enxerga a outra e que as travas seguram.
-- Roda inteiro dentro de uma transação e DESFAZ TUDO no fim: nada do que
-- este arquivo cria fica no banco.
--
-- ANTES DE RODAR, crie quatro usuários pelo painel do Supabase, em
-- Authentication › Users › Add user (pode usar e-mails inventados; marque
-- "Auto Confirm User"). Depois troque os quatro e-mails no topo do bloco.
--
-- Detalhe que enganou até a primeira versão deste arquivo: no Postgres,
-- uma tentativa BARRADA pela regra de permissão nem sempre dá erro. Em
-- INSERT ela dá; em UPDATE e DELETE ela simplesmente não mexe em linha
-- nenhuma, em silêncio. Por isso cada teste abaixo aceita as duas formas
-- de recusa — erro OU zero linhas — e só reprova se a operação passar.
-- =====================================================================

begin;

do $teste$
declare
  -- >>> TROQUE ESTES QUATRO <<<
  email_dona_a  text := 'dona.a@teste.local';
  email_aluno_a text := 'aluno.a@teste.local';
  email_prof_b  text := 'prof.b@teste.local';
  email_aluno_b text := 'aluno.b@teste.local';

  dona_a  uuid;  aluno_a uuid;  prof_b uuid;  aluno_b uuid;
  acad_a  uuid;  acad_b  uuid;
  ficha_a uuid;  plano_a uuid;  matr_a uuid;  lanc_a uuid;
  n       int;
  passou  int := 0;
  falhou  int := 0;
begin
  -- ---- quem é quem -----------------------------------------------------
  select id into dona_a  from pessoas where email = email_dona_a;
  select id into aluno_a from pessoas where email = email_aluno_a;
  select id into prof_b  from pessoas where email = email_prof_b;
  select id into aluno_b from pessoas where email = email_aluno_b;

  if dona_a is null or aluno_a is null or prof_b is null or aluno_b is null then
    raise exception 'Não achei os quatro usuários. Crie-os em Authentication › Users e ajuste os e-mails no topo deste arquivo.';
  end if;

  -- ---- monta duas academias separadas ----------------------------------
  -- Este trecho roda como dono do banco, que passa por cima das regras —
  -- é assim que o painel funciona. As regras só entram em cena depois do
  -- set_config('role','authenticated') mais abaixo.
  insert into academias (nome) values ('Academia A — teste') returning id into acad_a;
  insert into academias (nome) values ('Academia B — teste') returning id into acad_b;

  insert into vinculos (academia_id, pessoa_id, papeis)
    values (acad_a, dona_a,  array['admin','professor','gestor']::papel[]),
           (acad_a, aluno_a, array['aluno']::papel[]),
           (acad_b, prof_b,  array['admin','professor']::papel[]),
           (acad_b, aluno_b, array['aluno']::papel[]);

  insert into fichas (academia_id, professor_id, nome, conteudo)
    values (acad_a, dona_a, 'Ficha A', '[]'::jsonb) returning id into ficha_a;
  insert into atribuicoes (academia_id, ficha_id, aluno_id, professor_id)
    values (acad_a, ficha_a, aluno_a, dona_a);
  insert into planos (academia_id, nome, valor)
    values (acad_a, 'Mensal', 120.00) returning id into plano_a;
  insert into matriculas (academia_id, aluno_id, plano_id)
    values (acad_a, aluno_a, plano_a) returning id into matr_a;
  insert into lancamentos (academia_id, matricula_id, aluno_id, valor, forma,
                           competencia, registrado_por)
    values (acad_a, matr_a, aluno_a, 120.00, 'pix', current_date, dona_a)
    returning id into lanc_a;

  raise notice '--- montado: 2 academias, 4 pessoas, 1 ficha, 1 matrícula, 1 pagamento ---';

  -- ---- a partir daqui as regras valem ----------------------------------
  perform set_config('role', 'authenticated', true);

  -- =====================================================================
  -- FINGINDO SER O PROFESSOR DA ACADEMIA B
  -- =====================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', prof_b)::text, true);

  select count(*) into n from fichas where academia_id = acad_a;
  if n = 0 then passou := passou + 1; raise notice 'OK      não vê a ficha da outra academia';
  else falhou := falhou + 1; raise warning 'FALHOU  viu % ficha(s) da academia A', n; end if;

  select count(*) into n from lancamentos where academia_id = acad_a;
  if n = 0 then passou := passou + 1; raise notice 'OK      não vê o caixa da outra academia';
  else falhou := falhou + 1; raise warning 'FALHOU  viu % lançamento(s) da academia A', n; end if;

  select count(*) into n from pessoas where id = aluno_a;
  if n = 0 then passou := passou + 1; raise notice 'OK      não vê o cadastro do aluno da outra';
  else falhou := falhou + 1; raise warning 'FALHOU  viu o cadastro do aluno da academia A'; end if;

  select count(*) into n from matriculas where academia_id = acad_a;
  if n = 0 then passou := passou + 1; raise notice 'OK      não vê a matrícula da outra academia';
  else falhou := falhou + 1; raise warning 'FALHOU  viu % matrícula(s) da academia A', n; end if;

  -- =====================================================================
  -- FINGINDO SER O ALUNO DA ACADEMIA A
  -- =====================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', aluno_a)::text, true);

  select count(*) into n from fichas where id = ficha_a;
  if n = 1 then passou := passou + 1; raise notice 'OK      vê a própria ficha';
  else falhou := falhou + 1; raise warning 'FALHOU  não conseguiu ver a própria ficha'; end if;

  select count(*) into n from pessoas where id = dona_a;
  if n = 0 then passou := passou + 1; raise notice 'OK      aluno não vê o cadastro de outra pessoa';
  else falhou := falhou + 1; raise warning 'FALHOU  aluno viu o cadastro de outra pessoa'; end if;

  -- tenta se promover a admin
  begin
    update vinculos set papeis = array['admin']::papel[]
     where academia_id = acad_a and pessoa_id = aluno_a;
    get diagnostics n = row_count;
    if n = 0 then passou := passou + 1; raise notice 'OK      aluno não se promove (recusado em silêncio)';
    else falhou := falhou + 1; raise warning 'FALHOU  o aluno virou admin'; end if;
  exception when others then
    passou := passou + 1; raise notice 'OK      aluno não se promove (%)', left(sqlerrm, 44);
  end;

  -- tenta anotar um pagamento
  begin
    insert into lancamentos (academia_id, matricula_id, aluno_id, valor, forma,
                             competencia, registrado_por)
      values (acad_a, matr_a, aluno_a, 999.00, 'dinheiro', current_date, aluno_a);
    falhou := falhou + 1; raise warning 'FALHOU  o aluno anotou um pagamento';
  exception when others then
    passou := passou + 1; raise notice 'OK      aluno não anota pagamento';
  end;

  -- =====================================================================
  -- FINGINDO SER A DONA DA ACADEMIA A
  -- =====================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', dona_a)::text, true);

  select count(*) into n from lancamentos where academia_id = acad_a;
  if n = 1 then passou := passou + 1; raise notice 'OK      a dona vê o caixa da própria academia';
  else falhou := falhou + 1; raise warning 'FALHOU  a dona viu % lançamento(s), esperava 1', n; end if;

  select count(*) into n from lancamentos where academia_id = acad_b;
  if n = 0 then passou := passou + 1; raise notice 'OK      a dona não vê o caixa da academia B';
  else falhou := falhou + 1; raise warning 'FALHOU  a dona viu o caixa da academia B'; end if;

  -- nem ela edita um lançamento
  begin
    update lancamentos set valor = 1.00 where id = lanc_a;
    get diagnostics n = row_count;
    if n = 0 then passou := passou + 1; raise notice 'OK      lançamento não se edita (recusado em silêncio)';
    else falhou := falhou + 1; raise warning 'FALHOU  o lançamento foi editado'; end if;
  exception when others then
    passou := passou + 1; raise notice 'OK      lançamento não se edita (%)', left(sqlerrm, 44);
  end;

  -- nem ela apaga
  begin
    delete from lancamentos where id = lanc_a;
    get diagnostics n = row_count;
    if n = 0 then passou := passou + 1; raise notice 'OK      lançamento não se apaga (recusado em silêncio)';
    else falhou := falhou + 1; raise warning 'FALHOU  o lançamento foi apagado'; end if;
  exception when others then
    passou := passou + 1; raise notice 'OK      lançamento não se apaga (%)', left(sqlerrm, 44);
  end;

  -- nem ela muda o próprio papel
  begin
    update vinculos set papeis = array['professor']::papel[]
     where academia_id = acad_a and pessoa_id = dona_a;
    get diagnostics n = row_count;
    if n = 0 then passou := passou + 1; raise notice 'OK      nem a dona muda o próprio papel';
    else falhou := falhou + 1; raise warning 'FALHOU  a dona mudou o próprio papel'; end if;
  exception when others then
    passou := passou + 1; raise notice 'OK      nem a dona muda o próprio papel (%)', left(sqlerrm, 30);
  end;

  -- nem ela sai, sendo a única admin
  begin
    delete from vinculos where academia_id = acad_a and pessoa_id = dona_a;
    get diagnostics n = row_count;
    if n = 0 then passou := passou + 1; raise notice 'OK      a academia não fica sem admin';
    else falhou := falhou + 1; raise warning 'FALHOU  a academia A ficou sem nenhum admin'; end if;
  exception when others then
    passou := passou + 1; raise notice 'OK      a academia não fica sem admin (%)', left(sqlerrm, 34);
  end;

  -- nem ela entrega ficha para aluno de outra academia
  begin
    insert into atribuicoes (academia_id, ficha_id, aluno_id, professor_id)
      values (acad_a, ficha_a, aluno_b, dona_a);
    falhou := falhou + 1; raise warning 'FALHOU  entregou ficha para aluno de outra academia';
  exception when others then
    passou := passou + 1; raise notice 'OK      não entrega ficha para aluno de fora';
  end;

  -- mas ela CONSEGUE fazer o trabalho dela: anotar um pagamento
  begin
    insert into lancamentos (academia_id, matricula_id, aluno_id, valor, forma,
                             competencia, registrado_por)
      values (acad_a, matr_a, aluno_a, 120.00, 'dinheiro',
              (current_date - interval '1 month')::date, dona_a);
    passou := passou + 1; raise notice 'OK      a dona consegue anotar pagamento';
  exception when others then
    falhou := falhou + 1; raise warning 'FALHOU  a dona NÃO conseguiu anotar pagamento: %', left(sqlerrm, 60);
  end;

  raise notice '=====================================================';
  raise notice '  passou: %     falhou: %', passou, falhou;
  if falhou > 0 then
    raise notice '  ATENÇÃO: alguma regra não está segurando.';
    raise notice '  Não siga para a próxima fase antes de resolver.';
  else
    raise notice '  Todas as regras seguraram.';
  end if;
  raise notice '=====================================================';
end
$teste$;

-- Desfaz tudo: as academias, vínculos, fichas e lançamentos de teste não
-- ficam no banco. Só os quatro usuários que você criou pelo painel
-- continuam lá — apague-os por lá quando não precisar mais.
rollback;
