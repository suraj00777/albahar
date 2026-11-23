-- Hotel Al-Bahar — run once in Supabase → SQL Editor → New query → Run.
create table if not exists public.orders (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  customer_name text not null,
  phone text not null,
  order_type text not null,
  address text, table_no text, notes text,
  items jsonb not null default '[]',
  subtotal numeric not null default 0,
  delivery_fee numeric not null default 0,
  total numeric not null default 0,
  payment text not null default 'cod',
  status text not null default 'new'
);
create table if not exists public.menu_items (
  id text primary key, category text not null, name text not null,
  price numeric not null, veg boolean not null default false,
  available boolean not null default true, sort int not null default 0
);
-- Menu photos and descriptions (the site maps desc <-> description)
alter table public.menu_items add column if not exists description text;
alter table public.menu_items add column if not exists img text;
create table if not exists public.settings (key text primary key, value jsonb);

alter table public.orders enable row level security;
alter table public.menu_items enable row level security;
alter table public.settings enable row level security;

drop policy if exists "staff orders" on public.orders;
create policy "staff orders" on public.orders for all to authenticated using (true) with check (true);
drop policy if exists "read menu" on public.menu_items;
create policy "read menu" on public.menu_items for select to anon, authenticated using (true);
drop policy if exists "staff menu" on public.menu_items;
create policy "staff menu" on public.menu_items for all to authenticated using (true) with check (true);
drop policy if exists "read settings" on public.settings;
create policy "read settings" on public.settings for select to anon, authenticated using (true);
drop policy if exists "staff settings" on public.settings;
create policy "staff settings" on public.settings for all to authenticated using (true) with check (true);

-- Customers place and track orders through these two functions, so they never see other orders.
create or replace function public.place_order(o jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare new_id bigint;
begin
  if coalesce((select value::text from settings where key = 'accepting'), 'true') = 'false' then
    raise exception 'Online orders are paused';
  end if;
  insert into orders (customer_name, phone, order_type, address, table_no, notes, items,
                      subtotal, delivery_fee, total, payment, status)
  values (o->>'customer_name', o->>'phone', o->>'order_type', o->>'address', o->>'table_no',
          o->>'notes', coalesce(o->'items', '[]'::jsonb), (o->>'subtotal')::numeric,
          (o->>'delivery_fee')::numeric, (o->>'total')::numeric,
          coalesce(o->>'payment', 'cod'), 'new')
  returning id into new_id;
  return new_id;
end $$;
grant execute on function public.place_order(jsonb) to anon, authenticated;

create or replace function public.track_order(p_id bigint, p_phone text)
returns table (id bigint, status text, created_at timestamptz, order_type text, total numeric, items jsonb)
language sql security definer set search_path = public as $$
  select o.id, o.status, o.created_at, o.order_type, o.total, o.items
  from orders o where o.id = p_id and o.phone = p_phone
$$;
grant execute on function public.track_order(bigint, text) to anon, authenticated;

-- Live order alerts in the admin panel
alter publication supabase_realtime add table public.orders;
