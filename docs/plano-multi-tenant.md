# Plano exploratório: multi-tenant (várias empresas no mesmo app_agendamento)

> **Status: implementado** (schema, RLS, auth do painel admin, workflows Supabase e frontends).
> Este documento é o mapeamento original do problema e das opções consideradas — a decisão de
> design efetivamente tomada (Opção B abaixo: workflows compartilhados, tenant por slug/JWT, RLS
> como camada extra de isolamento no painel admin) está registrada e detalhada em
> `docs/deploy-easypanel.md` e nos comentários de `supabase/schema.sql`. Mantido aqui como
> histórico de decisão — não precisa ser lido para operar o sistema hoje.

## Por que hoje é single-tenant

- **Supabase**: as 3 tabelas (`servicos`, `agendamentos`, `bloqueios`) não têm nenhuma coluna de
  empresa — tudo é um balde só. `servicos.nome` tem `unique` global, o que já quebraria com 2
  empresas cadastrando "Corte Masculino".
- **n8n**: todo o `$env.*` usado nos workflows (`SALON_NAME`, `SALON_ADMIN_WHATSAPP`,
  `EVOLUTION_INSTANCE`, `EVOLUTION_API_URL`, `DOMAIN`) é global ao container — um valor só pra
  toda a instalação.
- **Frontends**: `frontend-agenda/index.html` e `frontend-admin/index.html` têm
  `NOME_SALAO`/`SALON_NAME` e o array `CABELEIREIROS` hardcoded direto no HTML/JS.
- **Admin**: o painel (`frontend-admin/`) não tem autenticação nenhuma — é uma página estática
  aberta. Pra multi-tenant isso deixa de ser aceitável (a empresa A não pode ver/mexer nos
  agendamentos da empresa B).
- **WhatsApp**: um número de WhatsApp Business = uma identidade pro cliente final. Isso não é uma
  limitação deste app, é uma limitação do WhatsApp — **não dá pra compartilhar um número entre
  empresas diferentes**, então essa parte escala 1:1 (1 instância Evolution + 1 número por
  empresa) em qualquer uma das abordagens abaixo.

## Peça 1 — Modelo de dados (Supabase)

Nova tabela `empresas`:

```sql
create table empresas (
  id                 bigint generated always as identity primary key,
  slug               text not null unique,        -- usado na URL/subdominio, ex: 'empresa-da-ana'
  nome               text not null,
  whatsapp_admin     text not null,                -- notificado a cada novo agendamento
  evolution_instance text not null unique,         -- nome da instancia na Evolution API
  timezone           text not null default 'America/Sao_Paulo',
  colaboradores      jsonb not null default '[]',  -- ["Carlos","Ana","Bruno"], substitui o hardcode no frontend
  ativo              boolean not null default true,
  criado_em          timestamptz not null default now()
);
```

Nas 3 tabelas existentes, adicionar `empresa_id bigint not null references empresas(id)` e:

- trocar `servicos.nome unique` por `unique (empresa_id, nome)`.
- todo índice/filtro que hoje é por `colaborador`/`data`/`status` passa a levar `empresa_id`
  junto (ex: `idx_agendamentos_empresa_colaborador_data_status`).
- RLS: já está habilitado nas 3 tabelas sem policy (o n8n usa a `service_role` key, que ignora
  RLS). Isso continua valendo — o isolamento entre empresas não vem do RLS, vem de **todo
  workflow sempre filtrar por `empresa_id` resolvido no início da execução** (ver Peça 3). Vale
  registrar esse ponto como risco: um bug num filtro Supabase esquecido é um vazamento de dados
  entre empresas, não só um bug de UX como os que corrigimos hoje.

## Peça 2 — Como identificar "de qual empresa é essa requisição"

Duas opções, ambas viáveis:

1. **Subdomínio** (`agenda.empresa-da-ana.seudominio.com`, `admin.empresa-da-ana.seudominio.com`) —
   mais amigável pro cliente final, mas exige DNS wildcard (`*.seudominio.com`) + certificado
   wildcard, e cada frontend precisa extrair o slug de `location.hostname` no lugar do
   `NOME_SALAO`/`CABELEIREIROS` hardcoded hoje.
2. **Prefixo no path do webhook** (`/webhook/empresa-da-ana/criar-agendamento`) — mais simples de
   configurar (sem DNS extra), mas menos "profissional" pro cliente final e exige que o frontend
   saiba seu próprio slug (via build/config, já que não tem mais domínio próprio pra descobrir
   sozinho).

**Recomendação**: subdomínio para os 2 frontends (`agenda.`/`admin.<slug>.dominio`), path-prefix
só nos webhooks internos do n8n (mais fácil de implementar e não é visível pro cliente final de
qualquer forma).

## Peça 3 — n8n: workflows compartilhados vs. duplicados por empresa

**Opção A — duplicar os 11 workflows por empresa.** Zero mudança de lógica, só reimportar o
mesmo pacote de hoje trocando os `$env.*` por valores fixos por empresa. Simples de montar uma
empresa nova, péssimo pra manter (bug encontrado = corrigir em N lugares; hoje já vimos 2 bugs
sistêmicos que precisaram de correção em 4 workflows cada — com 10 empresas isso vira 40+ edições
manuais por bug).

**Opção B — um workflow set só, parametrizado por `empresa_id` (recomendada).** Cada webhook
recebe o slug (path ou header vindo do Caddy/proxy) e o primeiro passo de cada workflow vira
"resolver empresa": um node Supabase faz `select * from empresas where slug = ...`, e a partir
daí todo `$env.SALON_NAME` vira `{{ $('Resolver Empresa').first().json.nome }}`, todo filtro
Supabase leva `empresa_id eq {{ ... }}`, e a URL da Evolution API/instância vem de
`evolution_instance` da empresa em vez de `$env.EVOLUTION_INSTANCE`. O `07-chatbot-whatsapp` é o
caso especial: quem chega é a Evolution API dizendo qual `instance` mandou o evento — dá pra
resolver a empresa por `evolution_instance` em vez de por slug de URL.

Isso significa reescrever os ~14 nós Supabase e ~6 nós HTTP-Evolution que hoje usam `$env.*`
direto — é o grosso do esforço, mas uma vez feito, correções futuras (como as de hoje) são feitas
uma vez só.

## Peça 4 — Evolution API (WhatsApp) por empresa

Cada empresa precisa da própria instância Evolution (própria conexão de WhatsApp, próprio QR
code). A Evolution API já suporta múltiplas instâncias no mesmo servidor/container — não precisa
de um container Evolution por empresa, só criar uma instância nova (`POST /instance/create`) por
empresa e configurar o `WEBHOOK_GLOBAL_URL` dela apontando pro mesmo endpoint `/webhook/whatsapp-in`
do n8n (o payload já traz `instance`, usado pra resolver a empresa — ver Peça 3).

## Peça 5 — Onboarding de empresa nova

Com a Opção B (workflows compartilhados), dar alta a uma empresa nova vira:

1. Inserir a linha em `empresas` (slug, nome, whatsapp_admin, colaboradores).
2. Criar a instância Evolution correspondente e conectar o WhatsApp (escanear QR).
3. Cadastrar o catálogo de serviços dela em `servicos` (com o `empresa_id` certo).
4. Apontar `agenda.<slug>` / `admin.<slug>` no Caddy/Easypanel pro mesmo par de containers de
   frontend (eles já ficam dinâmicos a partir da Peça 2).

Nenhum passo manual no n8n — os workflows já são compartilhados.

## Peça 6 — o que fica pendente / em aberto

- **Autenticação do painel admin**: hoje inexistente. Pra multi-tenant é obrigatório (login por
  empresa, ou ao menos um token por subdomínio) — precisa decidir se é login de verdade (usuário/
  senha, Supabase Auth) ou algo mais simples tipo link com token de acesso.
- **Billing/limites**: fora de escopo deste doc, mas relevante se isso virar produto vendável
  (limite de agendamentos/mês por plano, etc.).
- **Migração dos dados atuais**: a instalação de hoje (Boot-n8n) vira a "empresa 1" — precisa de
  uma migration que cria a linha em `empresas` e faz `update servicos/agendamentos/bloqueios set
  empresa_id = 1` nos dados existentes.

## Esforço aproximado (ordem de grandeza, não é estimativa fechada)

| Peça | Esforço |
|---|---|
| Schema Supabase (empresas + FK + índices) | Pequeno |
| Reescrever os 11 workflows pra Opção B | Grande (é o grosso) |
| Frontends dinâmicos por subdomínio | Médio |
| Auth no painel admin | Médio |
| Onboarding automatizado de empresa nova | Pequeno, depois que o resto existe |

**Recomendação geral**: vale a pena migrar pra Opção B (workflows compartilhados) mesmo que a
timeline de multi-tenant real seja incerta — é a mesma decisão de design que já se pagou hoje
quando dois bugs sistêmicos precisaram de correção em 4 workflows de uma vez; com 10+ empresas
rodando a Opção A, cada bug desses viraria uma operação manual em 40+ lugares.
