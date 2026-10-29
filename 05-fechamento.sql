-- ═══════════════════════════════════════════════════════════════════════════
--  Fatura da Casa — fechamento à prova de dois aparelhos + reparo de outubro
--  Cole inteiro no SQL Editor do Supabase e clique em Run.
--  Pode rodar mais de uma vez sem estragar nada.
--
--  O Supabase vai mostrar o aviso de "operações destrutivas": há
--  "drop trigger if exists", para o script poder ser repetido. Não há
--  drop table, delete nem truncate — nenhuma linha é apagada.
--
--  Ao terminar, a tabela de resultado mostra o estado final de setembro a
--  novembro e o total de cada mês. Copie e mande para conferência.
-- ═══════════════════════════════════════════════════════════════════════════


-- ─── 1. O mês deixa de ser um bloco único ─────────────────────────────────
-- Até aqui, a versão mais recente de um mês substituía a outra por inteiro —
-- inclusive o de acordo de quem não tinha mexido. Agora cada parte tem regra
-- própria:
--   • STATUS (prévia, definitiva, pagamento): vence a versão mais recente. Só
--     ações de status avançam essa marca — dar o de acordo, não. Assim, um de
--     acordo dado num aparelho desatualizado não desfaz uma definitiva emitida
--     no outro;
--   • DE ACORDO: cada pessoa por si. Cada marcação carrega a própria hora (em
--     aprovacoes._em) e vence a mais recente de cada pessoa. Os dois podem
--     marcar ao mesmo tempo sem um apagar o outro;
--   • MARCOS DO TETO: somam-se, nunca se perdem;
--   • status desconhecido nunca entra, e hora no futuro (relógio adiantado)
--     é trazida para agora — senão travaria todo ajuste até aquela data.

create or replace function public.ciclo_mesclar()
returns trigger
language plpgsql
as $$
declare
  validos constant text[] := array['aberto','conferencia','fechado','quitado'];
  semente constant text   := '2000-01-01T00:00:00.000Z';
  oa jsonb; na jsonb; oe jsonb; ne jsonb;
  ap jsonb := '{}'::jsonb; em jsonb := '{}'::jsonb;
  k text; ot text; nt text;
begin
  if new.aprovacoes is null then new.aprovacoes := '{}'::jsonb; end if;
  if new.marcos     is null then new.marcos     := '[]'::jsonb; end if;
  if new.atualizado_em > now() + interval '2 minutes' then new.atualizado_em := now(); end if;

  if tg_op = 'INSERT' then
    if new.status is null or not (new.status = any (validos)) then new.status := 'aberto'; end if;
    return new;
  end if;

  -- status: a versão mais nova vence; inválida ou mais velha não entra
  if new.status is null or not (new.status = any (validos))
     or new.atualizado_em < old.atualizado_em then
    new.status        := old.status;
    new.previa_em     := old.previa_em;
    new.fechado_em    := old.fechado_em;
    new.pago_em       := old.pago_em;
    new.atualizado_em := old.atualizado_em;
  end if;

  -- de acordo: pessoa a pessoa, vence a marcação mais recente de cada uma
  oa := coalesce(old.aprovacoes, '{}'::jsonb);  na := new.aprovacoes;
  oe := coalesce(oa->'_em', '{}'::jsonb);       ne := coalesce(na->'_em', '{}'::jsonb);
  for k in select jsonb_object_keys((oa - '_em') || (na - '_em')) loop
    ot := coalesce(oe->>k, semente);
    nt := least(coalesce(ne->>k, semente),
                to_char((now() + interval '2 minutes') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
    if na ? k and nt >= ot then
      ap := ap || jsonb_build_object(k, na->k);  em := em || jsonb_build_object(k, nt);
    else
      ap := ap || jsonb_build_object(k, coalesce(oa->k, 'null'::jsonb));  em := em || jsonb_build_object(k, ot);
    end if;
  end loop;
  new.aprovacoes := ap || jsonb_build_object('_em', em);

  -- marcos do teto: união
  new.marcos := (select coalesce(jsonb_agg(v order by v), '[]'::jsonb)
                   from (select distinct v from jsonb_array_elements(coalesce(old.marcos, '[]'::jsonb) || new.marcos) v) u);

  new.semeado := coalesce(old.semeado, false) or coalesce(new.semeado, false);
  return new;
end $$;

-- a regra "a linha mais nova vence inteira" sai da tabela de meses: ela
-- pularia a atualização antes de a mescla pessoa a pessoa acontecer
drop trigger if exists tg_mais_recente  on public.ciclo;
drop trigger if exists tg_ciclo_mesclar on public.ciclo;
create trigger tg_ciclo_mesclar before insert or update on public.ciclo
  for each row execute function public.ciclo_mesclar();

-- lançamentos e transferências: mesma proteção contra relógio adiantado
create or replace function public.manter_mais_recente()
returns trigger
language plpgsql
as $$
begin
  if new.atualizado_em > now() + interval '2 minutes' then new.atualizado_em := now(); end if;
  if tg_op = 'UPDATE' and new.atualizado_em < old.atualizado_em then
    return null;
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['lancamento','transferencia'] loop
    execute format('drop trigger if exists tg_mais_recente on public.%I', t);
    execute format(
      'create trigger tg_mais_recente before insert or update on public.%I
         for each row execute function public.manter_mais_recente()', t);
  end loop;
end $$;


-- ─── 2. Um pagamento por mês ──────────────────────────────────────────────
-- Cada aparelho, desconectado, registrou o seu pagamento de outubro. Quando
-- voltarem a falar com a nuvem, os dois tentariam subir. O banco passa a
-- aceitar só um registro de pagamento por mês; os demais são ignorados em
-- silêncio — sem erro, para não travar a sincronização do aparelho.

create or replace function public.acerto_unico()
returns trigger
language plpgsql
as $$
begin
  if new.finalidade = 'acerto' and new.excluido_em is null and exists (
       select 1 from public.transferencia t
        where t.casa_id = new.casa_id
          and t.competencia = new.competencia
          and t.finalidade = 'acerto'
          and t.excluido_em is null
          and t.id <> new.id) then
    return null;
  end if;
  return new;
end $$;

drop trigger if exists tg_acerto_unico on public.transferencia;
create trigger tg_acerto_unico before insert on public.transferencia
  for each row execute function public.acerto_unico();


-- ─── 3. Reparo: outubro como de fato aconteceu ───────────────────────────
-- De acordo: as datas reais, que a nuvem preservou — Janaína 20/10 17:06,
-- Gabriel 21/10 11:42. Definitiva e pagamento em 25/10, data registrada pela
-- Janaína. A marca de agora faz os dois aparelhos adotarem esta versão no
-- lugar das que cada um montou sozinho.

update public.ciclo
   set status     = 'quitado',
       fechado_em = '2026-10-25T15:00:00Z',
       pago_em    = '2026-10-25',
       aprovacoes = '{"Janaína": "2026-10-20T20:06:25.325Z",
                      "Gabriel": "2026-10-21T14:42:14.342Z",
                      "_em": {"Janaína": "2026-10-20T20:06:25.325Z",
                              "Gabriel": "2026-10-21T14:42:14.342Z"}}'::jsonb,
       atualizado_em = now()
 where casa_id = 'casa-1' and competencia = '2026-10';

insert into public.transferencia
  (id, casa_id, competencia, de_membro, para_membro, valor_cent, data,
   finalidade, considerar, criado_por, criado_em, atualizado_em)
values
  ('acerto-2026-10', 'casa-1', '2026-10', 'Gabriel', 'Janaína', 251773, '2026-10-25',
   'acerto', true, 'Gabriel', now(), now())
on conflict (id) do nothing;


-- ─── 4. Reparo: novembro aberto e limpo ──────────────────────────────────
-- A nuvem já está assim. A marca de agora faz o celular da Janaína trocar o
-- novembro estranho que montou sozinho por esta versão.

update public.ciclo
   set status = 'aberto', previa_em = null, fechado_em = null, pago_em = null,
       aprovacoes = jsonb_build_object(
         'Janaína', null, 'Gabriel', null,
         '_em', jsonb_build_object(
           'Janaína', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
           'Gabriel', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))),
       atualizado_em = now()
 where casa_id = 'casa-1' and competencia = '2026-11';


-- ─── 5. Conferência ───────────────────────────────────────────────────────
-- Estado final dos meses, pagamentos, total de lançamentos por mês e qualquer
-- lançamento que pareça duplicado (mesma descrição e valor no mesmo mês).

select tipo, chave, detalhe from (
  select 1 as o, 'ciclo' as tipo, competencia as chave,
         status
         || ' | de acordo J ' || coalesce(to_char((aprovacoes->>'Janaína')::timestamptz at time zone 'America/Sao_Paulo','DD/MM HH24:MI'),'-')
         || ' · G '           || coalesce(to_char((aprovacoes->>'Gabriel')::timestamptz at time zone 'America/Sao_Paulo','DD/MM HH24:MI'),'-')
         || ' | definitiva '  || coalesce(to_char(fechado_em at time zone 'America/Sao_Paulo','DD/MM'),'-')
         || ' | pago '        || coalesce(to_char(pago_em,'DD/MM'),'-') as detalhe
    from public.ciclo where competencia between '2026-09' and '2026-11'
  union all
  select 2, 'pagamento', competencia,
         de_membro || ' → ' || para_membro || ' R$ ' || to_char(valor_cent / 100.0, 'FM999990.00')
         || ' em ' || to_char(data,'DD/MM')
    from public.transferencia where finalidade = 'acerto' and excluido_em is null
  union all
  select 3, 'total do mês', competencia,
         count(*) || ' lançamentos | R$ ' || to_char(sum(valor_cent) / 100.0, 'FM999990.00')
    from public.lancamento
   where excluido_em is null and escopo = 'fatura' and competencia between '2026-08' and '2026-11'
   group by competencia
  union all
  select 4, 'duplicado?', competencia,
         count(*) || 'x ' || descricao || ' R$ ' || to_char(valor_cent / 100.0, 'FM999990.00')
    from public.lancamento
   where excluido_em is null and competencia between '2026-08' and '2026-12'
   group by competencia, descricao, valor_cent
  having count(*) > 1
) x
order by o, chave, detalhe;
