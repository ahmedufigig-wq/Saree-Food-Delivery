-- Saree Food Delivery: initial production-oriented schema
-- Apply in Supabase SQL Editor. All money values are integer YER amounts.
create extension if not exists pgcrypto;

create type public.app_role as enum ('customer', 'restaurant_owner', 'courier', 'admin');
create type public.order_status as enum ('pending', 'accepted', 'preparing', 'ready_for_pickup', 'picked_up', 'delivered', 'cancelled');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text unique,
  role public.app_role not null default 'customer',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.restaurants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null default '',
  phone text,
  address text not null default '',
  city text not null default 'رداع',
  image_url text,
  is_active boolean not null default false,
  delivery_fee_yer integer not null default 1000 check (delivery_fee_yer >= 0),
  minimum_order_yer integer not null default 0 check (minimum_order_yer >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.restaurant_members (
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  member_role text not null default 'manager' check (member_role in ('manager','staff')),
  created_at timestamptz not null default now(),
  primary key (restaurant_id, user_id)
);

create table public.menu_categories (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  name text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.menu_items (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  category_id uuid references public.menu_categories(id) on delete set null,
  name text not null,
  description text not null default '',
  price_yer integer not null check (price_yer >= 0),
  image_url text,
  is_available boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.customer_addresses (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id) on delete cascade,
  label text not null default 'المنزل',
  address_text text not null,
  area text not null default '',
  latitude double precision,
  longitude double precision,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number bigint generated always as identity unique,
  customer_id uuid not null references public.profiles(id),
  restaurant_id uuid not null references public.restaurants(id),
  courier_id uuid references public.profiles(id),
  status public.order_status not null default 'pending',
  customer_name text not null,
  customer_phone text not null,
  delivery_address text not null,
  delivery_latitude double precision,
  delivery_longitude double precision,
  subtotal_yer integer not null check (subtotal_yer >= 0),
  delivery_fee_yer integer not null check (delivery_fee_yer >= 0),
  total_yer integer not null check (total_yer = subtotal_yer + delivery_fee_yer),
  payment_method text not null default 'cash_on_delivery' check (payment_method = 'cash_on_delivery'),
  notes text not null default '',
  cancellation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  menu_item_id uuid references public.menu_items(id) on delete set null,
  item_name text not null,
  unit_price_yer integer not null check (unit_price_yer >= 0),
  quantity integer not null check (quantity > 0),
  line_total_yer integer generated always as (unit_price_yer * quantity) stored
);

create table public.courier_locations (
  courier_id uuid primary key references public.profiles(id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  is_available boolean not null default true,
  updated_at timestamptz not null default now()
);

create index orders_customer_created_idx on public.orders(customer_id, created_at desc);
create index orders_restaurant_status_idx on public.orders(restaurant_id, status, created_at desc);
create index orders_courier_status_idx on public.orders(courier_id, status, created_at desc);
create index menu_items_restaurant_idx on public.menu_items(restaurant_id, is_available);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger restaurants_updated_at before update on public.restaurants
for each row execute function public.set_updated_at();
create trigger menu_items_updated_at before update on public.menu_items
for each row execute function public.set_updated_at();
create trigger orders_updated_at before update on public.orders
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    nullif(new.raw_user_meta_data->>'phone', '')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.is_restaurant_member(target_restaurant uuid)
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.restaurant_members rm
    where rm.restaurant_id = target_restaurant and rm.user_id = auth.uid()
  );
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin');
$$;

alter table public.profiles enable row level security;
alter table public.restaurants enable row level security;
alter table public.restaurant_members enable row level security;
alter table public.menu_categories enable row level security;
alter table public.menu_items enable row level security;
alter table public.customer_addresses enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.courier_locations enable row level security;

create policy "profiles read self or admin" on public.profiles
for select to authenticated using (id = auth.uid() or public.is_admin());
create policy "profiles update self or admin" on public.profiles
for update to authenticated using (id = auth.uid() or public.is_admin())
with check (id = auth.uid() or public.is_admin());

create policy "active restaurants public" on public.restaurants
for select to anon, authenticated using (is_active = true or public.is_admin() or public.is_restaurant_member(id));
create policy "restaurant managers update" on public.restaurants
for update to authenticated using (public.is_restaurant_member(id) or public.is_admin())
with check (public.is_restaurant_member(id) or public.is_admin());
create policy "admins insert restaurants" on public.restaurants
for insert to authenticated with check (public.is_admin());
create policy "admins delete restaurants" on public.restaurants
for delete to authenticated using (public.is_admin());

create policy "members visible to self or admin" on public.restaurant_members
for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "admins manage members" on public.restaurant_members
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "categories visible for active restaurants" on public.menu_categories
for select to anon, authenticated using (
  is_active and exists (select 1 from public.restaurants r where r.id = restaurant_id and r.is_active)
  or public.is_admin() or public.is_restaurant_member(restaurant_id)
);
create policy "restaurant members manage categories" on public.menu_categories
for all to authenticated using (public.is_restaurant_member(restaurant_id) or public.is_admin())
with check (public.is_restaurant_member(restaurant_id) or public.is_admin());

create policy "available menu public" on public.menu_items
for select to anon, authenticated using (
  is_available and exists (select 1 from public.restaurants r where r.id = restaurant_id and r.is_active)
  or public.is_admin() or public.is_restaurant_member(restaurant_id)
);
create policy "restaurant members manage menu" on public.menu_items
for all to authenticated using (public.is_restaurant_member(restaurant_id) or public.is_admin())
with check (public.is_restaurant_member(restaurant_id) or public.is_admin());

create policy "customers manage own addresses" on public.customer_addresses
for all to authenticated using (customer_id = auth.uid() or public.is_admin())
with check (customer_id = auth.uid() or public.is_admin());

create policy "orders visible to participants" on public.orders
for select to authenticated using (
  customer_id = auth.uid() or courier_id = auth.uid()
  or public.is_restaurant_member(restaurant_id) or public.is_admin()
);
create policy "customers create own orders" on public.orders
for insert to authenticated with check (customer_id = auth.uid() and status = 'pending' and courier_id is null);
create policy "restaurant and courier update assigned orders" on public.orders
for update to authenticated using (
  public.is_restaurant_member(restaurant_id) or courier_id = auth.uid() or public.is_admin()
) with check (
  public.is_restaurant_member(restaurant_id) or courier_id = auth.uid() or public.is_admin()
);

create policy "order items visible to order participants" on public.order_items
for select to authenticated using (
  exists (select 1 from public.orders o where o.id = order_id and (
    o.customer_id = auth.uid() or o.courier_id = auth.uid()
    or public.is_restaurant_member(o.restaurant_id) or public.is_admin()
  ))
);
create policy "customers add items to own pending orders" on public.order_items
for insert to authenticated with check (
  exists (select 1 from public.orders o where o.id = order_id and o.customer_id = auth.uid() and o.status = 'pending')
);

create policy "couriers read own location" on public.courier_locations
for select to authenticated using (courier_id = auth.uid() or public.is_admin());
create policy "couriers manage own location" on public.courier_locations
for all to authenticated using (courier_id = auth.uid() or public.is_admin())
with check (courier_id = auth.uid() or public.is_admin());

-- Enable realtime updates for order tracking when not already included.
do $$
begin
  alter publication supabase_realtime add table public.orders;
exception when duplicate_object then
  null;
end;
$$;
