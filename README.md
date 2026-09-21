# app_zapagenda — Agendamento via WhatsApp para Salões (multi-tenant)

Sistema de agendamento via WhatsApp para salões de beleza, **multi-tenant**: uma única instalação
atende várias empresas (salões), cada uma isolada por `empresa_id` + Row Level Security no
Postgres. Toda a lógica de negócio mora em workflows do n8n; os dados ficam no Supabase
(Postgres); as mensagens de WhatsApp passam pela **Evolution API**, com **uma instância por
empresa**.

- **App do cliente** (`frontend-agenda/`): escolhe colaborador, serviço, data e horário, confirma
  pelo WhatsApp. Um deploy só, servido por subdomínio dinâmico (`<slug-da-empresa>.agenda.<domínio>`).
- **Painel da empresa** (`frontend-admin/`): login/cadastro via Supabase Auth, dashboard do dia,
  cancelar/finalizar atendimentos, bloqueio de agenda, catálogo de serviços, conexão do WhatsApp
  (QR code) — tudo escopado à empresa logada.
- **Automações** (`n8n-workflows-supabase/`): 15 workflows do n8n (validação, checagem de
  conflito de horário, catálogo de serviços, chatbot de WhatsApp, lembrete automático, cobrança
  via Hotmart) — sem servidor "de aplicação" além do próprio n8n.
- **Banco de dados**: Supabase (Postgres gerenciado), com RLS protegendo o painel admin e o n8n
  filtrando explicitamente por `empresa_id` no fluxo público.
- **Infraestrutura de produção**: Easypanel, self-hosted numa VPS Hostinger, atrás de Traefik.

## Arquitetura

```
Cliente (celular)                         Dono da empresa (celular/PC)
      │                                          │
      ▼                                          ▼
<slug>.agenda.<dominio>                admin.<dominio>
(frontend-agenda/index.html)          (frontend-admin/index.html)
      │                                          │
      └────────────────────┬─────────────────────┘
                            ▼
                   n8n.<dominio>  (n8n — webhooks + cron)
                            │
             ┌──────────────┼───────────────────┐
             ▼                                   ▼
       Supabase (Postgres)                Evolution API (WhatsApp)
       empresas / servicos /              1 instância por empresa
       agendamentos / bloqueios                   │
             ▲                                    ▼
             │                          WhatsApp do cliente / da empresa
     Hotmart (webhook de assinatura:
     cancelamento/reembolso desativa
     a empresa automaticamente)
```

## Estrutura do projeto

```
frontend-agenda/index.html      → app de agendamento do cliente (HTML+JS puro, sem build)
frontend-admin/index.html       → painel da empresa (Supabase Auth + dashboard)
n8n-workflows-supabase/         → 15 arquivos JSON (00-14), importar direto no n8n
  00-listar-servicos            09-listar-bloqueios
  01-horarios-disponiveis       10-cancelar-bloqueio
  02-criar-agendamento          11-empresa-info (+ atualizar colaboradores)
  03-listar-agendamentos        12-servicos-admin (CRUD do catálogo)
  04-cancelar-agendamento       13-conectar-whatsapp (QR code por empresa)
  05-finalizar-agendamento      14-hotmart-webhook (assinatura: ativa/desativa empresa)
  06-lembrete-automatico
  07-chatbot-whatsapp
  08-criar-bloqueio
supabase/schema.sql             → schema completo (tabelas, RLS, triggers) — rodar no SQL Editor
docs/                           → deploy-easypanel.md, plano-multi-tenant.md, evolution-api-setup.md,
                                   manual-painel-admin.md (manual em linguagem simples pro dono)
easypanel/                      → compose + .env.example do deploy de produção
docker-compose.yml + Caddyfile  → stack manual alternativa (não é o que roda em produção hoje)
.env.example                    → variáveis de ambiente (copie para .env)
```

## Como colocar no ar

Produção roda hoje em **Easypanel** — siga `docs/deploy-easypanel.md` de ponta a ponta (cria o
projeto no Supabase e roda `supabase/schema.sql`, sobe n8n + Evolution API + os dois frontends
como apps no Easypanel, importa os workflows de `n8n-workflows-supabase/`, configura o domínio
wildcard `*.agenda.<domínio>` via Cloudflare para o multi-tenant). `docs/plano-multi-tenant.md`
tem o histórico de decisão dessa arquitetura.

## Rodando localmente

```bash
docker compose up -d
```

Sem `.env.example` versionado com valores reais — copie `.env.example` para `.env` e preencha.
`docker-compose.override.yml` (aplicado automaticamente em dev) expõe os frontends em
`localhost:8081`/`:8082`, o n8n em `:5678` e a Evolution API em `:8080`, sem precisar de
Caddy/HTTPS. Não existem testes automatizados, linters ou CI — "testar" uma mudança é
reimportar o workflow no n8n e rodar o fluxo de ponta a ponta.

## Vendendo o produto (Hotmart)

O app_zapagenda é vendido como assinatura na Hotmart. O workflow `14-hotmart-webhook-supabase`
recebe os eventos de compra aprovada/cancelada/reembolsada/chargeback e ativa ou desativa a
empresa correspondente (casada pelo e-mail do comprador) — o cadastro em si continua sendo feito
pela própria empresa no `frontend-admin`.
