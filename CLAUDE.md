# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A WhatsApp-based scheduling system for hair salons ("Salão de Beleza"), **multi-tenant**: one
installation serves several empresas (salons), isolated by `empresa_id` + Postgres Row Level
Security. All business logic lives in n8n workflows; the data store is Supabase (Postgres);
WhatsApp messaging goes through a self-hosted Evolution API instance, one instance per empresa.
There is no build step anywhere in this repo — both frontends are single static `index.html`
files (Tailwind via CDN, vanilla JS), and the "backend" is JSON workflow definitions imported into
n8n's UI.

Docs (`docs/`) and code comments (including inside the n8n workflow JSON `Code` nodes) are in
Portuguese (pt-BR); this reflects the target user (a Brazilian salon owner), so keep new
docs/UI copy in Portuguese too.

Note: this project's git root is the parent `workpace` directory, which contains several
unrelated projects as siblings — treat `App_Agendamento/` as the project boundary regardless of
what else `git status` shows.

## Architecture

```
frontend-agenda/index.html (client booking app)   ─┐
frontend-admin/index.html (owner dashboard)        ├──HTTP──▶ n8n webhooks ──▶ Supabase/Postgres (data store)
                                                    │                     └──▶ Evolution API ──▶ WhatsApp
```

- **`frontend-agenda/index.html`** — client-facing booking flow: pick stylist → service → date →
  time → confirm via WhatsApp number. Calls n8n webhooks directly via `fetch`.
- **`frontend-admin/index.html`** — dashboard for the salon owner: day's appointments,
  cancel/finalize actions, plus a schedule-blocking panel (time off, full-day closures).
- **Evolution API** is the self-hosted WhatsApp gateway (Baileys protocol). n8n talks to it via
  HTTP for outbound sends; it forwards inbound messages to the `07-chatbot-whatsapp` webhook via
  `WEBHOOK_GLOBAL_URL`. Reference: `docs/evolution-api-setup.md`.
- **Caddy** reverse-proxies subdomains and serves the two frontend directories as static files
  with automatic HTTPS: `agenda.$DOMAIN` → `frontend-agenda/` (bare, non-wildcard block, predates
  the multi-tenant wildcard block below), `admin.$DOMAIN` → `frontend-admin/`, `n8n.$DOMAIN` → n8n
  container, `evolution.$DOMAIN` → Evolution API container. Routing rules: `Caddyfile`.
  - Multi-tenant `frontend-agenda` (Supabase track) is served by a 5th block,
    `*.agenda.$DOMAIN` — one deploy for every empresa, slug resolved from the subdomain (see
    `EMPRESA_SLUG` in `frontend-agenda/index.html`). Because it's a wildcard, its certificate
    needs the ACME **DNS-01** challenge (HTTP-01 can't prove control of a wildcard name), which
    requires: the zone for `$DOMAIN` hosted on **Cloudflare** (not Hostinger's own DNS — confirmed
    by testing that Hostinger rejects a DNS record with the wildcard in a non-leftmost position,
    e.g. `agenda.*.$DOMAIN`, which is why the slug comes *before* "agenda" in the hostname, not
    after); the Caddy image built from `Dockerfile.caddy` (stock `caddy:2-alpine` has no DNS
    provider modules) with the official `caddy-dns/cloudflare` module; and a `CLOUDFLARE_API_TOKEN`
    env var (Zone:DNS:Edit scope) consumed by the `tls { dns cloudflare ... }` block for that site
    in the `Caddyfile`.
- **`n8n-workflows-supabase/*.json`** — the entire application backend, 14 importable n8n workflow
  files (`00`-`13`), **multi-tenant**: several empresas (salons) share one installation, isolated
  by `empresa_id` + Postgres Row Level Security. Schema source of truth: `supabase/schema.sql`
  (also documents the `empresas`/`perfis` tables, the `empresa_atual()` helper, and the RLS
  policies). Every Supabase node in these files carries a placeholder credential
  (`PLACEHOLDER_SUPABASE_CREDENTIAL`) that must be reselected after import — see
  `docs/deploy-easypanel.md`. Design/decision history: `docs/plano-multi-tenant.md`.
  - `00-listar-servicos` (`/servicos`) — reads the empresa's `servicos` rows for the service
    catalog shown as cards in the client app.
  - `01-horarios-disponiveis` (`/horarios-disponiveis`) — computes available time slots for a
    given day + colaborador. The weekly opening-hours grid (`periodosPorDia`, keyed
    0=Domingo..6=Sábado, 30-minute slots) is hardcoded in this workflow's **Code** node, not in
    the database — see the comment at the top of that node before changing salon hours. Also
    reads `bloqueios` to exclude times the admin has blocked off for that colaborador.
  - `02-criar-agendamento` (`/criar-agendamento`) — creates a booking. Re-checks for schedule
    conflicts **at save time** against both existing `agendamentos` and `bloqueios` (not just when
    the grid was loaded, to avoid a race between two clients booking the same slot, or someone
    calling the API directly to bypass the UI), scoped by each service's real `duracao_minutos`,
    not just the exact start time.
  - `03-listar-agendamentos` (`/agendamentos`) — feeds the admin dashboard.
  - `04-cancelar-agendamento` / `05-finalizar-agendamento` — status transitions, each notifies
    the client over WhatsApp.
  - `06-lembrete-automatico` — cron-triggered (hourly), sends a WhatsApp reminder ~1h before an
    appointment; uses the `lembrete_enviado` boolean column as a dedup flag so it never
    double-sends.
  - `07-chatbot-whatsapp` (`/whatsapp-in`) — Evolution API webhook target for inbound WhatsApp
    messages; numbered-menu auto-replies (`1`/`AGENDAR`, `2`/`CANCELAR`, `3`/`STATUS`, anything
    else falls back to the menu message), ignores `fromMe: true` to avoid replying to itself.
  - `08-criar-bloqueio` / `09-listar-bloqueios` / `10-cancelar-bloqueio` (`/criar-bloqueio`,
    `/bloqueios`, `/cancelar-bloqueio`) — admin-only schedule blocking (folga/férias/consulta)
    per colaborador. A block with null `hora_inicio`/`hora_fim` closes the whole day; with both
    set, it closes only that time range. Cancelling flips `status` to `Cancelado` rather than
    deleting the row (same soft-delete pattern as `agendamentos`).
  - Public/anonymous workflows (`00`, `01`, `02`, and the public half of `11`) resolve the empresa
    from a `slug` **query param** on GET requests or a `slug` **body field** on the POST
    (`criar-agendamento`) — not a `:slug` path segment. n8n's `:param` dynamic webhook path only
    matches when the first path segment equals the node's own internal `webhookId` (it's built for
    resuming a specific execution's wait-webhook, not general request routing), so it can't carry
    an arbitrary business value like a tenant slug — confirmed by testing against a local n8n
    instance. These workflows keep using the `service_role` Supabase credential (no logged-in user
    to scope by) — every query is filtered by the resolved `empresa_id` explicitly.
  - Admin workflows (`03`-`05`, `08`-`10`, `12`, `13`, and the admin half of `11`) require a Supabase
    Auth JWT forwarded from `frontend-admin` (`Authorization: Bearer <token>`). Their first node
    verifies the token against `${SUPABASE_URL}/auth/v1/user`; the Supabase reads/writes then go
    through **HTTP Request** nodes calling PostgREST directly with the `anon` key + that forwarded
    JWT (not `service_role`), so Postgres enforces `empresa_id = empresa_atual()` via RLS — the
    app-level filtering is defense in depth, not the only thing preventing cross-tenant access.
  - `12-servicos-admin` is the service-catalog CRUD the admin dashboard's "Serviços" tab talks to:
    `GET /servicos-admin` (list own catalog, including inactive), `POST /criar-servico`,
    `POST /atualizar-servico` (full-row update — nome/preco/duracao_minutos/ativo together, no
    partial-patch semantics). Before this workflow existed, adding a service meant hand-editing
    the `servicos` table in Supabase's Table Editor — not viable once salons self-serve.
  - Multi-tenant means one Evolution API deployment hosts **one WhatsApp instance per empresa**
    (`empresas.evolution_instance`, set to the slug at signup — see `handle_new_user()` in
    `supabase/schema.sql`), not a single global instance. Every outbound send in `02`, `04`, `05`
    looks up the sending empresa's row first
    and targets `.../message/sendText/<evolution_instance>` (and uses that empresa's `nome` /
    `whatsapp_admin` in the message text) instead of the old env vars; `$env.SALON_NAME` /
    `$env.SALON_ADMIN_WHATSAPP` only survive as fallbacks where an empresa can't be resolved.
  - `13-conectar-whatsapp-supabase` (`/whatsapp-status` GET, `/whatsapp-conectar` POST) is what
    lets an empresa pair its own WhatsApp instance from the admin dashboard instead of an operator
    running `curl` against the Evolution API by hand: `/whatsapp-status` reports
    `nao_criada`/`conectando`/`conectado` via `GET /instance/connectionState/<slug>`;
    `/whatsapp-conectar` creates the instance if it doesn't exist yet (`POST /instance/create`,
    `qrcode: true`) or reconnects it if it exists but isn't `open` (`GET /instance/connect/<slug>`),
    and returns the QR code as base64 for `frontend-admin` to render and poll against. Both
    Evolution API response shapes (`qrcode.base64` from `/instance/create` vs. a root-level
    `base64`/`qr` from `/instance/connect`) are normalized in one Code node since the two endpoints
    don't agree on field naming.
  - `06-lembrete-automatico` and `07-chatbot-whatsapp` have no per-request user or slug (cron /
    inbound WhatsApp), so they resolve the empresa from data instead: `06` joins each pending
    reminder against `empresas` to find the right `evolution_instance`; `07` reads the `instance`
    field the Evolution API includes in every inbound event.
  - `14-hotmart-webhook-supabase` (`/hotmart-webhook` POST) is the Hotmart postback target for the
    app_agendamento product being sold on Hotmart. The empresa still self-provisions the normal way
    (signs up on `frontend-admin`, which already sends a Supabase Auth confirmation e-mail) — this
    workflow does **not** create accounts. It only reacts to Hotmart's own purchase lifecycle:
    validates the `X-Hotmart-Hottok` header/`hottok` body field against `$env.HOTMART_HOTTOK`
    (whichever one the buyer's Hotmart account actually sends — not yet confirmed by a real test
    send, see the Code node's comment) and the product against `$env.HOTMART_PRODUCT_ID`, then on
    `PURCHASE_CANCELED`/`PURCHASE_REFUNDED`/`PURCHASE_CHARGEBACK` looks up `empresas` by
    `email` (matched against the buyer's Hotmart e-mail) and sets `ativo = false`; on
    `PURCHASE_APPROVED`/`PURCHASE_COMPLETE` it sets `ativo = true` back (re-subscribe case). If no
    empresa exists yet for that e-mail (buyer hasn't signed up), it's a no-op — new signups already
    default to `ativo = true`. `empresas.email` is populated automatically by `handle_new_user()`
    from `auth.users.email` (no new signup field) specifically so this workflow can do that lookup.
    `ativo = false` is enforced in two places: `frontend-admin` shows a "assinatura inativa" screen
    instead of the dashboard after login (via the `ativo` field `11-empresa-info-supabase` now
    returns), and `00`/`01`/`02`/`11`'s public halves already refused to resolve an inactive
    empresa by slug (`ativo = true` was already one of their filter conditions) — so this closes
    the enforcement gap only on the admin-dashboard side.
  - Needs `SUPABASE_URL` and `SUPABASE_ANON_KEY` as n8n env vars (read via `$env.*` in the
    admin/auth workflows above; `service_role` stays a credential, not an env var). `14` also needs
    `HOTMART_HOTTOK` and `HOTMART_PRODUCT_ID`. See `easypanel/docker-compose.easypanel.yml`.
  - **Gotcha confirmed by testing**: the native `n8n-nodes-base.supabase` node's `getAll`
    operation combines multiple `filters.conditions` with **OR** by default (its `matchType`
    parameter defaults to `anyFilter`) — not AND. Any Supabase node filtering on more than one
    column (e.g. `slug` + `ativo`) must explicitly set `"matchType": "allFilters"` in its
    `parameters`, or it silently matches rows that satisfy only one condition (a real cross-tenant
    leak risk here, since these are exactly the `service_role` nodes resolving `empresa` by slug).
    The HTTP Request nodes used in the admin/RLS workflows are unaffected (plain PostgREST query
    params AND by default).
  - **Gotcha confirmed by testing**: the native `n8n-nodes-base.supabase` node's `tableId`
    parameter must be written as a resource-locator object —
    `{ "__rl": true, "value": "empresas", "mode": "id" }` — not a plain string. A plain string
    (`"tableId": "empresas"`) imports and saves without error, but this n8n version's editor can't
    resolve/display it, shows "Error fetching options from Supabase" on the field, and — more
    importantly — refuses to **Publish** the workflow ("1 node has issues") until every affected
    node is fixed. Affects only the `service_role` workflows that use the native node directly
    (`00`, `01`, `02`, `06`, `07`, `14`, and the public half of `11`); the admin/RLS workflows are
    unaffected since they call PostgREST via **HTTP Request** nodes instead.

### Frontend ↔ backend wiring

Both `index.html` files set `N8N_BASE_URL` at the top of an inline `<script>` block, with
auto-detection of local vs. production based on `IS_LOCAL = location.protocol === "file:" ||
["localhost", "127.0.0.1"].includes(location.hostname)`.

- **`frontend-agenda/index.html`** additionally hardcodes `EMPRESA_SLUG`, sent as `?slug=...` on
  every GET webhook call and as a `slug` field in the POST body for `criar-agendamento` (matches
  the query/body resolution described above — deliberately not a path segment). One slug per
  deployed copy of this file — see the per-empresa deploy note in `docs/deploy-easypanel.md`
  step 8.
- **`frontend-admin/index.html`** loads `supabase-js` from a CDN and hardcodes `SUPABASE_URL` +
  `SUPABASE_ANON_KEY` (the public anon key — safe to expose, same trust level as `N8N_BASE_URL`).
  It gates the dashboard behind Supabase Auth: an `authOverlay` login/signup UI shown until
  `supabase.auth.getSession()`/`onAuthStateChange` reports a session, and every admin webhook
  call goes through `fetchAutenticado()`, which attaches `Authorization: Bearer <access_token>`.
  Signup (`supabase.auth.signUp` with `options.data = { slug, nome_empresa, whatsapp_admin,
  colaboradores }`) is what actually provisions a new empresa, via the `handle_new_user` trigger
  in `supabase/schema.sql` — there is no separate n8n signup endpoint. The dashboard's "Serviços"
  card (list + inline edit/toggle + add form) talks to workflow `12` — this is how an empresa
  manages its own catalog; there's no other UI for it. The "WhatsApp" card talks to workflow `13`:
  polls `/whatsapp-status` on load to show a badge (não conectado/conectando/conectado), and its
  "Conectar WhatsApp" button calls `/whatsapp-conectar`, renders the returned QR code, and polls
  status every 4s for up to 2 minutes waiting for a scan (then tells the user the QR expired).

Neither file hardcodes collaborator names (`COLABORADORES`) or the empresa name anymore — both
call `GET .../empresa-info` after resolving the empresa (by slug for `frontend-agenda`, by JWT for
`frontend-admin`, see workflow `11`) and populate those from the response. Scheduling *is* split
per-collaborator: `01`, `02`, `08`, `09` and `10` all scope their reads/writes to
`Colaborador === <chosen collaborator>` (plus `empresa_id`), so two clients can book the same time
slot as long as they pick different collaborators, and a block on one collaborator doesn't affect
another's availability.

## Running locally

No package manager, no build. Local dev spins up the whole stack via Docker Compose. There is no
`.env.example` committed in this directory — create `.env` directly (see the variables
referenced in `docker-compose.yml`: `DOMAIN`, `N8N_ENCRYPTION_KEY`, `N8N_BASIC_AUTH_USER/PASSWORD`,
`TIMEZONE`, `N8N_DB_PASSWORD`, `GOOGLE_SHEET_ID`, `EVOLUTION_API_KEY`, `EVOLUTION_INSTANCE`,
`EVOLUTION_DB_PASSWORD`, `SALON_ADMIN_WHATSAPP`, `SALON_NAME`, `CLOUDFLARE_API_TOKEN`), then:

```bash
docker compose up -d
```

`docker-compose.override.yml` is auto-applied by `docker compose` in this environment only (not
on the production VPS) and adds two `nginx:alpine` containers serving the frontends directly on
`localhost:8081` (client) / `localhost:8082` (admin), plus exposes n8n on `:5678` and Evolution
API on `:8080` without needing Caddy/HTTPS. With `IS_LOCAL` detection in the frontends, opening
`index.html` directly (`file://`) or via `localhost`/`127.0.0.1` automatically points
`N8N_BASE_URL` at `http://127.0.0.1:5678/webhook`.

There are no automated tests, linters, or build/CI commands in this repo. "Testing" a change
means: import/re-import the affected workflow JSON into a running n8n, activate it, and exercise
it end-to-end (client app → row appears in Supabase → WhatsApp message received → admin panel
reflects it).

## Editing n8n workflows

The `n8n-workflows-supabase/*.json` files are full n8n workflow exports (nodes + connections +
settings). When changing logic that lives in these workflows:
- Prefer editing the JSON directly for structural/logic changes (node parameters, `Code` node
  bodies), since there's no other source of truth — the JSON *is* the workflow.
- Every Supabase node carries a placeholder credential (`PLACEHOLDER_SUPABASE_CREDENTIAL`) that
  only resolves to a real credential inside a given n8n instance after being reselected post-import
  — don't invent or change credential IDs; see `docs/deploy-easypanel.md`.
- Watch for the two Supabase-node gotchas documented above (`matchType: allFilters` for
  multi-condition filters, and the `tableId` resource-locator object shape) when touching a
  `service_role` workflow's native Supabase node.
- Keep using `$env.*` for anything environment-specific (Evolution API URL/key, instance name,
  salon phone/name, `SUPABASE_URL`/`SUPABASE_ANON_KEY`) rather than hardcoding — see
  `docker-compose.yml` / `easypanel/docker-compose.easypanel.yml` for the full list of env vars
  injected into the n8n container.
- After editing, the change must be re-imported into n8n (Import from File) to take effect; there
  is no way to "run" these JSON files outside of n8n.

## Production deployment target

**Easypanel, self-hosted on the user's own Hostinger KVM 2 VPS** (not Easypanel Cloud) — this is
the actual, currently-running production deployment. Easypanel manages two projects behind
Traefik: `app_agendamento` (the `frontend_admin` and `frontend_agenda` static apps, built from
their respective `Dockerfile`s) and `projeto-n8n` (n8n + Evolution API, each with its own
Postgres/Redis). Full step-by-step: `docs/deploy-easypanel.md`. Supporting files:
`frontend-admin/Dockerfile`, `frontend-agenda/Dockerfile`, and `easypanel/` (a trimmed
`docker-compose.easypanel.yml` and an `app_agendamento.env.example`). Never commit a real
`.env`/`app_agendamento.env` — they're git-ignored, and only ever belong on the VPS.

**Legacy, not currently deployed**: the repo's root `docker-compose.yml` + `Caddyfile` (+
`Dockerfile.caddy`) describe a manual, non-Easypanel way to run the same n8n + Evolution API +
Caddy stack directly on a VPS via `docker compose up -d`, with DNS A records for `n8n.`,
`evolution.`, `agenda.`, `admin.` subdomains of `$DOMAIN` plus the wildcard `*.agenda.$DOMAIN`
(see the Caddy wildcard note above) — that record's zone must be hosted on Cloudflare, not
Hostinger's own DNS. Confirmed by SSHing into the production VPS (2026-09-14) that this manual
stack is **not** currently running — only Easypanel/Traefik-managed containers are up. There is
no dedicated step-by-step doc for this path. Treat it as an unmaintained fallback, not something
to assume is live.
