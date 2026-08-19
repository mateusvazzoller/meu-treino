# CLAUDE.md — contexto do projeto

**Meu Treino**: app de acompanhamento de treino que deve suportar **vários
planos**, para um professor entregar a cada aluno o treino dele.

Nasceu como cópia do [Meu TAF](https://github.com/mateusvazzoller/taf) na versão
`taf-v11` (agosto de 2026), que atendia um plano só — a preparação do dono do
repositório para o TAF da Polícia Civil do Paraná. Toda a máquina veio junto;
o treino da PCPR e os registros pessoais **não**.

O app não prescreve treino: ele mostra o que um profissional prescreveu.
**Não invente, não "corrija" e não complete exercícios, cargas ou progressões.**
Dúvida vira pergunta ao usuário, não suposição.

## O banco — instalado e testado

Projeto Supabase `meu-treino`, ref `ivvzsneumirucwilpbrj`, São Paulo, plano
gratuito. API em `https://ivvzsneumirucwilpbrj.supabase.co`. O esquema foi
aplicado em quatro migrações e o teste das regras passou nas 16 checagens.
Ver `banco/LEIA-ME.md`.

`banco/01-esquema.sql` é a **fonte da verdade**: ao mudar o banco, mude o
arquivo junto, senão refazer o projeto do zero traz de volta algo diferente
do que está no ar.

Existe conector MCP do Supabase ligado na conta do usuário, então dá para
aplicar migração e consultar direto daqui. Duas coisas que ele **não** faz e
continuam sendo do usuário: criar usuários (tem campo de senha) e marcar o
dono do sistema (`update pessoas set suporte = true`, de propósito impossível
pela API).

Decisões que já estão dentro do esquema e não devem ser desfeitas sem
conversa:

- **Multi-academia desde a primeira tabela.** Toda tabela tem `academia_id`,
  e as chaves estrangeiras são **compostas** (`ficha_id, academia_id`) para
  que "pertencer à mesma academia" seja garantido pela estrutura e não só
  pela regra. Acrescentar isso depois seria migrar tudo com dados reais
  dentro.
- **Papéis acumuláveis** (`vinculos.papeis` é um array), porque em academia
  pequena a mesma pessoa faz mais de uma coisa. O `admin` já pode tudo
  sozinho — o dono não precisa acumular.
- **A pessoa é global, o vínculo é local.** Um login por ser humano, mesmo
  que ele esteja em duas academias.
- **`lancamentos` só cresce.** Nem regra de update/delete, nem gatilho que
  permita. Errou, lança estorno.
- **As regras moram no banco.** Ao criar tabela nova, ligue
  `row level security` nela — sem isso ela nasce aberta a qualquer um.

Duas consequências que só apareceram rodando, e que valem para sempre:
**academia com lançamento não pode ser apagada** (a trava vale também na
cascata) e **pessoa com lançamento não pode ser apagada** (a chave estrangeira
segura). Na LGPD isso vira: pedido de exclusão se resolve anonimizando o
cadastro e preservando o lançamento, nunca apagando.

Toda função nova precisa de `set search_path` — sem isso o verificador do
Supabase (`get_advisors`) acusa, com razão. Rode-o depois de cada mudança de
estrutura.

Ao mexer nas regras, lembre que uma tentativa barrada **nem sempre dá
erro**: em `INSERT` dá, em `UPDATE`/`DELETE` ela apenas não mexe em linha
nenhuma, em silêncio. Um teste que só espera exceção passa achando que
falhou — foi um erro real na primeira versão do `02-teste.sql`.

## Conta e login — feito

O app exige entrar. A tela de login substitui tudo quando não há sessão, e a
decisão é tomada por um script no `<head>` (classe `sem-conta`), antes de a
página desenhar — mesmo motivo da capa: senão o app pisca antes de sumir.

**Sem biblioteca, de propósito.** O Supabase é REST comum, e as quatro chamadas
que o app usa (descobrir e-mail pelo telefone, entrar, renovar, sair) couberam
em ~120 linhas. A biblioteca oficial passa de 100 KB num app de 240 KB que tem
que funcionar sem internet. Se um dia entrar `supabase-js`, ela precisa ser
**arquivo do repositório** e entrar em `ARQUIVOS` no `sw.js` — nunca CDN, que
quebra o offline.

**A chave `sb_publishable_...` no código é pública de propósito.** Ela só
identifica o projeto e está à vista em qualquer app Supabase. Quem protege os
dados são as regras do banco. A chave `service_role` **nunca** entra aqui.

**Entrar exige internet uma vez; depois o app abre offline.** A sessão fica em
`meu-treino-sessao`. Regra que não pode ser desfeita: falha de rede ao renovar
o crachá **não desloga** — só recusa explícita do servidor (400/401) desloga.
Testado com o servidor inalcançável e o crachá vencido: o app abriu e a sessão
sobreviveu.

**Sair não apaga o treino local.** Hoje os registros ainda são do aparelho, não
da conta. Quando a sincronização existir (fase 5), isso vira uma decisão: ou o
`sair` limpa os dados locais, ou eles passam a ser guardados por pessoa. Num
aparelho compartilhado da academia, deixar como está vaza o treino de um aluno
para o próximo.

**Entrar pelo telefone** usa `email_por_telefone` e aceita o número formatado
(`(41) 98888-7777`). Só funciona para quem tem telefone em `pessoas` — quem não
tem entra pelo e-mail.

### Armadilha ao criar usuário à mão para testar

Usuário inserido direto em `auth.users` por SQL faz o login devolver
`500 Database error querying schema`. O motivo: o GoTrue espera **texto vazio**
nas colunas de token (`confirmation_token`, `recovery_token`, etc.) e o insert
deixa nulo. A correção é preencher todas as colunas de texto com `''`. Usuário
criado pelo painel não tem esse problema — só `phone` fica nulo, e isso é
normal.

## A recepcao cadastra — feito

Cadastro publico esta LIGADO no Supabase mas exige confirmacao por e-mail, e
nao ha e-mail: toda tentativa devolve `over_email_send_rate_limit`. Por isso a
conta do aluno nasce pela recepcao, na funcao `servidor/criar-pessoa`.

Regra que organiza aquela funcao e nao deve ser afrouxada: **a chave de
administracao serve so para criar o login**. Conferir quem chama e criar o
vinculo vao com o cracha de quem chamou, para a regra do banco decidir em vez
do codigo. Ver `servidor/LEIA-ME.md`.

A regra `admin cria vinculo` estava mais estrita que a tabela de papeis deste
arquivo — a recepcao nao conseguiria matricular ninguem. Corrigido: recepcao e
gestor vinculam, mas **so como `aluno`**; qualquer outro papel continua sendo
do admin.

A aba **Gestao** cobre isso: criar academia (dono do sistema), escolher a
academia, listar as pessoas, cadastrar e ligar/desligar papel tocando nos
chips. Ela so aparece para quem tem o que gerir — mas esconder e arrumacao,
nao protecao: testado forcando a API como aluna, ela enxerga so a si mesma e
criar academia devolve 403.

### A senha provisória não é mais definitiva — feito

A conta nasce com `user_metadata.trocar_senha = true` (posto pela função
`criar-pessoa`), e o app põe a tela **"Crie a sua senha"** na frente de tudo
no primeiro acesso. Salvar manda um `PUT /auth/v1/user` com a senha nova e
`data:{trocar_senha:false}` — **uma chamada só**, o que evita o estado
intermediário de senha trocada com o aviso ainda ligado.

Não houve tabela nem regra nova de propósito: o aviso vive no próprio
usuário. A contrapartida, escrita no código: a pessoa consegue, em tese,
desligar o aviso pela API sem trocar a senha. **Só ela perde com isso, e
nada no sistema usa esse campo para proteger dado nenhum** — é lembrete, não
tranca.

A senha digitada no login fica numa variável em memória (`senhaAntiga`) só
até a troca acontecer. É o que permite recusar "trocar" a senha pela mesma
que a recepção anotou no papel. Nunca é gravada em lugar nenhum, e some no
`sair`.

Nos Ajustes há **Trocar senha** para qualquer momento; aí, e só aí, aparece
o "Agora não".

**Quem já tinha conta antes disto não é incomodado**: sem o campo no
usuário, o app não pede nada. As duas contas criadas durante o
desenvolvimento continuam com a senha que têm — se uma delas for virar conta
de aluno de verdade, troque pelos Ajustes.

## A ficha vira dado — feito

`PLAN` não é mais escrito à mão: é o `conteudo` da ficha que o professor
entregou, baixado do banco e **guardado no aparelho** (`meu-treino-ficha`).
O formato do array é o MESMO nos dois lados de propósito — qualquer tradução
entre banco e tela seria um lugar a mais para o treino sair diferente do que
o professor escreveu.

O caminho inteiro: `fichas.conteudo` → `atribuicoes` (a entrega) → app do
aluno → `registros` (o que ele marcou).

Regras que sustentam isso e não devem ser desfeitas:

- **Falha de rede não apaga a ficha.** Só uma resposta clara do servidor
  dizendo "não há entrega ativa" tira a ficha do aparelho. Mesmo princípio do
  crachá: ficar sem treino no meio do exercício é pior do que estar um dia
  desatualizado.
- **`sair` leva a ficha junto.** Na academia o celular passa de mão em mão. O
  que o aluno MARCOU fica — apagar registro de treino sem pedir seria pior.
- **A chave começa pela entrega** (`kPre()` = 8 primeiros dígitos do
  `atribuicao_id`). Sem isso, duas fichas com sessões de mesmo id nasceriam
  com as séries da anterior já marcadas.
- **O número de semanas é da ficha** (`NSEM`), não mais 4 fixo. `bs()` repete
  a última semana escrita quando o professor variou só algumas — nunca
  inventa progressão.

### O que sobe de volta: uma linha por entrega

`registros` guarda **uma linha por entrega**, `chave = 'estado'`, com o estado
inteiro daquela ficha dentro do `valor`. O banco aceitaria uma linha por série
marcada, mas aí cada toque viraria uma ida ao servidor — e treino acontece
justamente onde o sinal é ruim.

O preço está escrito no código: **o último aparelho a mandar vence**. Para um
aluno com um celular, nunca acontece. Se um dia virar problema, o caminho é
uma linha por chave, e o formato de dentro já é esse.

`save()` marca pendente e agenda a subida; `save(true)` grava calado, e é o
que se usa quando o que mudou VEIO do servidor — sem isso o app devolveria ao
servidor o que acabou de receber, para sempre.

**Baixar vem depois de mandar.** Se o aparelho tem coisa que o servidor não
tem, ele manda primeiro; senão o treino de hoje sumiria para dar lugar ao de
ontem.

### Entregar ficha — feito. Montar ficha — não.

A aba Gestão lista as fichas da academia, mostra quem está com cada uma,
entrega a um aluno e encerra. **Montar a ficha ainda não existe**: até o
cliente escolher entre os três estudos (A: professor escreve; B: escolhe de
uma lista; C: entrega um programa pronto), a lista só tem o que for criado
direto no banco.

Entregar uma ficha nova **encerra a anterior do mesmo aluno**, porque o app
mostra uma ficha por vez. Se a anterior for de outro professor, o banco recusa
**em silêncio** — por isso o `Prefer: return=representation` nos UPDATE, que
faz o servidor dizer quantas linhas mexeu. Sem ele, "encerrei" apareceria na
tela sem nada ter acontecido.

**Armadilha viva:** `kSess`, `kDone` e `kLog` montam a chave com `PLAN[d].id`.
Sem ficha, `PLAN[d]` não existe e o app quebrava **uma vez por segundo**, no
relógio do topo. As três (mais `totalSets`, `doneSets` e `bs`) têm guarda.
Qualquer função nova que indexe `PLAN` precisa da mesma.

## O trabalho que ainda não foi feito

### Ninguém consegue se colocar numa academia pelo app

A Gestão só sabe **criar pessoa nova** (que cria um login). Não há como
vincular alguém que **já tem conta** a uma academia — nem a si mesmo.

Apareceu no primeiro teste de ponta a ponta: o dono do sistema não é membro
de academia nenhuma (ele enxerga todas para administrar), então não aparecia
na lista de quem pode receber ficha, e não havia como ele receber a própria
ficha. Foi resolvido com um `insert` à mão em `vinculos` — o que não é
resposta para um cliente.

Numa academia de verdade isso aparece de três jeitos: o dono quer treinar,
um professor de outra unidade passa a dar aula nesta, e um aluno que já
treinou em outra academia do sistema volta. Nos três, a pessoa existe e o
que falta é só o vínculo.

O caminho provável é uma busca por e-mail ou telefone dentro do cadastro:
achou alguém, cria o vínculo em vez de um login novo. **Cuidado ao fazer**:
a busca não pode virar uma forma de descobrir quem existe no sistema — a
regra `vejo a mim e a quem eu administro` está lá justamente para isso, e
uma busca livre a contorna.

### As provas ainda são código

`PROVAS` tem as cinco provas do TAF da PCPR escritas no `index.html`. Numa
academia comum elas não fazem sentido — por isso `MOSTRA_SIMULADO = false`.
Se um cliente preparar para concurso, elas precisam virar dado da ficha, do
mesmo jeito que o treino virou.

O que **não** muda nunca: as METAS não vêm do código. Os índices mudam por
idade e sexo, então quem digita é o usuário, com o edital na mão.

### Simulado desligado, não apagado

`var MOSTRA_SIMULADO = false;` esconde a aba e devolve quem estiver nela para
o Treino. O código, `PROVAS` e `S.taf` continuam inteiros: numa academia comum
as cinco provas do TAF da PCPR não fazem sentido, mas num cliente que prepare
para concurso fazem. Voltar é trocar para `true`, e nada mais.

Sobrou um vizinho do mesmo mundo: o ajuste **"Dia da prova"**, que liga a
contagem regressiva na capa (`S.cfg.prova`). Continua ligado porque não é o
simulado — mas numa academia o rótulo soa estranho e vale renomear ou
esconder junto quando alguém decidir.

## Armadilha herdada: os dois apps dividem o mesmo endereço

`meu-treino` e `taf` são publicados no **mesmo domínio**
(`mateusvazzoller.github.io`), em pastas diferentes. O navegador guarda dados
**por domínio, não por pasta** — então `localStorage`, `sessionStorage` e o
Cache Storage são compartilhados entre os dois apps. Se as chaves colidirem, um
app apaga os dados do outro.

Por isso, e **nunca volte atrás nisso**:

| | Meu TAF | Meu Treino |
|---|---|---|
| `localStorage` | `taf-pcpr-v1` | `meu-treino-v1` |
| `sessionStorage` | `taf-aberto` | `meu-treino-aberto` |
| Cache do SW (`VERSAO`) | `taf-vN` | `meu-treino-vN` |
| Sessão | — | `meu-treino-sessao` |
| Ficha baixada | — | `meu-treino-ficha` |
| Estado da sincronia | — | `meu-treino-sync` |

Ao criar qualquer chave nova, prefixe com `meu-treino-`.

**A pegadinha mais difícil de ver está no `activate` do service worker.** A
faxina de caches velhos varre `caches.keys()`, que também é por domínio: a
versão original apagava tudo que não fosse a versão atual e, com dois apps no
mesmo domínio, cada um destruía o cache offline do outro ao ser aberto. O
sintoma seria "o outro app parou de funcionar sem internet", horas depois e
sem relação aparente. Por isso a faxina é filtrada por `PREFIXO` nos dois
repositórios — não remova esse filtro.

**O QR do endereço também foi vítima disso.** O `index.html` nasceu como cópia
e ficou com o QR e o texto do `/taf/` — quem lesse o código na tela de instalar
baixaria o app errado. Foi confirmado lendo o QR de volta com um decodificador,
não no olho: um QR errado é indistinguível de um certo. Regerar é
`python tools/gerar-qr.py`, e o `<path>` e o texto do `#iUrl` mudam **juntos**.

Pela mesma razão o **ícone é azul** (`#4A90FF`) e o do Meu TAF é laranja: os dois
convivem na mesma tela inicial e precisam ser distinguíveis a 48 px. A marca (o
T construído) é a mesma de propósito — são irmãos.

## Arquivos

| Arquivo | Papel |
|---|---|
| `index.html` | **Fonte única da verdade.** O app inteiro: dados, estilos e lógica |
| `manifest.webmanifest` | Nome, cores e ícones da instalação |
| `sw.js` | Service worker — funcionamento offline |
| `icons/` | Ícones PNG, gerados por `tools/gerar-icones.py` |
| `sons/` | Avisos sonoros em MP3 + `CREDITOS.txt` com autoria e licença |
| `tools/gerar-icones.py` | Regera os ícones a partir das cores do app |
| `tools/gerar-qr.py` | Regera o QR do endereço do app (precisa de `pip install qrcode`) |
| `banco/` | Estrutura do Supabase: tabelas, regras de permissão e o teste delas |

Não existe build, bundler nem dependência. Editar `index.html` e dar push é o
fluxo completo.

## Estrutura do `index.html`

Tudo em um arquivo só, nesta ordem: `<style>` com os tokens e componentes, o
HTML da casca, e um `<script>` com uma IIFE contendo dados, estado e render.

### Dados do treino — `PLAN`

Array de sessões. Cada sessão tem `blocos`, e cada bloco tem `sem`: um array de
**exatamente 4 posições**, uma por semana.

```js
{ id:"b2", t:"Agachamento búlgaro", tipo:"Complexo", nota:"…", sem:[ cfgS1, cfgS2, cfgS3, cfgS4 ] }
```

Cada `cfg` de semana:

| Campo | O que é |
|---|---|
| `s` | Número de séries (vira a quantidade de chips marcáveis) |
| `r` | Descanso em segundos que alimenta o timer |
| `rt` | Descanso como o professor escreveu, ex. `"1:00 a 2:00 entre os tiros"` |
| `ritmo` | Só para EMOM — substitui a etiqueta de descanso e troca "séries" por "rodadas" |
| `it` | Exercícios: `{ n:nome, p:prescrição, reg:{t:tipo} }` |

Helpers: `eq(x)` repete a mesma config nas 4 semanas, `pair(a,b)` faz semanas 1-2
com `a` e 3-4 com `b`.

**Distinção que importa:** `rt` é o que o professor mandou e aparece com a
etiqueta "Descanso" destacada; quando o bloco não tem `rt`, o `r` é sugestão
nossa e aparece só como tempo. Não apresente sugestão como prescrição.

### Registros — `REG`

Tipos de campo que o usuário preenche: `kg`, `reps`, `seg`, `tempo` (mm:ss), `m`.
Os de tempo (`seg`, `tempo`) ganham botão de cronômetro que preenche o campo
sozinho ao salvar.

### Vídeos — `VID` e `VIDEO`

`VID` é o mapa `nome do exercício → termos de busca` (fallback). `VIDEO` é o mapa
curado `nome do exercício → {id, t, c, d}` (id do YouTube, título, canal,
duração) que alimenta o player embutido no painel ▶. Prioridade ao abrir:

1. Link salvo pelo usuário (`S.vid`) — se for do YouTube, também toca embutido.
2. Vídeo curado de `VIDEO` — player embutido + crédito do canal + link externo.
3. Busca no YouTube com os termos de `VID`, em outra aba.

**Não inventar IDs.** Os IDs vieram do Meu TAF, onde foram encontrados por busca
real e verificados um a um via oEmbed (que também acusa vídeo com incorporação
desativada) em 10/08/2026. Ao trocar ou acrescentar um vídeo, verifique do mesmo
jeito. O iframe (`youtube-nocookie.com`) é criado só quando o painel abre e é
removido ao fechar. O player precisa de internet; o restante do app segue
funcionando offline.

### Simulado — `PROVAS` e `S.taf`

Aba própria (`S.tab === "sim"`, render em `renderSim()`). Cada prova tem `dir`
(1 = quanto maior melhor; -1 = quanto menor melhor), `bool` para prova de
sim/não e `timer` opcional que abre o cronômetro já no tempo da prova.

**As metas são digitadas pelo usuário, nunca embutidas no código.** Os índices
mínimos mudam por idade e sexo e saem do edital — o app só compara o resultado
com o número que o usuário colocou em "Meta do edital". Não invente esses
valores, nem como sugestão.

`S.taf = { metas:{idProva: "valor"}, tests:[{p, v, d, ts}] }`. O veredito sai de
`passou()`, que devolve `null` quando não há meta.

### Estado — `S` e `localStorage`

Chave `meu-treino-v1`. Campos persistidos listados em `FIELDS`; `snapshot()`
monta o objeto exportado. Formato das chaves:

```
done  →  "w{semana}|{idSessao}|{idBloco}|{indiceSerie}"
logs  →  "w{semana}|{idSessao}|{idBloco}|{indiceExercicio}|{indiceSerie}"
sess  →  "w{semana}|{idSessao}"     (concluída: data, contagem, dur, rpe)
notas →  "w{semana}|{idSessao}"
ini   →  "w{semana}|{idSessao}"     (Date.now da 1ª série — tempo do treino)
vid   →  "{nome do exercício}"
taf   →  { metas, tests }           (simulados; não é por semana)
tab   →  aba atual
```

Em `cfg`: `prova` (data do objetivo, "AAAA-MM-DD", liga a contagem regressiva) e
`somTipo` (qual arquivo de `sons/` toca).

Tudo fica no aparelho. **Não há sincronização entre celulares** — é o preço de
funcionar offline sem servidor. A saída é ⚙ Ajustes → Exportar/Importar backup.

## Decisões herdadas que não devem ser desfeitas

Todas foram pagas com bug ou com rejeição do usuário no projeto anterior.

**O ícone é um T construído** (travessão = barra, haste = corpo), escuro sobre
fundo sólido azul. Não é a palavra escrita: três letras viram três elementos de
~14 px quando o ícone é visto a 48 px. Ao mexer, rode `tools/gerar-icones.py`,
que produz as três famílias (`any`, `maskable`, `monochrome`) — elas não são
intercambiáveis, e o cabeçalho do script explica a diferença. **Nunca** declare
`"purpose": "any maskable"` no mesmo arquivo. Valide a 48 px, não no tamanho
grande.

**Aviso sonoro é gravação, não síntese.** As primeiras versões geravam bipes com
osciladores e o usuário rejeitou duas vezes: "toque monofônico é muito feio".
Cada opção é um MP3 curto em `sons/`, tocado por Web Audio a partir de um
`AudioBuffer` — o mesmo arquivo serve para tudo: inteiro no fim do descanso, os
primeiros 0,55 s como confirmação, os primeiros 0,13 s na contagem 3-2-1. A
síntese sobrou só como reserva.

Ao trocar um som, **confira onde o som começa de fato** (envelope de energia, não
confie no nome do arquivo): como a contagem toca só os 130 ms iniciais, um
arquivo que começa devagar sai mudo. Iguale o volume **médio** (≈ −16 dBFS), não
o de pico, senão uma opção parece muito mais baixa que as outras. Os arquivos
ficam em `ARQUIVOS` no `sw.js` para tocarem offline.

**Cronômetro usa `Date.now()`, não `requestAnimationFrame`.** A primeira versão
acumulava deltas de rAF e o timer congelava quando a tela apagava — inaceitável
para descanso de treino. `T.anchor` guarda o instante alvo e o tempo é sempre
derivado do relógio; `setInterval` só redesenha. **O tempo total do treino segue
a mesma regra**: `S.ini` guarda o instante da primeira série.

**O aviso de fim de descanso não depende do JavaScript estar rodando.** Com o app
minimizado o navegador congela o `setInterval`. `agendaAvisos()` marca a contagem
3-2-1 e o aviso final direto na placa de áudio (`src.start(instanteAbsoluto)`),
que roda em outra linha de execução. Duas armadilhas: (1) o áudio do app é
desligado quando ele sai da frente, então `segurarAudio(true)` põe um tom de
200 Hz a −68 dB em looping **no `visibilitychange` para `hidden`** — só fora da
tela, senão atrapalharia música tocando durante o treino; (2) o `loop()` precisa
saber se o som já saiu sozinho, senão toca de novo ao voltar — daí a comparação
`actx.currentTime >= T.fimAudio`. Toda mudança no descanso (±15, pausa, play,
trocar o som) tem que chamar `agendaAvisos()` de novo, e `cancelaAgenda()` só
interrompe o que ainda não começou, senão cortaria o aviso no meio.

**O relógio do topo some quando o treino é concluído.** Antes ele congelava no
total e ficava parado no cabeçalho — o usuário leu isso como "não zera". O total
vai para `S.sess[nk].dur`, aparece no botão "Concluído em …" e no Histórico.
Reabrir o treino devolve o relógio de onde parou.

**Capa a cada abertura do app, não a cada carregamento da página.** A marca fica
no `sessionStorage` (`meu-treino-aberto`) e um script no `<head>` — antes de a
página desenhar, senão a capa pisca — põe a classe `ja-abriu` no `<html>`. O
`sessionStorage` é o que separa os três casos: sobrevive a um recarregamento
(inclusive ao que o próprio app faz depois de uma atualização) e ao app
minimizado, mas é apagado quando o app é fechado de verdade.

**Atualização avisa em vez de trocar em silêncio.** App instalado pode ficar
semanas com a versão velha. O app chama `reg.update()` toda vez que volta para a
frente e mostra a faixa `#upd` quando o service worker novo assume. Cuidado com
`jaControlado`: a **primeira** troca de controlador é a instalação inicial e não
deve virar aviso — um bug real morava aí.

**O botão de instalar não promete o que não pode cumprir.** No iOS a Apple não
permite instalação programática — o botão mostra o passo a passo do Safari. No
Android ele dispara o `beforeinstallprompt` quando o Chrome oferece. Detecta
também se está dentro de um iframe/webview e avisa para abrir no navegador, que
é a causa nº 1 de "não instala".

**Tema claro e escuro via tokens.** Os componentes só usam variáveis CSS; o tema
é redefinido em `@media (prefers-color-scheme)` e nos seletores
`:root[data-theme]`. Nunca estilizar componente dentro do media query — já deu
colisão de especificidade uma vez, resolvida com o token `--on-good`.

## Publicar uma alteração

```bash
cd "C:/Users/Matheus/Documents/Treino/meu-treino" && git add -A && git commit -m "…" && git push
```

O Pages reconstrói sozinho em 30 a 60 segundos.

**Ao alterar `index.html`, troque a versão em `sw.js`**
(`const VERSAO = "meu-treino-v1"` → `"meu-treino-v2"`). Sem isso, quem já
instalou pode continuar com a versão velha em cache. É o erro mais fácil de
cometer aqui.

**Publicar exige autorização explícita do usuário na hora.** Commit local pode;
`git push` só com o "pode publicar" dele.

- Site: https://mateusvazzoller.github.io/meu-treino/
- Repositório: https://github.com/mateusvazzoller/meu-treino

## Como testar

Service worker e manifest **não funcionam em `file://`**. Suba um servidor:

```bash
python -m http.server 8766 --bind 127.0.0.1 --directory meu-treino
```

Depois abra `http://127.0.0.1:8766/` e confira no console: service worker ativo,
manifest válido, cache populado. Para provar o offline, derrube o servidor e
recarregue — o app tem que abrir inteiro. Em `file://` o embed do YouTube também
não funciona (erro 153).

## Como falar com o usuário

Português do Brasil. Ele não é programador: explique em termos do que acontece na
tela e no celular, não em termos de código. Ele valoriza saber o que **não**
funciona e por quê — limitação do iOS, dado que não sincroniza, repositório
público. Não prometa o que a plataforma não entrega.
