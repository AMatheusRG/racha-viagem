-- =====================================================================
--  Racha Viagem — migração 02: vários pagadores no mesmo gasto  (18/11/2026)
--  Só ADICIONA (não apaga nem muda dados existentes).
--  pagadores = {"<id da pessoa>": centavos, ...}  — vazio {} = um pagador só (coluna pagou)
-- =====================================================================

alter table public.expenses
  add column pagadores jsonb not null default '{}'::jsonb;

alter table public.expenses
  add constraint pagadores_objeto check (jsonb_typeof(pagadores) = 'object');

-- regra "pessoas da mesma viagem" agora também confere os pagadores e a soma
create or replace function public.tg_mesma_viagem()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare ids uuid[]; soma numeric;
begin
  if tg_table_name = 'expenses' then
    ids := array_remove(array[new.pagou, new.de, new.para], null);
    if new.pagadores <> '{}'::jsonb then
      if new.tipo <> 'g' then raise exception 'pagamento de acerto não tem vários pagadores'; end if;
      if exists (select 1 from jsonb_each(new.pagadores) e
                 where jsonb_typeof(e.value) <> 'number'
                    or (e.value)::text::numeric <= 0
                    or (e.value)::text::numeric <> trunc((e.value)::text::numeric)) then
        raise exception 'valor de pagador inválido (precisa ser centavos > 0)';
      end if;
      select sum((value)::text::numeric) into soma from jsonb_each(new.pagadores);
      if soma <> new.valor then raise exception 'a soma dos pagadores (%) é diferente do total (%)', soma, new.valor; end if;
      if not (new.pagadores ? new.pagou::text) then raise exception 'quem pagou precisa estar entre os pagadores'; end if;
      ids := ids || array(select k::uuid from jsonb_object_keys(new.pagadores) k);
    end if;
  else
    ids := array_remove(array[new.resp], null);
  end if;
  if exists (select 1 from unnest(ids) x where not exists
      (select 1 from public.trip_members m where m.id = x and m.trip_id = new.trip_id)) then
    raise exception 'pessoa não pertence a esta viagem';
  end if;
  return new;
end $$;
