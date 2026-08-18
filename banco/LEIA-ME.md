# O banco do Meu Treino

**Já está instalado e testado.** Este arquivo explica o que existe lá, como
refazer do zero se precisar, e as consequências que só apareceram depois de
rodar de verdade.

| | |
|---|---|
| Projeto | `meu-treino` (ref `ivvzsneumirucwilpbrj`) |
| Região | São Paulo (`sa-east-1`) |
| URL da API | `https://ivvzsneumirucwilpbrj.supabase.co` |
| Plano | gratuito |

## Os arquivos

| Arquivo | Para quê |
|---|---|
| `01-esquema.sql` | Tudo: nove tabelas, funções, travas e regras. Refaz o banco do zero |
| `02-teste.sql` | Versão do teste para colar no SQL Editor à mão |

O `01-esquema.sql` é a fonte da verdade. **Ao mudar o banco, mude o arquivo
junto** — senão refazer o projeto depois traz de volta um banco diferente do
que está no ar.

## O que já foi feito

1. Esquema instalado em três migrações (`esquema_inicial_meu_treino`,
   `funcoes_e_travas`, `regras_de_permissao`).
2. Verificador de segurança do Supabase rodado. Ele apontou oito funções sem
   `search_path` fixo — corrigido na migração `fixa_search_path_das_funcoes` e
   no arquivo.
3. Teste das regras rodado com quatro pessoas e duas academias de mentira:
   **16 checagens, 16 OK**. Os dados de teste foram apagados no fim; as tabelas
   estão todas zeradas.

## Falta uma coisa para o sistema poder ser usado

Nenhuma academia pode ser criada enquanto não existir um **dono do sistema**, e
essa marca não se dá pela API de propósito. Depois de criar a sua conta:

```sql
update pessoas set suporte = true where email = 'voce@exemplo.com';
```

Tem que responder `UPDATE 1`.

## Consequências que só apareceram rodando

**Uma academia com pagamento anotado não pode mais ser apagada.** A trava que
impede apagar lançamento vale também quando o apagamento vem em cascata pela
academia. Isso é coerente com "dinheiro só cresce", mas significa que remover
uma academia cliente exige desligar a trava de propósito — foi o que o teste
precisou fazer para limpar depois de si.

**Uma pessoa com pagamento anotado também não pode ser apagada.** O lançamento
aponta para ela, e a chave estrangeira segura. Isso tem peso na LGPD: quando
alguém pedir para excluir a conta, a saída é **anonimizar o cadastro e manter o
lançamento**, não apagar. Precisa estar escrito no aviso de privacidade.

**Regra barrada nem sempre dá erro.** Em `INSERT` dá; em `UPDATE` e `DELETE` ela
apenas não mexe em linha nenhuma, em silêncio. Um teste que só espera exceção
reprova regras que estão funcionando. O `02-teste.sql` confere as duas formas.

## Dois avisos de segurança que ficam de propósito

O verificador do Supabase acusa `email_por_telefone` como função poderosa que
qualquer um pode chamar. **É intencional**: é ela que permite entrar pelo
telefone sem pagar SMS. O preço é que quem souber o telefone de alguém descobre
o e-mail dela.

Se um dia isso incomodar, apague a função e o login passa a ser só por e-mail.
Enquanto ficar, os dois avisos vão continuar aparecendo — não são descuido.

## As nove tabelas

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

**Papéis são acumuláveis.** Uma pessoa pode ser `professor` e `gestor` na mesma
academia. O `admin` já pode tudo sozinho — o dono não precisa acumular nada.

**As regras moram no banco, não na tela.** Ao criar tabela nova, ligue
`row level security` nela: sem isso ela nasce aberta. E ponha `set search_path`
em toda função nova, senão o verificador acusa — com razão.

**A pessoa é global, o vínculo é local.** Quem treina numa academia e dá aula em
outra é a mesma pessoa, com dois vínculos e um login só. Efeito colateral a
conhecer: se a recepção de uma academia corrigir o telefone dela, a outra
academia vê o telefone novo.

**O plano gratuito desliga o projeto após 7 dias sem uso.** É só reabrir pelo
painel. Quando entrar academia de verdade, US$ 25 por mês vira custo fixo.

## Refazendo do zero

Se algum dia precisar recomeçar: crie um projeto novo, cole o `01-esquema.sql`
inteiro no SQL Editor e rode. Depois o `02-teste.sql`, que precisa de quatro
usuários criados em Authentication › Users (ele explica no topo).
