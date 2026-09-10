# Deploy no Easypanel + Supabase

> Este é um caminho de deploy **alternativo** ao de `deploy-vps-hostinger.md` — não substitui o
> original, que continua funcionando normalmente com Google Sheets numa VPS com Docker Compose +
> Caddy. Use este guia se você quer hospedar no [Easypanel](https://easypanel.io) e trocar o
> "banco de dados" de Google Sheets para Supabase (Postgres).
>
> Não tenho acesso a uma instância real do Easypanel para validar os nomes exatos de cada tela —
> os passos abaixo seguem o modelo padrão do Easypanel (serviços "App" a partir de imagem Docker
> ou repositório Git, serviço "Compose" para um `docker-compose.yml`, templates prontos de
> Postgres/Redis, domínio + HTTPS automático por serviço). Confira contra a versão instalada e
> ajuste nomes de tela conforme necessário.

Arquitetura:

```
Internet
  │
  ├── agenda.SEUDOMINIO  → Easypanel (App "frontend_agenda") → frontend-agenda/ (Dockerfile)
  ├── admin.SEUDOMINIO   → Easypanel (App "frontend_admin")  → frontend-admin/  (Dockerfile)
  ├── n8n.SEUDOMINIO     → Easypanel → container n8n (automações)
  └── evolution.SEUDOMINIO → Easypanel → container Evolution API (WhatsApp)
                                              │
                                              ▼
                                   Supabase Cloud (Postgres + REST API)
```

Diferença chave em relação ao caminho da Hostinger: o Easypanel faz proxy reverso + HTTPS
automático por serviço (não usa o `Caddyfile` deste repo), e o "banco de dados" passa a ser um
projeto Supabase hospedado na nuvem do próprio Supabase — não dentro do Easypanel. Os nomes
`frontend_admin`/`frontend_agenda` abaixo são os nomes dos *serviços* no Easypanel, e batem 1:1
com as pastas do repositório: `frontend-admin/` e `frontend-agenda/`.

## 1. Criar o projeto Supabase

Este é um deploy **multi-tenant**: uma instalação atende várias empresas (salões), cada uma
isolada por Row Level Security. Não existe mais um catálogo/agenda "da empresa" fixo — cada empresa
se cadastra pelo próprio painel admin (ver passo 8.1) e o Postgres separa os dados
automaticamente por `empresa_id`.

1. Crie uma conta/projeto em [supabase.com](https://supabase.com) (região mais próxima do
   público dos salões).
2. Abra **SQL Editor → New query**, cole o conteúdo de `supabase/schema.sql` deste repositório e
   rode. Isso cria as tabelas `empresas`, `perfis`, `servicos`, `agendamentos`, `bloqueios`, a
   função `empresa_atual()`, o trigger que provisiona `empresas`+`perfis` automaticamente no
   cadastro de uma empresa (`handle_new_user`), e as policies de RLS que isolam cada empresa —
   ver os comentários no topo do arquivo para o racional completo.
3. Em **Authentication → Providers**, confirme que **Email** está habilitado (é o método usado
   pelo cadastro/login do painel admin). Se preferir pular a confirmação de e-mail por
   simplicidade em teste, desative "Confirm email" em **Authentication → Settings**.
4. Em **Project Settings → API**, anote a **Project URL**, a chave **anon/public** e a chave
   **service_role** — vai precisar das três nos passos 5 e 8 abaixo. Não precisa cadastrar
   catálogo nenhum aqui manualmente: cada dono de empresa cadastra os próprios serviços depois,
   pelo painel admin (aba "Serviços" — criar, editar preço/duração e ativar/desativar), via o
   workflow `12-servicos-admin-supabase`.

## 2. Criar o projeto "app_agendamento" no Easypanel

Crie um novo projeto chamado `app_agendamento`. Para o backend (n8n + Evolution API), escolha uma
das duas opções:

**Opção A — serviços individuais (recomendada)**: crie um serviço "App" a partir da imagem
`docker.n8n.io/n8nio/n8n:1.123.25` para o n8n, um serviço de banco usando o template de
**Postgres** do Easypanel para `n8n-db`, um serviço "App" a partir da imagem
`evoapicloud/evolution-api:latest` para o Evolution API, e templates de **Postgres** e **Redis**
para `evolution-db`/`evolution-redis`. Configure as variáveis de ambiente de cada serviço
conforme `easypanel/app_agendamento.env.example` e o `docker-compose.yml` original (mesmos nomes,
menos `GOOGLE_SHEET_ID`).

**Opção B — um serviço Compose (mais rápida)**: crie um serviço do tipo **Compose**, cole o
conteúdo de `easypanel/docker-compose.easypanel.yml`, preencha as variáveis de ambiente do
serviço (mesma lista do `.env.example` acima) e publique. Configure domínio/porta por
sub-serviço na tela de domínios do Easypanel (as portas internas de cada serviço estão anotadas
como comentário `# porta:` no próprio arquivo compose).

## 3. Criar os serviços estáticos `frontend_admin` e `frontend_agenda`

Para cada frontend, crie um serviço **App** apontando para este repositório Git, com:
- Método de build: **Dockerfile**.
- Caminho de build: `frontend-admin/` (serviço `frontend_admin`) ou `frontend-agenda/` (serviço
  `frontend_agenda`) — os `Dockerfile`s já existem em cada pasta (`FROM nginx:alpine` +
  `COPY . /usr/share/nginx/html`, mesmo padrão já usado no nginx local de
  `docker-compose.override.yml`).
- Porta interna: `80`.

## 4. Apontar os domínios

Na tela de domínio de cada serviço, configure (Easypanel emite HTTPS automaticamente, sem precisar
mexer no `Caddyfile` deste repo — ele não é usado neste caminho):

| Serviço | Domínio |
|---|---|
| n8n | `n8n.SEUDOMINIO` |
| evolution-api | `evolution.SEUDOMINIO` |
| frontend_agenda | `agenda.SEUDOMINIO` |
| frontend_admin | `admin.SEUDOMINIO` |

## 5. Criar a credencial Supabase no n8n e configurar `$env.*`

1. No n8n, vá em **Credentials → New → Supabase API** e cole a **Project URL** e a chave
   **service_role** anotadas no passo 1.4. Essa credencial continua usada pelos workflows
   públicos/cron/chatbot (`00`, `01`, `02`, `06`, `07`, e a metade pública do `11`), que rodam
   sem usuário logado.
2. Nas variáveis de ambiente do serviço n8n (mesma tela onde já estão `EVOLUTION_API_KEY`,
   `SALON_NAME` etc.), adicione `SUPABASE_URL` (a Project URL, sem sufixo `/rest/v1/`) e
   `SUPABASE_ANON_KEY` (a chave anon/public do passo 1.4). Essas duas **são** lidas por
   `$env.*` dentro dos workflows admin (`03`, `04`, `05`, `08`, `09`, `10`, e a metade admin do
   `11`) — usadas para verificar o JWT de quem está logado no painel e falar com o PostgREST em
   nome dele, fazendo o RLS valer de verdade (ver `docs/plano-multi-tenant.md` e os comentários em
   `supabase/schema.sql`).

## 6. Importar os workflows Supabase

Na pasta `n8n-workflows-supabase/` (não confundir com `n8n-workflows/`, que é a versão Google
Sheets original, single-tenant, e continua intocada), importe cada arquivo `.json` em
**n8n → Workflows → Import from File**, na ordem numérica (agora 13 arquivos, `00` a `12`).
Depois de importar cada um:

1. Abra todo nó **Supabase** do workflow — como o `.json` traz um `id` de credencial placeholder
   (`PLACEHOLDER_SUPABASE_CREDENTIAL`) que não existe na sua instância, o n8n mostra o nó com a
   credencial não vinculada (comportamento normal de import, não é erro). Reselecione a
   credencial "Supabase account" criada no passo 5.1 em cada um. Os nós **HTTP Request** que
   falam com `$env.SUPABASE_URL` (inclusive os nós "Autenticar") não usam credencial do n8n —
   dependem só das variáveis de ambiente do passo 5.2 estarem configuradas.
2. Ative o workflow (toggle "Active").
3. Confira a URL do webhook gerada — os caminhos em si não mudaram (`/servicos`,
   `/horarios-disponiveis`, `/criar-agendamento`, `/empresa-info-publico`); os públicos passam a
   exigir o slug da empresa como **query param** (`?slug=...`) nos GET ou campo `slug` no body do
   POST `criar-agendamento` — **não** como segmento do path. (O mecanismo `:param` de path
   dinâmico do n8n não serve pra isso: o primeiro segmento precisa bater com o `webhookId` interno
   do nó, é pensado para webhooks de espera de execução, não para roteamento de negócio — por
   isso o slug vai por query/body em vez de path.) Os caminhos do painel admin não mudaram:
   `/agendamentos`, `/cancelar-agendamento`, `/finalizar-agendamento`, `/criar-bloqueio`,
   `/bloqueios`, `/cancelar-bloqueio`, `/empresa-info` (sem slug — a empresa é resolvida pelo
   usuário logado). `/whatsapp-in` também não muda (a empresa é resolvida pela instância Evolution
   que recebeu a mensagem). O workflow `12` adiciona três caminhos novos, também sem slug (RLS
   resolve a empresa): `/servicos-admin` (GET, lista o catálogo completo inclusive inativos),
   `/criar-servico` e `/atualizar-servico` (POST) — é o que a aba "Serviços" do `frontend-admin`
   usa.

As demais configurações (número do WhatsApp, chave da Evolution API) continuam vindo prontas via
`$env.*` — mesmos nomes de hoje, menos `GOOGLE_SHEET_ID` (não existe mais nesta versão) e menos
`SALON_NAME`/`SALON_ADMIN_WHATSAPP` fixos (cada empresa tem os seus próprios, cadastrados no
signup — os `$env.SALON_NAME`/`SALON_ADMIN_WHATSAPP` só sobrevivem como fallback nos poucos
lugares que não conseguem resolver a empresa, ex.: mensagem de erro genérica).

## 7. Conectar o WhatsApp (Evolution API) — uma instância por empresa

Diferente do caminho single-tenant, aqui cada empresa precisa da própria instância Evolution
(próprio número de WhatsApp, próprio QR Code) — a Evolution API já suporta várias instâncias no
mesmo container, então isso não exige um novo serviço, só uma instância nova por empresa. Para
cada empresa cadastrada (passo 8.1):

1. Crie a instância via `POST /instance/create` com `instanceName` **igual ao slug** da empresa
   (é o valor que `handle_new_user()` grava em `empresas.evolution_instance` — ver
   `supabase/schema.sql`), escaneie o QR Code e confirme com
   `GET /instance/connectionState/<slug>`. Mesmo procedimento detalhado em
   `docs/evolution-api-setup.md` e na seção 5 de `deploy-vps-hostinger.md`, só trocando a URL
   base para `https://evolution.SEUDOMINIO`.
2. O `WEBHOOK_GLOBAL_URL` já aponta pro mesmo endpoint `/webhook/whatsapp-in` do n8n pra todas as
   instâncias (configurado uma vez no serviço Evolution API, não por instância) — o workflow `07`
   descobre sozinho qual empresa é, pelo campo `instance` que a Evolution manda em cada evento.

## 8. Cadastrar as empresas e apontar os frontends

### 8.1 Cadastro self-service (painel admin)

Não há mais uma "empresa fixa" pré-configurada: cada dono de empresa se cadastra pelo próprio
`frontend-admin` (tela "Cadastrar empresa" — nome, slug, WhatsApp, e-mail, senha). O cadastro já
cria a empresa e o perfil automaticamente (trigger `handle_new_user`, passo 1.2). Depois de
cadastrada, use o **slug** escolhido para: nomear a instância Evolution (passo 7), configurar o
domínio do `frontend_agenda` dessa empresa (abaixo), e como valor de `EMPRESA_SLUG` no
`frontend-agenda/index.html` dela.

### 8.2 Apontar os frontends para o n8n/Supabase

`frontend-admin/index.html` é compartilhado por todas as empresas (login resolve a empresa pelo
usuário) — edite o topo uma única vez:

```js
const N8N_BASE_URL = "https://n8n.SEUDOMINIO/webhook";
const SUPABASE_URL = "https://SEU-PROJETO.supabase.co";
const SUPABASE_ANON_KEY = "...";
```

`frontend-agenda/index.html` é por empresa (cada uma precisa da própria cópia com o próprio
slug) — para cada empresa cadastrada, gere um novo deploy do serviço `frontend_agenda` (ou um
serviço por empresa) com:

```js
const N8N_BASE_URL = "https://n8n.SEUDOMINIO/webhook";
const EMPRESA_SLUG = "slug-da-empresa";
```

e aponte um domínio próprio pra esse deploy (ex.: `agenda-slug-da-empresa.SEUDOMINIO`, ou um
subdomínio por empresa se preferir DNS wildcard — é o valor que o chatbot do WhatsApp (`07`) usa
para montar o link que manda pro cliente). Como cada frontend é rebuildado a partir do próprio
repositório (Dockerfile), um novo deploy do serviço no Easypanel após o commit já reflete a
mudança.

## 9. Testar de ponta a ponta

1. Abra `https://admin.SEUDOMINIO`, cadastre uma empresa de teste (aba "Cadastrar empresa") e
   confirme que o dashboard carrega vazio depois do login.
2. No Supabase, confira **Table Editor → empresas** e **perfis** e veja se as linhas foram
   criadas pelo trigger. No painel admin, aba "Serviços", cadastre 1-2 serviços de teste.
3. Abra a URL do `frontend-agenda` dessa empresa (passo 8.2), escolha um serviço, colaborador,
   data e horário, confirme com um WhatsApp válido (o seu, para teste) e crie o agendamento.
4. No Supabase, confira **Table Editor → agendamentos** e veja se a linha apareceu com o
   `empresa_id` certo.
5. Verifique se você recebeu a mensagem de confirmação no WhatsApp e se o `whatsapp_admin` da
   empresa recebeu a notificação de novo agendamento.
6. No painel admin, confirme que o agendamento aparece na lista do dia, teste os botões
   "Cancelar" e "Finalizado".
7. Crie um bloqueio de agenda (folga/dia inteiro) pelo painel admin e confirme que o horário some
   da lista de horários disponíveis no app do cliente; cancele o bloqueio e confirme que o
   horário volta a aparecer.
8. **Teste de isolamento (o motivo de existir RLS)**: cadastre uma segunda empresa, logue com
   essa conta e confirme que ela **não** vê os agendamentos/bloqueios/serviços da primeira —
   nem que reaproveite o mesmo `frontend-admin`. Tente também bater direto no PostgREST com a
   `anon key` sem nenhum `Authorization` (`curl` na URL `SUPABASE_URL/rest/v1/agendamentos` com
   header `apikey: <anon key>`) e confirme que volta vazio/erro, não os dados de ninguém.
9. Para testar o lembrete automático, crie um agendamento para o dia seguinte e aguarde o horário
   configurado no workflow `06-lembrete-automatico-supabase` (por padrão, roda 1x por hora).

## Manutenção / diferenças em relação ao guia da Hostinger

- Não há Caddy nem `Caddyfile` neste caminho — domínio e HTTPS são geridos por serviço direto na
  UI do Easypanel.
- Backup do "banco de dados" agora é feito pelo próprio Supabase (backups automáticos do plano
  contratado, ou `pg_dump` manual via **Database → Backups**/connection string), em vez de copiar
  a planilha do Google.
- Atualizar imagens: redeploy de cada serviço "App" (n8n, Evolution API) pela UI do Easypanel, ou
  reaplicar o `docker-compose.easypanel.yml` no serviço Compose se você usou a Opção B do passo 2.
- Os workflows de `n8n-workflows/` (Google Sheets) continuam existindo neste repositório como
  modelo/referência — não são usados neste caminho de deploy.
