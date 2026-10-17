-- ═══════════════════════════════════════════════════════════════════════════
--  Fatura da Casa — identificadores passam de uuid para texto
--  Cole inteiro no SQL Editor do Supabase e clique em Run.
--  Pode rodar mais de uma vez sem estragar nada.
--
--  O Supabase VAI mostrar o aviso de "operações destrutivas": o script
--  derruba políticas, funções e chaves estrangeiras para recriá-las logo
--  em seguida. NÃO há drop table, delete nem truncate — nenhuma linha é
--  apagada em momento algum.
--
--  Por quê: os identificadores são gerados no aparelho, não no banco, e
--  nem todos têm forma de uuid — os dados de partida usam 'casa-1',
--  'ago-00', 'cred-mai-jul'. Exigir uuid rejeitaria 37 lançamentos e a
--  transferência de crédito. Como o banco nunca interpreta esses valores,
--  só os compara, texto serve igual e aceita o que já existe.
--
--  membro.user_id continua uuid: aquele vem do Supabase, não do aparelho.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 1. políticas e funções saem da frente ────────────────────────────────
-- As políticas chamam minhas_casas(); a função não pode mudar de tipo
-- enquanto alguém depende dela.

drop policy if exists p_casa_sel   on public.casa;
drop policy if exists p_casa_upd   on public.casa;
drop policy if exists p_casa_ins   on public.casa;
drop policy if exists p_membro_sel on public.membro;
drop policy if exists p_membro_ins on public.membro;

do $$
declare t text;
begin
  foreach t in array array['lancamento','transferencia','ciclo'] loop
    execute format('drop policy if exists p_%1$s_all on public.%1$s', t);
  end loop;
end $$;

drop function if exists public.minhas_casas();
drop function if exists public.meu_nome(uuid);
drop function if exists public.meu_nome(text);
drop function if exists public.entrar_na_casa(text, text);

-- ─── 2. chaves estrangeiras que apontam para casa(id) ─────────────────────

alter table public.membro        drop constraint if exists membro_casa_id_fkey;
alter table public.lancamento    drop constraint if exists lancamento_casa_id_fkey;
alter table public.transferencia drop constraint if exists transferencia_casa_id_fkey;
alter table public.ciclo         drop constraint if exists ciclo_casa_id_fkey;

-- ─── 3. troca dos tipos ───────────────────────────────────────────────────

alter table public.casa          alter column id      drop default;
alter table public.casa          alter column id      type text using id::text;
alter table public.casa          alter column id      set default gen_random_uuid()::text;

alter table public.membro        alter column casa_id type text using casa_id::text;
alter table public.lancamento    alter column id      type text using id::text;
alter table public.lancamento    alter column casa_id type text using casa_id::text;
alter table public.transferencia alter column id      type text using id::text;
alter table public.transferencia alter column casa_id type text using casa_id::text;
alter table public.ciclo         alter column casa_id type text using casa_id::text;

-- ─── 4. chaves estrangeiras de volta ──────────────────────────────────────

alter table public.membro        add constraint membro_casa_id_fkey
  foreign key (casa_id) references public.casa(id) on delete cascade;
alter table public.lancamento    add constraint lancamento_casa_id_fkey
  foreign key (casa_id) references public.casa(id) on delete cascade;
alter table public.transferencia add constraint transferencia_casa_id_fkey
  foreign key (casa_id) references public.casa(id) on delete cascade;
alter table public.ciclo         add constraint ciclo_casa_id_fkey
  foreign key (casa_id) references public.casa(id) on delete cascade;

-- ─── 5. funções de volta, agora em texto ──────────────────────────────────

create or replace function public.minhas_casas()
returns setof text
language sql stable security definer set search_path = public
as $$ select casa_id from public.membro where user_id = auth.uid() $$;

create or replace function public.meu_nome(p_casa text)
returns text
language sql stable security definer set search_path = public
as $$ select nome_exibicao from public.membro
     where casa_id = p_casa and user_id = auth.uid() limit 1 $$;

create or replace function public.entrar_na_casa(p_codigo text, p_nome text)
returns text
language plpgsql security definer set search_path = public
as $$
declare v_casa text;
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

-- ─── 6. políticas de volta, idênticas ─────────────────────────────────────

create policy p_casa_sel on public.casa for select
  using (id in (select public.minhas_casas()));
create policy p_casa_upd on public.casa for update
  using (id in (select public.minhas_casas()));
create policy p_casa_ins on public.casa for insert
  with check (auth.uid() is not null);

create policy p_membro_sel on public.membro for select
  using (casa_id in (select public.minhas_casas()));
create policy p_membro_ins on public.membro for insert
  with check (user_id = auth.uid());

do $$
declare t text;
begin
  foreach t in array array['lancamento','transferencia','ciclo'] loop
    execute format(
      'create policy p_%1$s_all on public.%1$s for all
         using      (casa_id in (select public.minhas_casas()))
         with check (casa_id in (select public.minhas_casas()))', t);
  end loop;
end $$;

select 'identificadores em texto' as resultado;
