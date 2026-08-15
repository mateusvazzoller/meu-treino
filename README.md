# Meu Treino

App para acompanhar um plano de treino no celular. Roda no navegador, instala na
tela inicial e funciona sem internet.

Nasceu do [Meu TAF](https://github.com/mateusvazzoller/taf), que atendia um plano
só — o da preparação para o TAF da Polícia Civil do Paraná. Aqui a ideia é
suportar **vários planos**, para que um professor possa entregar a cada aluno o
treino dele.

> **Em construção.** O que está publicado hoje é a base herdada do Meu TAF, com
> um **plano de exemplo** no lugar do treino real. Carregar planos diferentes é o
> próximo passo — hoje o plano ainda é código, não dado.

## O que já funciona

- Marcação de séries com progresso por sessão e por semana
- Timer de descanso automático e cronômetro para isometrias, com **aviso sonoro
  que continua valendo com o app minimizado**
- Registro de cargas, tempos, repetições e distâncias, comparando entre as semanas
- Vídeo demonstrativo embutido em cada exercício (precisa de internet), com espaço
  para salvar o link do professor — que tem prioridade
- Simulado de provas físicas, com metas digitadas pelo usuário
- Histórico das sessões concluídas, com duração e esforço
- Exportar e importar backup
- Tema claro e escuro, instalação na tela inicial e aviso de nova versão

## Como funciona

Uma página só, sem servidor e sem banco de dados. Tudo o que você marca fica
guardado no próprio aparelho (`localStorage`), então:

- Os dados não saem do celular e ninguém mais tem acesso a eles.
- Cada aparelho tem o próprio histórico — não sincroniza entre celulares.
- Limpar os dados do navegador apaga o histórico. Use *Exportar backup*.

## Arquivos

| Arquivo | Para que serve |
|---|---|
| `index.html` | O app inteiro — marcação, timers, registros e o plano de treino |
| `manifest.webmanifest` | Nome, cores e ícones usados na instalação na tela inicial |
| `sw.js` | Service worker: guarda o app no aparelho para abrir sem internet |
| `icons/` | Ícones do atalho |
| `sons/` | Avisos sonoros, com autoria e licença em `CREDITOS.txt` |
| `tools/` | Script que regera os ícones |
| `CLAUDE.md` | Contexto do projeto: estrutura, decisões e como alterar sem quebrar |

## Publicando

Serve qualquer hospedagem de site estático. No GitHub Pages: *Settings* →
*Pages* → *Deploy from a branch* → `main` / `root`.

Ao alterar o app, troque o número da versão em `sw.js`
(`const VERSAO = "meu-treino-v1"`) para que os celulares que já instalaram
recebam a atualização.

## Aviso

O app não prescreve treino: ele mostra o que um profissional prescreveu. O plano
que vem no repositório é **exemplo**, não recomendação — quem for treinar deve
passar por avaliação com um profissional de educação física.
