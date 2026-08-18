# A parte que roda no servidor

Uma função só, e ela existe por um motivo específico: **criar um login é a
única coisa que o app no celular não pode fazer sozinho** sem receber poder
demais.

## `criar-pessoa`

A recepção cadastra alguém na academia dela e recebe de volta uma senha
provisória para entregar.

```
POST https://ivvzsneumirucwilpbrj.supabase.co/functions/v1/criar-pessoa
Authorization: Bearer <crachá de quem está logado>

{ "academia_id": "…", "nome": "Joana Pereira Lima",
  "email": "joana@exemplo.com", "telefone": "(41) 99876-5432",
  "papeis": ["aluno"] }
```

Devolve `{ ok, pessoa_id, nome, email, papeis, senha_provisoria }`.

### Como ela se protege

A chave de administração do Supabase é usada **exclusivamente para criar o
login**. Tudo mais acontece com o crachá de quem chamou, de propósito: assim
quem decide é a regra do banco, e não este código — se um dia a função tiver um
erro de lógica, as regras seguram atrás dela.

Na prática, a ordem é:

1. Descobre quem está chamando perguntando ao Supabase **com o crachá dele**.
2. Confere se essa pessoa tem `recepcao`, `gestor` ou `admin` **na academia
   pedida** — a consulta também vai com o crachá dele, então quem responde é a
   regra.
3. Só então cria o login, com a chave de administração.
4. Cria o vínculo **de novo com o crachá dele**, para a regra do banco valer.
5. Se o vínculo falhar, apaga o login recém-criado — não pode sobrar conta
   solta sem academia.

Dar papel diferente de `aluno` é do admin. Isso é conferido aqui **e** na regra
do banco; a checagem daqui existe só para devolver um erro claro em vez de um
"não deu".

### A chave secreta nunca aparece

`SUPABASE_SERVICE_ROLE_KEY` é injetada pelo Supabase como variável de ambiente
na hora que a função roda. Ela não está neste repositório, não passou por
ninguém e não precisa ser configurada.

**Nunca coloque essa chave no `index.html`.** Ela passa por cima de todas as
regras: quem a tiver lê e apaga tudo, de todas as academias.

## Testado

14 checagens contra o servidor de verdade, todas passando:

| O que | Resultado |
|---|---|
| Recepção cadastra aluno | cria e devolve senha |
| A pessoa entra com a senha provisória | entra |
| Nome e telefone chegam certos na ficha | `Joana Pereira Lima`, `41998765432` |
| Já dá para entrar pelo telefone | sim |
| **Aluno tenta cadastrar alguém** | 403 `sem_permissao` |
| **Recepção tenta criar um admin** | 403 `so_admin_da_papel` |
| **Cadastrar em academia alheia** | 403 `sem_permissao` |
| E-mail repetido | 409 `email_ja_usado` |
| Sem estar logado | 401 |

## Publicando uma alteração

A função foi enviada pelo conector do Supabase. Ao mudar o `index.ts`, mande a
versão nova — o Supabase guarda o histórico e troca sem interrupção.

## Senha provisória

Oito caracteres em dois blocos (`VRA6-ZCFZ`), sem `0`, `O`, `1`, `I` nem `l`,
porque ela vai ser escrita à mão num papel e digitada por outra pessoa.

Ainda **não existe** troca de senha no primeiro acesso. Enquanto não existir, a
senha provisória vira a senha definitiva — o que é aceitável para começar, mas
precisa ser resolvido antes de entrar academia de verdade.
