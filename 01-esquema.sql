-- ═══════════════════════════════════════════════════════════════════════════
--  Fatura da Casa — esquema inicial
--  Cole inteiro no SQL Editor do Supabase e clique em Run.
--  Pode rodar mais de uma vez sem estragar nada.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Tabelas ───────────────────────────────────────────────────────────────

create table if not exists public.casa (
  id              uuid primary key default gen_random_uuid(),
  nome            text        not null default 'Casa',
  dia_corte       int         not null default 20 check (dia_corte between 1 and 28),
  teto_cent       bigint      not null default 300000,
  alertas         boolean     not null default true,
  codigo_convite  text        not null unique default upper(substr(md5(random()::text), 1, 6)),
  recorrencias    jsonb       not null default '[]'::jsonb,
  parcelamentos   jsonb       not null default '[]'::jsonb,
  categorias      jsonb       not null default '[]'::jsonb,
  parcela_base    text,
  criado_em       timestamptz not null default now()
);

create table if not exists public.membro (
  id            uuid primary key default gen_random_uuid(),
  casa_id       uuid        not null references public.casa(id) on delete cascade,
  user_id       uuid        not null references auth.users(id)  on delete cascade,
  nome_exibicao text        not null,
  ordem         int         not null default 0,
  criado_em     timestamptz not null default now(),
  unique (casa_id, user_id),
  unique (casa_id, nome_exibicao)
);

-- O id vem do cliente: preserva os identificadores que já existem no aparelho
-- e torna a migração idempotente (reenviar não duplica).
create table if not exists public.lancamento (
  id                      uuid primary key,
  casa_id                 uuid        not null references public.casa(id) on delete cascade,
  competencia             text        not null,
  descricao               text        not null,
  valor_cent              bigint,
  pagador                 text        not null,
  icone                   text,
  categoria               text,
  natureza                text,
  projeto                 text,
  escopo                  text        not null default 'fatura',
  tipo_rateio             text        not null default 'igual',
  data_despesa            date,
  parcela                 text,
  parcela_grupo_id        text,
  valor_total_compra_cent bigint,
  recorrencia_id          text,
  estimado                boolean     not null default false,
  base                    text,
  obs                     text,
  criado_por              text,
  atualizado_por          text,
  criado_em               timestamptz not null default now(),
  atualizado_em           timestamptz not null default now(),
  excluido_em             timestamptz
);

create table if not exists public.transferencia (
  id            uuid primary key,
  casa_id       uuid        not null references public.casa(id) on delete cascade,
  competencia   text        not null,
  de_membro     text        not null,
  para_membro   text        not null,
  valor_cent    bigint      not null,
  data          date,
  finalidade    text        not null default 'adiantamento',
  obs           text,
  considerar    boolean     not null default true,
  criado_por    text,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  excluido_em   timestamptz
);

create table if not exists public.ciclo (
  casa_id       uuid        not null references public.casa(id) on delete cascade,
  competencia   text        not null,
  status        text        not null default 'aberto',
  aprovacoes    jsonb       not null default '{}'::jsonb,
  marcos        jsonb       not null default '[]'::jsonb,
  previa_em     timestamptz,
  fechado_em    timestamptz,
  pago_em       date,
  semeado       boolean     not null default false,
  atualizado_em timestamptz not null default now(),
  primary key (casa_id, competencia)
);

create index if not exists ix_lanc_casa_comp on public.lancamento (casa_id, competencia);
create index if not exists ix_transf_casa    on public.transferencia (casa_id, competencia);
create index if not exists ix_membro_user    on public.membro (user_id);

-- ─── Quem enxerga o quê ────────────────────────────────────────────────────
-- SECURITY DEFINER para quebrar a recursão: uma política sobre `membro` que
-- consultasse `membro` entraria em laço infinito.

create or replace function public.minhas_casas()
returns setof uuid
language sql stable security definer set search_path = public
as $$ select casa_id from public.membro where user_id = auth.uid() $$;

create or replace function public.meu_nome(p_casa uuid)
returns text
language sql stable security definer set search_path = public
as $$ select nome_exibicao from public.membro
     where casa_id = p_casa and user_id = auth.uid() limit 1 $$;

alter table public.casa          enable row level security;
alter table public.membro        enable row level security;
alter table public.lancamento    enable row level security;
alter table public.transferencia enable row level security;
alter table public.ciclo         enable row level security;

drop policy if exists p_casa_sel on public.casa;
drop policy if exists p_casa_upd on public.casa;
drop policy if exists p_casa_ins on public.casa;
create policy p_casa_sel on public.casa for select
  using (id in (select public.minhas_casas()));
create policy p_casa_upd on public.casa for update
  using (id in (select public.minhas_casas()));
create policy p_casa_ins on public.casa for insert
  with check (auth.uid() is not null);

drop policy if exists p_membro_sel on public.membro;
drop policy if exists p_membro_ins on public.membro;
create policy p_membro_sel on public.membro for select
  using (casa_id in (select public.minhas_casas()));
create policy p_membro_ins on public.membro for insert
  with check (user_id = auth.uid());

-- As três tabelas de movimento seguem a mesma regra: só quem é membro da casa.
do $$
declare t text;
begin
  foreach t in array array['lancamento','transferencia','ciclo'] loop
    execute format('drop policy if exists p_%1$s_all on public.%1$s', t);
    execute format(
      'create policy p_%1$s_all on public.%1$s for all
         using      (casa_id in (select public.minhas_casas()))
         with check (casa_id in (select public.minhas_casas()))', t);
  end loop;
end $$;

-- ─── Entrar numa casa pelo código de convite ───────────────────────────────

create or replace function public.entrar_na_casa(p_codigo text, p_nome text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_casa uuid;
begin
  select id into v_casa from public.casa
    where codigo_convite = upper(trim(p_codigo));
  if v_casa is null then
    raise exception 'Código de convite não encontrado.';
  end if;
  insert into public.membro (casa_id, user_id, nome_exibicao, ordem)
    values (v_casa, auth.uid(), p_nome,
            (select count(*) from public.membro where casa_id = v_casa))
    on conflict (casa_id, user_id) do update set nome_exibicao = excluded.nome_exibicao;
  return v_casa;
end $$;

-- ─── Tempo real ────────────────────────────────────────────────────────────

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

-- Incluir uma tabela que já está na publicação é ERRO no Postgres, não
-- silêncio. Sem este laço, a segunda execução do arquivo parava aqui com
-- 42710 e a transação inteira era desfeita.
do $$
declare t text;
begin
  foreach t in array array['lancamento','transferencia','ciclo','casa'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Realtime precisa da linha inteira para avisar o outro aparelho sobre edições.
alter table public.lancamento    replica identity full;
alter table public.transferencia replica identity full;
alter table public.ciclo         replica identity full;

select 'esquema aplicado' as resultado;
