-- =====================================================================
--  Racha Viagem — migração 03: fotos de nota fiscal / comprovante   (19/11/2026)
--  Só ADICIONA. Nenhum dado existente é alterado ou apagado.
--  Arquivos em: comprovantes/<id da viagem>/<id do gasto>/<id da foto>.jpg  (+ _t.jpg = miniatura)
-- =====================================================================

-- 1) lista de fotos no gasto (caminhos no Storage), no máximo 6
alter table public.expenses
  add column fotos jsonb not null default '[]'::jsonb;
alter table public.expenses
  add constraint fotos_lista check (jsonb_typeof(fotos) = 'array' and jsonb_array_length(fotos) <= 6);

-- 2) "pasta" privada no Storage: até 3 MB por arquivo, só imagens
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('comprovantes', 'comprovantes', false, 3145728, array['image/jpeg', 'image/png', 'image/webp']);

-- 3) a pessoa logada é membro da viagem dona deste arquivo? (1ª pasta do caminho = id da viagem)
create function public.is_trip_member_path(p_name text)
returns boolean language plpgsql stable security definer set search_path = ''
as $$
declare tid uuid;
begin
  begin
    tid := split_part(p_name, '/', 1)::uuid;
  exception when others then
    return false;                       -- caminho fora do padrão: nega
  end;
  return exists (select 1 from public.trip_access a where a.trip_id = tid and a.user_id = auth.uid());
end $$;
revoke execute on function public.is_trip_member_path(text) from public, anon;
grant execute on function public.is_trip_member_path(text) to authenticated;

-- 4) regras do Storage: só membros da viagem veem, enviam e apagam as fotos dela
create policy "comprovantes: membro vê" on storage.objects for select to authenticated
  using (bucket_id = 'comprovantes' and public.is_trip_member_path(name));
create policy "comprovantes: membro envia" on storage.objects for insert to authenticated
  with check (bucket_id = 'comprovantes' and public.is_trip_member_path(name));
create policy "comprovantes: membro apaga" on storage.objects for delete to authenticated
  using (bucket_id = 'comprovantes' and public.is_trip_member_path(name));

-- 5) o gatilho de validação passa a conferir também as fotos: cada caminho precisa
--    começar com "<id desta viagem>/<id deste gasto>/"
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
    if exists (select 1 from jsonb_array_elements(new.fotos) f
               where jsonb_typeof(f) <> 'string'
                  or left(f #>> '{}', 74) <> new.trip_id::text || '/' || new.id::text || '/') then
      raise exception 'foto com caminho inválido para este gasto';
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
