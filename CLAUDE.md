# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A WhatsApp-based scheduling system for a hair salon ("Salão de Beleza"), built with **no
traditional backend or database**. All business logic lives in n8n workflows; the data store is a
Google Sheet; WhatsApp messaging goes through a self-hosted Evolution API instance. There is no
build step anywhere in this repo — both frontends are single static `index.html` files (Tailwind
via CDN, vanilla JS), and the "backend" is JSON workflow definitions imported into n8n's UI.

Docs (`docs/`) and code comments (including inside the n8n workflow JSON `Code` nodes) are in
Portuguese (pt-BR); this reflects the target user (a Brazilian salon owner), so keep new
docs/UI copy in Portuguese too.

Note: this project's git root is the parent `workpace` directory, which contains several
unrelated projects as siblings — treat `App_Agendamento/` as the project boundary regardless of
what else `git status` shows.

## Architecture

```
frontend-agenda/index.html (client booking app)   ─┐
frontend-admin/index.html (owner dashboard)        ├──HTTP──▶ n8n webhooks ──▶ Google Sheets (data store)
                                                    │                     └──▶ Evolution API ──▶ WhatsApp
```

- **`frontend-agenda/index.html`** — client-facing booking flow: pick stylist → service → date →
  time → confirm via WhatsApp number. Calls n8n webhooks directly via `fetch`.
- **`frontend-admin/index.html`** — dashboard for the salon owner: day's appointments,
  cancel/finalize actions, plus a schedule-blocking panel (time off, full-day closures).
- **`n8n-workflows/*.json`** — the entire application backend, as importable n8n workflow files,
  numbered in the order they should be imported:
  - `00-listar-servicos` (`/servicos`) — reads the `Servicos` sheet tab for the service catalog
    shown as cards in the client app.
  - `01-horarios-disponiveis` (`/horarios-disponiveis`) — computes available time slots for a
    given day + stylist. The weekly opening-hours grid (`gradePorDia`, keyed 0=Sunday..6=Saturday)
    is hardcoded in this workflow's **Code** node, not in the sheet — see the comment at the top
    of that node before changing salon hours. Also reads the `Bloqueios` sheet tab to exclude
    times the admin has blocked off for that stylist.
  - `02-criar-agendamento` (`/criar-agendamento`) — creates a booking. Re-checks for schedule
    conflicts **at save time** against both existing bookings and `Bloqueios` (not just when the
    grid was loaded, to avoid a race between two clients booking the same slot, or someone
    calling the API directly to bypass the UI), scoped by each service's real `DuracaoMinutos`
    (duration), not just the exact start time.
  - `03-listar-agendamentos` (`/agendamentos`) — feeds the admin dashboard.
  - `04-cancelar-agendamento` / `05-finalizar-agendamento` — status transitions, each notifies
    the client over WhatsApp.
  - `06-lembrete-automatico` — cron-triggered (hourly), sends a WhatsApp reminder 24h before an
    appointment; uses the `LembreteEnviado` column as a dedup flag so it never double-sends.
  - `07-chatbot-whatsapp` (`/whatsapp-in`) — Evolution API webhook target for inbound WhatsApp
    messages; keyword-based auto-replies (`AGENDAR`, `CANCELAR`, `STATUS`, `AJUDA`), ignores
    `fromMe: true` to avoid replying to itself.
  - `08-criar-bloqueio` / `09-listar-bloqueios` / `10-cancelar-bloqueio` (`/criar-bloqueio`,
    `/bloqueios`, `/cancelar-bloqueio`) — admin-only schedule blocking (folga/férias/consulta)
    per stylist. A block with empty `HoraInicio`/`HoraFim` closes the whole day; with both set,
    it closes only that time range. Cancelling flips `Status` to `Cancelado` rather than deleting
    the row (same soft-delete pattern as `Agendamentos`).
  - All workflows read config (sheet ID, Evolution API key/instance, salon phone/name) from n8n
    environment variables (`$env.*`, injected via `docker-compose.yml` from `.env`) — no
    per-node hardcoding.
  - Every outbound WhatsApp send is isolated in its own **HTTP Request** node per workflow, so
    swapping providers (e.g. to Meta's official WhatsApp Cloud API) only means editing those
    nodes, not the booking logic.
- **Google Sheets is the database.** One spreadsheet, three tabs: `Agendamentos` (bookings),
  `Servicos` (service catalog), `Bloqueios` (schedule blocks). Exact column layout, including
  which sheet `gid` each workflow's Google Sheets node is hardwired to, is documented in
  `docs/google-sheets-schema.md` — read that before adding/reordering columns or duplicating the
  spreadsheet, since a `sheetName` mismatch fails with `Sheet with ID <name> not found`. Editing
  the `Servicos` tab (add row / toggle `Ativo`) is how you add or hide a service — no code
  change needed.
- **Evolution API** is the self-hosted WhatsApp gateway (Baileys protocol). n8n talks to it via
  HTTP for outbound sends; it forwards inbound messages to the `07-chatbot-whatsapp` webhook via
  `WEBHOOK_GLOBAL_URL`. Reference: `docs/evolution-api-setup.md`.
- **Caddy** reverse-proxies 4 subdomains and serves the two frontend directories as static files
  with automatic HTTPS: `agenda.$DOMAIN` → `frontend-agenda/`, `admin.$DOMAIN` →
  `frontend-admin/`, `n8n.$DOMAIN` → n8n container, `evolution.$DOMAIN` → Evolution API
  container. Routing rules: `Caddyfile`.
- **`n8n-workflows-supabase/*.json`** — a parallel set of workflows (`00`-`12`, 13 files), modeled
  on `n8n-workflows/` but reading/writing a Supabase Postgres database instead of Google Sheets,
  and **multi-tenant**: several empresas (salons) share one installation, isolated by
  `empresa_id` + Postgres Row Level Security. Schema source of truth: `supabase/schema.sql` (also
  documents the `empresas`/`perfis` tables, the `empresa_atual()` helper, and the RLS policies).
  Every Supabase node in these files carries a placeholder credential
  (`PLACEHOLDER_SUPABASE_CREDENTIAL`) that must be reselected after import — see
  `docs/deploy-easypanel.md`. Design/decision history: `docs/plano-multi-tenant.md`.
  - Public/anonymous workflows (`00`, `01`, `02`, and the public half of `11`) resolve the empresa
    from a `slug` **query param** on GET requests or a `slug` **body field** on the POST
    (`criar-agendamento`) — not a `:slug` path segment. n8n's `:param` dynamic webhook path only
    matches when the first path segment equals the node's own internal `webhookId` (it's built for
    resuming a specific execution's wait-webhook, not general request routing), so it can't carry
    an arbitrary business value like a tenant slug — confirmed by testing against a local n8n
    instance. These workflows keep using the `service_role` Supabase credential (no logged-in user
    to scope by) — every query is filtered by the resolved `empresa_id` explicitly.
  - Admin workflows (`03`-`05`, `08`-`10`, `12`, and the admin half of `11`) require a Supabase
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
  - `06-lembrete-automatico` and `07-chatbot-whatsapp` have no per-request user or slug (cron /
    inbound WhatsApp), so they resolve the empresa from data instead: `06` joins each pending
    reminder against `empresas` to find the right `evolution_instance`; `07` reads the `instance`
    field the Evolution API includes in every inbound event.
  - Needs two extra n8n env vars beyond the Google Sheets set: `SUPABASE_URL` and
    `SUPABASE_ANON_KEY` (read via `$env.*` in the admin/auth workflows above; `service_role` stays
    a credential, not an env var). See `easypanel/docker-compose.easypanel.yml`.
  - **Gotcha confirmed by testing**: the native `n8n-nodes-base.supabase` node's `getAll`
    operation combines multiple `filters.conditions` with **OR** by default (its `matchType`
    parameter defaults to `anyFilter`) — not AND. Any Supabase node filtering on more than one
    column (e.g. `slug` + `ativo`) must explicitly set `"matchType": "allFilters"` in its
    `parameters`, or it silently matches rows that satisfy only one condition (a real cross-tenant
    leak risk here, since these are exactly the `service_role` nodes resolving `empresa` by slug).
    The HTTP Request nodes used in the admin/RLS workflows are unaffected (plain PostgREST query
    params AND by default).

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
  cabeleireiros }`) is what actually provisions a new empresa, via the `handle_new_user` trigger
  in `supabase/schema.sql` — there is no separate n8n signup endpoint. The dashboard's "Serviços"
  card (list + inline edit/toggle + add form) talks to workflow `12` — this is how a salon manages
  its own catalog; there's no other UI for it.

Neither file hardcodes stylist names (`CABELEIREIROS`) or the salon name anymore — both call
`GET .../empresa-info` after resolving the empresa (by slug for `frontend-agenda`, by JWT for
`frontend-admin`, see workflow `11`) and populate those from the response. Scheduling *is* split
per-stylist: `01`, `02`, `08`, `09` and `10` all scope their reads/writes to
`Cabeleireiro === <chosen stylist>` (plus `empresa_id`), so two clients can book the same time
slot as long as they pick different stylists, and a block on one stylist doesn't affect another's
availability.

## Running locally

No package manager, no build. Local dev spins up the whole stack via Docker Compose. There is no
`.env.example` committed in this directory — create `.env` directly (see the variables
referenced in `docker-compose.yml`: `DOMAIN`, `N8N_ENCRYPTION_KEY`, `N8N_BASIC_AUTH_USER/PASSWORD`,
`TIMEZONE`, `N8N_DB_PASSWORD`, `GOOGLE_SHEET_ID`, `EVOLUTION_API_KEY`, `EVOLUTION_INSTANCE`,
`EVOLUTION_DB_PASSWORD`, `SALON_ADMIN_WHATSAPP`, `SALON_NAME`), then:

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
it end-to-end (client app → sheet row appears → WhatsApp message received → admin panel reflects
it) — see the checklist in `docs/deploy-vps-hostinger.md`.

## Editing n8n workflows

The `n8n-workflows/*.json` files are full n8n workflow exports (nodes + connections + settings).
When changing logic that lives in these workflows:
- Prefer editing the JSON directly for structural/logic changes (node parameters, `Code` node
  bodies), since there's no other source of truth — the JSON *is* the workflow.
- Any Google Sheets node references a credential by name/ID that only exists inside a given n8n
  instance; don't invent or change credential IDs.
- The Google Sheets nodes' `sheetName` field is set to the tab's numeric `gid`, not its name —
  see the "Importante" section in `docs/google-sheets-schema.md` before touching those nodes.
- Keep using `$env.*` for anything environment-specific (sheet ID, Evolution API URL/key,
  instance name, salon phone/name) rather than hardcoding — see `docker-compose.yml` for the full
  list of env vars injected into the n8n container.
- After editing, the change must be re-imported into n8n (Import from File) to take effect; there
  is no way to "run" these JSON files outside of n8n.

## Production deployment target

Single Hostinger KVM 2 VPS running the full `docker-compose.yml` stack (n8n + Postgres for n8n +
Evolution API + its own Postgres/Redis + Caddy), with 4 DNS A records pointing at it
(`n8n.`, `evolution.`, `agenda.`, `admin.` subdomains of `$DOMAIN`). Full step-by-step is in
`docs/deploy-vps-hostinger.md`. Never commit a real `.env` — it's git-ignored, and only ever
belongs on the VPS.

**Alternative deployment target**: `docs/deploy-easypanel.md` documents deploying to Easypanel
instead, paired with the Supabase-backed workflows in `n8n-workflows-supabase/` and the schema in
`supabase/schema.sql`. It's additive — the Hostinger/Google-Sheets path above stays intact and is
not being replaced. Supporting files for that path: `frontend-admin/Dockerfile`,
`frontend-agenda/Dockerfile`, and `easypanel/` (a trimmed `docker-compose.easypanel.yml` and an
`app_agendamento.env.example`).
