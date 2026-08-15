# O banco do Meu Treino

Dois arquivos, na ordem. O primeiro cria tudo; o segundo confere se as
regras estão segurando.

## Antes de tudo

Você precisa criar a conta e o projeto no Supabase — é a única parte que
ninguém faz por você. É gratuito e não pede cartão.

1. Entre em <https://supabase.com> e crie a conta.
2. **New project.** Nome: `meu-treino`. Região: **South America (São Paulo)** —
   quanto mais perto, mais rápido o app responde.
3. Guarde a senha do banco que ele mostrar. Ela aparece **uma vez só**.
4. Espere uns dois minutos até o projeto ficar pronto.

## Passo 1 — criar as tabelas

No painel, vá em **SQL Editor › New query**, cole o conteúdo de
[`01-esquema.sql`](01-esquema.sql) inteiro e clique em **Run**.

Deve terminar com `Success. No rows returned`. Se der erro, ele para no
primeiro problema e não deixa nada pela metade — me mande a mensagem.

Depois disso, em **Table Editor**, você deve ver as nove tabelas:
`academias`, `pessoas`, `vinculos`, `fichas`, `atribuicoes`, `registros`,
`planos`, `matriculas`, `lancamentos`.

## Passo 2 — nomear o dono do sistema

Nenhuma academia pode ser criada enquanto não existir um dono do sistema, e
essa marca é de propósito impossível de dar pela API — só à mão, aqui.

1. **Authentication › Users › Add user.** Use o seu e-mail de verdade e
   marque **Auto Confirm User**.
2. Volte ao **SQL Editor** e rode, trocando pelo seu e-mail:

```sql
update pessoas set suporte = true where email = 'voce@exemplo.com';
```

Se isso responder `UPDATE 0`, a pessoa não foi criada — confira o e-mail.

## Passo 3 — conferir se as regras seguram

Não pule este passo. Ele é o que separa "as tabelas existem" de "uma
academia não enxerga a outra".

1. Crie **quatro usuários de teste** em Authentication › Users, com e-mails
   inventados (`dona.a@teste.local` e companhia), todos com **Auto Confirm**.
2. Abra [`02-teste.sql`](02-teste.sql), troque os quatro e-mails no topo se
   tiver usado outros, e rode inteiro no SQL Editor.

A resposta aparece na aba de mensagens, uma linha por checagem. O fim tem
que dizer:

```
  passou: 16     falhou: 0
  Todas as regras seguraram.
```

**Se aparecer qualquer `FALHOU`, pare.** Significa que alguém consegue ver
ou mudar o que não devia, e seguir em frente só empilha código em cima de
um buraco.

O teste roda dentro de uma transação e desfaz tudo no fim — nenhuma
academia de mentira fica no banco. Só os quatro usuários continuam lá;
apague-os pelo painel quando quiser.

## O que fica guardado onde

| Tabela | O que é |
|---|---|
| `academias` | Cada academia cliente |
| `pessoas` | Um ser humano, um login. Existe **uma vez** no sistema inteiro |
| `vinculos` | A pessoa dentro de uma academia, com os papéis dela ali |
| `fichas` | O treino prescrito |
| `atribuicoes` | Qual aluno faz qual ficha |
| `registros` | O que o aluno marcou — mesmo formato de chave que o app usa hoje |
| `planos` | O que a academia vende: mensal, trimestral, anual |
| `matriculas` | O aluno num plano |
| `lancamentos` | Pagamento anotado. **Só cresce** |

Mais a visão `inadimplencia`, que não guarda nada: é a consulta de quem tem
matrícula ativa sem pagamento no mês.

## Coisas que valem saber

**Papéis são acumuláveis.** Uma pessoa pode ser `professor` e `gestor` na
mesma academia. O `admin` já pode tudo sozinho — o dono não precisa
acumular nada.

**As regras moram no banco, não na tela.** Checagem feita só no app se
contorna pelo menu de desenvolvedor do navegador. Ao criar tabela nova,
lembre de ligar `row level security` nela — sem isso ela nasce aberta.

**Lançamento não se edita nem se apaga.** Errou, registre um estorno. Isso
é o que permite responder "para onde foi aquele R$ 120" seis meses depois.

**A pessoa é global, o vínculo é local.** Quem treina numa academia e dá
aula em outra é a mesma pessoa, com dois vínculos e um login só. Efeito
colateral a conhecer: se a recepção de uma academia corrigir o telefone
dela, a outra academia vê o telefone novo. É o mesmo ser humano — mas se
isso incomodar, é aqui que se mexe.

**Entrar pelo telefone tem um preço.** A função `email_por_telefone` deixa
quem souber o número de alguém descobrir o e-mail dela. Foi o jeito de ter
login por telefone sem pagar SMS. Se preferir não correr esse risco, apague
a função e o login passa a ser só por e-mail.

**O plano gratuito desliga o projeto após 7 dias sem uso.** Enquanto for só
você construindo, é só reabrir pelo painel. Quando entrar academia de
verdade, US$ 25 por mês vira custo fixo.
