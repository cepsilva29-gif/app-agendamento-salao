-- supabase/schema.sql
--
-- Rode isto no SQL Editor do projeto Supabase (Dashboard -> SQL Editor -> New query).
-- Modelo multi-tenant: uma instalação atende várias empresas (salões), cada uma isolada por
-- `empresa_id` + Row Level Security. Ver docs/deploy-easypanel.md para o passo a passo de deploy
-- que usa este schema, e docs/plano-multi-tenant.md para o histórico de decisão desta arquitetura.
--
-- Decisões de tipo (por que não é tudo "óbvio"):
--   - status / ativo: text + CHECK, não um enum nativo. Um enum exige ALTER TYPE ... ADD VALUE
--     para acrescentar um valor novo (fricção desnecessária para algo que praticamente nunca
--     muda); um CHECK dá a mesma garantia de integridade com ALTER TABLE normal.
--   - hora / hora_inicio / hora_fim: text com CHECK de formato "HH:MM", não o tipo `time` nativo.
--     O PostgREST serializa `time` como "HH:MM:SS" (com segundos), o que quebraria a comparação
--     exata que o frontend e os Code nodes fazem contra strings "HH:MM" — e toda a aritmética de
--     horário já acontece em JS (toMinutos()), nunca em SQL, então usar `time` não traria
--     benefício nenhum.
--   - data: `date` nativo — o PostgREST serializa como "YYYY-MM-DD", que já bate com o contrato
--     esperado pelos dois frontends.
--   - lembrete_enviado / ativo: `boolean` real (na planilha eram strings 'TRUE'/'FALSE'/'1'/'SIM').
--
-- Modelo de isolamento entre empresas (por que RLS + filtro explícito, os dois):
--   - `empresas`/`perfis`/`servicos`/`agendamentos`/`bloqueios` têm RLS habilitado com policies
--     escopadas por `empresa_atual()` (ver abaixo) para o role `authenticated` — isso é o que
--     protege o painel admin: mesmo que um workflow n8n esqueça de filtrar por empresa_id, o
--     Postgres recusa ler/escrever fora da empresa do usuário logado.
--   - Não existe nenhuma policy para o role `anon`. O fluxo público de agendamento (cliente final,
--     sem login) nunca fala direto com o PostgREST — sempre passa pelo n8n usando a chave
--     `service_role` (que ignora RLS por padrão), resolvendo a empresa por slug e filtrando
--     explicitamente por `empresa_id` em cada query. Isso é necessário porque um visitante anônimo
--     não tem identidade nenhuma pro RLS validar contra — não tem como o Postgres "saber" sozinho
--     qual empresa é a de um request sem sessão.

create table if not exists empresas (
  id                 bigint generated always as identity primary key,
  slug               text not null unique,          -- usado no path dos webhooks publicos, ex: 'salao-da-ana'
  nome               text not null,
  whatsapp_admin     text not null,                  -- notificado a cada novo agendamento
  evolution_instance text not null unique,           -- nome da instancia na Evolution API
  timezone           text not null default 'America/Sao_Paulo',
  cabeleireiros      jsonb not null default '[]',    -- ["Carlos","Ana","Bruno"], substitui o hardcode nos frontends
  ativo              boolean not null default true,
  criado_em          timestamptz not null default now()
);

-- Um usuário do Supabase Auth = dono de uma empresa (MVP: 1 usuário : 1 empresa, role 'owner').
create table if not exists perfis (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  empresa_id bigint not null references empresas(id) on delete cascade,
  role       text not null default 'owner' check (role in ('owner')),
  criado_em  timestamptz not null default now()
);

create table if not exists servicos (
  id               bigint generated always as identity primary key,
  empresa_id       bigint not null references empresas(id) on delete cascade,
  nome             text not null,
  preco            numeric(10,2) not null,
  duracao_minutos  integer not null default 30,
  ativo            boolean not null default true,
  unique (empresa_id, nome)
);

create table if not exists agendamentos (
  id               text primary key,                 -- 'AG-<timestamp_ms>', gerado no Code node "Validar Dados"
  empresa_id       bigint not null references empresas(id) on delete cascade,
  nome             text not null,
  whatsapp         text not null,                     -- só dígitos, com DDI (ex: 5511999998888)
  servico          text not null,                     -- nome do serviço no momento da reserva (preco/duracao já travados do catálogo)
  preco            numeric(10,2) not null,
  duracao_minutos  integer not null,
  cabeleireiro     text not null,
  data             date not null,
  hora             text not null check (hora ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  status           text not null default 'Confirmado' check (status in ('Confirmado','Cancelado','Finalizado')),
  criado_em        timestamptz not null default now(),
  lembrete_enviado boolean not null default false
);

create index if not exists idx_agendamentos_empresa_cabeleireiro_data_status on agendamentos (empresa_id, cabeleireiro, data, status);
create index if not exists idx_agendamentos_empresa_data on agendamentos (empresa_id, data);
create index if not exists idx_agendamentos_whatsapp on agendamentos (whatsapp);

create table if not exists bloqueios (
  id            text primary key,                     -- 'BQ-<timestamp_ms>'
  empresa_id    bigint not null references empresas(id) on delete cascade,
  cabeleireiro  text not null,
  data          date not null,
  hora_inicio   text check (hora_inicio is null or hora_inicio ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  hora_fim      text check (hora_fim is null or hora_fim ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  motivo        text,
  status        text not null default 'Ativo' check (status in ('Ativo','Cancelado')),
  criado_em     timestamptz not null default now()
);
-- hora_inicio/hora_fim NULL (nao '') = bloqueio de dia inteiro. As checagens em JS
-- (`!row.hora_inicio`) tratam null e string vazia da mesma forma, entao isso e compativel.

create index if not exists idx_bloqueios_empresa_cabeleireiro_data_status on bloqueios (empresa_id, cabeleireiro, data, status);

-- Migração para instalações que já tinham servicos/agendamentos/bloqueios de um deploy
-- single-tenant anterior (os `create table if not exists` acima não alteram tabelas já
-- existentes): adiciona empresa_id, troca o unique de servicos e remove os índices antigos sem
-- empresa_id. Sem efeito (tudo IF NOT EXISTS/IF EXISTS) numa instalação nova, onde as tabelas já
-- nascem com empresa_id pelos CREATE TABLE acima.
alter table servicos     add column if not exists empresa_id bigint references empresas(id) on delete cascade;
alter table agendamentos add column if not exists empresa_id bigint references empresas(id) on delete cascade;
alter table bloqueios    add column if not exists empresa_id bigint references empresas(id) on delete cascade;

alter table servicos     alter column empresa_id set not null;
alter table agendamentos alter column empresa_id set not null;
alter table bloqueios    alter column empresa_id set not null;

alter table servicos drop constraint if exists servicos_nome_key;
alter table servicos drop constraint if exists servicos_empresa_id_nome_key;
alter table servicos add constraint servicos_empresa_id_nome_key unique (empresa_id, nome);

drop index if exists idx_agendamentos_cabeleireiro_data_status;
drop index if exists idx_agendamentos_data;
drop index if exists idx_bloqueios_cabeleireiro_data_status;

-- Resolve a empresa do usuário logado a partir do JWT (auth.uid()). security definer porque
-- `perfis` também tem RLS habilitado — sem isso a função não conseguiria nem ler a própria linha.
create or replace function public.empresa_atual()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select empresa_id from perfis where user_id = auth.uid()
$$;

-- Provisiona empresa + perfil automaticamente no signup (supabase.auth.signUp com
-- options.data = { slug, nome_empresa, whatsapp_admin, cabeleireiros }). Ver
-- frontend-admin/index.html (tela de cadastro) para quem preenche esse metadata.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa_id bigint;
begin
  insert into empresas (slug, nome, whatsapp_admin, evolution_instance, cabeleireiros)
  values (
    new.raw_user_meta_data->>'slug',
    new.raw_user_meta_data->>'nome_empresa',
    new.raw_user_meta_data->>'whatsapp_admin',
    new.raw_user_meta_data->>'slug', -- 1 instancia Evolution por empresa; nome da instancia = slug
    coalesce(new.raw_user_meta_data->'cabeleireiros', '[]'::jsonb)
  )
  returning id into v_empresa_id;

  insert into perfis (user_id, empresa_id) values (new.id, v_empresa_id);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Preenche empresa_id automaticamente em INSERTs feitos por um usuário autenticado (painel
-- admin), pra esses workflows não precisarem saber/enviar o empresa_id explicitamente — só
-- precisam encaminhar o JWT do usuário. Não afeta o fluxo público (service_role): ali o n8n
-- resolve a empresa pelo slug e sempre envia empresa_id explícito na query de insert; se um
-- workflow público esquecer, este mesmo trigger tenta empresa_atual(), que resolve null pra
-- service_role (sem linha em perfis) e o INSERT falha pela constraint not null — falha segura,
-- não um vazamento entre empresas.
create or replace function public.set_empresa_id_padrao()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.empresa_id is null then
    new.empresa_id := public.empresa_atual();
  end if;
  return new;
end;
$$;

drop trigger if exists set_empresa_id_servicos on servicos;
create trigger set_empresa_id_servicos
  before insert on servicos
  for each row execute function public.set_empresa_id_padrao();

drop trigger if exists set_empresa_id_agendamentos on agendamentos;
create trigger set_empresa_id_agendamentos
  before insert on agendamentos
  for each row execute function public.set_empresa_id_padrao();

drop trigger if exists set_empresa_id_bloqueios on bloqueios;
create trigger set_empresa_id_bloqueios
  before insert on bloqueios
  for each row execute function public.set_empresa_id_padrao();

alter table empresas     enable row level security;
alter table perfis       enable row level security;
alter table servicos     enable row level security;
alter table agendamentos enable row level security;
alter table bloqueios    enable row level security;

-- perfis: cada usuário só enxerga a própria linha.
drop policy if exists "perfis_select_own" on perfis;
create policy "perfis_select_own" on perfis
  for select to authenticated
  using (user_id = auth.uid());

-- empresas: cada usuário só enxerga a própria empresa (via perfis).
drop policy if exists "empresas_select_own" on empresas;
create policy "empresas_select_own" on empresas
  for select to authenticated
  using (id = public.empresa_atual());

-- servicos/agendamentos/bloqueios: CRUD completo, sempre restrito à empresa do usuário logado.
-- Nenhuma policy para o role `anon` de propósito — ver nota no topo do arquivo.
drop policy if exists "servicos_all_own_empresa" on servicos;
create policy "servicos_all_own_empresa" on servicos
  for all to authenticated
  using (empresa_id = public.empresa_atual())
  with check (empresa_id = public.empresa_atual());

drop policy if exists "agendamentos_all_own_empresa" on agendamentos;
create policy "agendamentos_all_own_empresa" on agendamentos
  for all to authenticated
  using (empresa_id = public.empresa_atual())
  with check (empresa_id = public.empresa_atual());

drop policy if exists "bloqueios_all_own_empresa" on bloqueios;
create policy "bloqueios_all_own_empresa" on bloqueios
  for all to authenticated
  using (empresa_id = public.empresa_atual())
  with check (empresa_id = public.empresa_atual());

-- Seed opcional pra testar localmente (troque <EMPRESA_ID> pelo id gerado no signup da empresa
-- de teste, e edite os serviços conforme o catálogo real do salão — mesmos 4 exemplos já
-- documentados em docs/google-sheets-schema.md):
-- insert into servicos (empresa_id, nome, preco, duracao_minutos, ativo) values
--   (<EMPRESA_ID>, 'Corte Masculino', 50, 30, true),
--   (<EMPRESA_ID>, 'Escova', 80, 45, true),
--   (<EMPRESA_ID>, 'Corte Masculino + Barba', 75, 45, true),
--   (<EMPRESA_ID>, 'Coloração', 150, 90, true);
