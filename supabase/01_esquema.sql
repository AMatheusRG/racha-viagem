-- =====================================================================
--  Racha Viagem — banco de dados (Supabase / PostgreSQL)   v1 · 16/11/2026
--  Como usar: Supabase → SQL Editor → New query → cole tudo → Run.
--  Pode rodar de novo sem problema? NÃO (cria tabelas). Rode uma vez só.
-- =====================================================================
--  Ideia geral de segurança
--  • Ninguém lê nada de uma viagem sem estar em trip_access (é "membro").
--  • Para virar membro só existe um caminho: a função join_trip(código),
--    chamada pelo link/código de convite. Não dá para listar viagens.
--  • Criar viagem também só pela função create_trip (já te põe como dono).
--  • Valores em CENTAVOS (bigint) — nunca float para dinheiro.
-- =====================================================================

-- ---------- Tabelas ---------------------------------------------------

create table public.trips (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  name        text not null check (char_length(name) between 1 and 80),
  emoji       text not null default '🧳' check (char_length(emoji) <= 16),
  ini         date,
  fim         date,
  orc         jsonb not null default '{}'::jsonb,           -- orçamento {categoria: centavos}
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- quem tem ACESSO à viagem (contas)
create table public.trip_access (
  trip_id    uuid not null references public.trips(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       text not null default 'member' check (role in ('owner','member')),
  joined_at  timestamptz not null default now(),
  primary key (trip_id, user_id)
);

-- PESSOAS da viagem (podem ou não ter conta — ex.: a avó)
create table public.trip_members (
  id          uuid primary key default gen_random_uuid(),
  trip_id     uuid not null references public.trips(id) on delete cascade,
  nome        text not null check (char_length(nome) between 1 and 40),
  cota        numeric(4,1) not null default 1 check (cota >= 0 and cota <= 10),
  pix         text not null default '' check (char_length(pix) <= 120),
  tel         text not null default '' check (char_length(tel) <= 30),
  cor         smallint not null default 0 check (cor between 0 and 9),
  user_id     uuid references auth.users(id) on delete set null,   -- "quem sou eu"
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index trip_members_um_por_conta on public.trip_members(trip_id, user_id) where user_id is not null;

-- gastos (tipo 'g') e pagamentos de acerto (tipo 'p')
create table public.expenses (
  id          uuid primary key default gen_random_uuid(),
  trip_id     uuid not null references public.trips(id) on delete cascade,
  tipo        text not null default 'g' check (tipo in ('g','p')),
  descr       text not null default '' check (char_length(descr) <= 120),
  cat         text not null default 'outros' check (cat in ('mercado','bebidas','combustivel','hospedagem','restaurante','transporte','passeios','contas','outros')),
  valor       bigint not null check (valor > 0 and valor <= 10000000000),   -- centavos (até R$ 100 mi)
  pagou       uuid references public.trip_members(id),
  de          uuid references public.trip_members(id),
  para        uuid references public.trip_members(id),
  data        date not null default current_date,
  modo        text check (modo in ('igual','cota','itens','manual','depois')),
  part        jsonb not null default '[]'::jsonb,   -- [id de pessoa]
  man         jsonb not null default '{}'::jsonb,   -- {id: centavos}
  itens       jsonb not null default '[]'::jsonb,   -- [{id, desc, valor, part:[...]}]
  cotas       boolean not null default false,
  item_id     uuid,                                  -- item da lista que gerou o gasto
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint gasto_ou_pagamento check (
    (tipo = 'g' and pagou is not null and modo is not null)
    or (tipo = 'p' and de is not null and para is not null and de <> para)
  ),
  constraint json_formatos check (jsonb_typeof(part) = 'array' and jsonb_typeof(man) = 'object' and jsonb_typeof(itens) = 'array')
);
create index on public.expenses(trip_id);

-- lista de provisões
create table public.items (
  id          uuid primary key default gen_random_uuid(),
  trip_id     uuid not null references public.trips(id) on delete cascade,
  nome        text not null check (char_length(nome) between 1 and 80),
  qtd         text not null default '' check (char_length(qtd) <= 40),
  cat         text not null default 'outros' check (cat in ('mercado','bebidas','combustivel','hospedagem','restaurante','transporte','passeios','contas','outros')),
  resp        uuid references public.trip_members(id) on delete set null,
  status      text not null default 'pend' check (status in ('pend','ok')),
  gasto_id    uuid references public.expenses(id) on delete set null,
  ord         integer not null default 0,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index on public.items(trip_id);
alter table public.expenses add constraint expenses_item_fk foreign key (item_id) references public.items(id) on delete set null;
create index on public.trip_members(trip_id);

-- sugestões (botão 💬). Só entram; você lê no Table Editor.
create table public.suggestions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  tipo        text not null check (tipo in ('ideia','bug','elogio')),
  txt         text not null check (char_length(txt) between 1 and 2000),
  nome        text not null default '' check (char_length(nome) <= 60),
  tela        text not null default '' check (char_length(tela) <= 40),
  ua          text not null default '' check (char_length(ua) <= 200),
  v           text not null default '' check (char_length(v) <= 20),
  lida        boolean not null default false,
  created_at  timestamptz not null default now()
);

-- ---------- Funções auxiliares ----------------------------------------

-- a conta logada é membro da viagem? (usada em todas as regras)
create function public.is_trip_member(p_trip uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.trip_access a where a.trip_id = p_trip and a.user_id = auth.uid());
$$;

-- código de convite: 8 caracteres sem 0/O/1/I (32^8 ≈ 1 trilhão de combinações)
create function public.gen_trip_code()
returns text language plpgsql volatile security definer set search_path = ''
as $$
declare
  alfabeto constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  b bytea; c text;
begin
  loop
    b := extensions.gen_random_bytes(8);          -- aleatório criptográfico
    c := '';
    for i in 0..7 loop
      c := c || substr(alfabeto, (get_byte(b, i) % 32) + 1, 1);   -- 256 é múltiplo de 32: sem viés
    end loop;
    exit when not exists (select 1 from public.trips t where t.code = c);
  end loop;
  return c;
end $$;

-- carimba autor/datas e impede mudar a viagem de um registro
create function public.tg_meta()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if tg_table_name <> 'trip_members' then new.created_by := auth.uid(); end if;
    new.created_at := now();
  else
    if tg_table_name <> 'trips' and (to_jsonb(new)->>'trip_id') is distinct from (to_jsonb(old)->>'trip_id') then
      raise exception 'trip_id não pode mudar';
    end if;
    if tg_table_name <> 'trip_members' then new.created_by := old.created_by; end if;
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end $$;

-- pessoas citadas num gasto/item precisam ser da MESMA viagem
create function public.tg_mesma_viagem()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare ids uuid[];
begin
  if tg_table_name = 'expenses' then ids := array_remove(array[new.pagou, new.de, new.para], null);
  else ids := array_remove(array[new.resp], null); end if;
  if exists (select 1 from unnest(ids) x where not exists
      (select 1 from public.trip_members m where m.id = x and m.trip_id = new.trip_id)) then
    raise exception 'pessoa não pertence a esta viagem';
  end if;
  return new;
end $$;

-- "quem sou eu": só posso vincular uma pessoa à MINHA conta (ou desvincular)
create function public.tg_member_claim()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.user_id is not null
     and (tg_op = 'INSERT' or new.user_id is distinct from old.user_id)
     and new.user_id <> auth.uid() then
    raise exception 'só dá para vincular a própria conta';
  end if;
  return new;
end $$;

create trigger meta  before insert or update on public.trips        for each row execute function public.tg_meta();
create trigger meta  before insert or update on public.trip_members for each row execute function public.tg_meta();
create trigger meta  before insert or update on public.expenses     for each row execute function public.tg_meta();
create trigger meta  before insert or update on public.items        for each row execute function public.tg_meta();
create trigger mesma_viagem before insert or update on public.expenses for each row execute function public.tg_mesma_viagem();
create trigger mesma_viagem before insert or update on public.items    for each row execute function public.tg_mesma_viagem();
create trigger claim before insert or update of user_id on public.trip_members for each row execute function public.tg_member_claim();

-- ---------- Funções chamadas pelo app (RPC) ---------------------------

-- cria a viagem + te põe como dono + cria as pessoas (você e os convidados)
create function public.create_trip(p_name text, p_emoji text, p_ini date, p_fim date, p_eu text, p_convidados text[] default '{}')
returns public.trips language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  t public.trips;
  n text; i int := 0;
begin
  if uid is null then raise exception 'precisa estar logado'; end if;
  if coalesce(array_length(p_convidados, 1), 0) > 50 then raise exception 'máximo de 50 convidados'; end if;
  if (select count(*) from public.trips x where x.created_by = uid and x.created_at > now() - interval '1 hour') >= 20 then
    raise exception 'muitas viagens criadas em pouco tempo';
  end if;
  insert into public.trips(code, name, emoji, ini, fim, created_by)
    values (public.gen_trip_code(), trim(p_name), coalesce(nullif(trim(p_emoji), ''), '🧳'), p_ini, p_fim, uid)
    returning * into t;
  insert into public.trip_access(trip_id, user_id, role) values (t.id, uid, 'owner');
  insert into public.trip_members(trip_id, nome, cor, user_id) values (t.id, left(trim(p_eu), 40), 0, uid);
  foreach n in array coalesce(p_convidados, '{}') loop
    if trim(n) <> '' then
      i := i + 1;
      insert into public.trip_members(trip_id, nome, cor) values (t.id, left(trim(n), 40), i % 10);
    end if;
  end loop;
  return t;
end $$;

-- entra na viagem pelo código/link. Devolve o id, ou null se o código não existe.
create function public.join_trip(p_code text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare uid uuid := auth.uid(); tid uuid;
begin
  if uid is null then raise exception 'precisa estar logado'; end if;
  select t.id into tid from public.trips t
   where t.code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if tid is null then return null; end if;
  insert into public.trip_access(trip_id, user_id) values (tid, uid) on conflict do nothing;
  return tid;
end $$;

-- ---------- Regras de acesso por linha (RLS) ---------------------------

alter table public.trips        enable row level security;
alter table public.trip_access  enable row level security;
alter table public.trip_members enable row level security;
alter table public.expenses     enable row level security;
alter table public.items        enable row level security;
alter table public.suggestions  enable row level security;

create policy "membro lê a viagem"        on public.trips for select to authenticated using (public.is_trip_member(id));
create policy "membro edita a viagem"     on public.trips for update to authenticated using (public.is_trip_member(id)) with check (public.is_trip_member(id));
create policy "só quem criou exclui"      on public.trips for delete to authenticated using (created_by = (select auth.uid()));

create policy "membro vê quem tem acesso" on public.trip_access for select to authenticated using (public.is_trip_member(trip_id));
create policy "sair da viagem"            on public.trip_access for delete to authenticated using (user_id = (select auth.uid()));

create policy "membro: pessoas" on public.trip_members for all to authenticated
  using (public.is_trip_member(trip_id)) with check (public.is_trip_member(trip_id));
create policy "membro: gastos"  on public.expenses     for all to authenticated
  using (public.is_trip_member(trip_id)) with check (public.is_trip_member(trip_id));
create policy "membro: itens"   on public.items        for all to authenticated
  using (public.is_trip_member(trip_id)) with check (public.is_trip_member(trip_id));

create policy "enviar sugestão" on public.suggestions for insert to authenticated with check (user_id = (select auth.uid()));

-- ---------- Permissões (nada fica exposto sem estar aqui) ---------------

revoke all on public.trips, public.trip_access, public.trip_members, public.expenses, public.items, public.suggestions from anon, authenticated;

grant select, delete on public.trips to authenticated;
grant update (name, emoji, ini, fim, orc) on public.trips to authenticated;           -- código e dono não mudam
grant select, delete on public.trip_access to authenticated;
grant select, insert, delete on public.trip_members to authenticated;
grant update (nome, cota, pix, tel, cor, user_id) on public.trip_members to authenticated;
grant select, insert, update, delete on public.expenses, public.items to authenticated;
grant insert on public.suggestions to authenticated;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.is_trip_member(uuid) to authenticated;
grant execute on function public.create_trip(text, text, date, date, text, text[]) to authenticated;
grant execute on function public.join_trip(text) to authenticated;

-- ---------- Tempo real (todos veem o gasto novo na hora) ---------------

alter publication supabase_realtime add table public.trips, public.trip_members, public.expenses, public.items;
