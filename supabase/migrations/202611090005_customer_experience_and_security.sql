-- Saree phase 2: customer engagement, restaurant operations and security hardening
begin;

create table if not exists public.favorites (
  customer_id uuid not null references public.profiles(id) on delete cascade,
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (customer_id, restaurant_id)
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text not null default '',
  is_visible boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  kind text not null default 'general',
  related_order_id uuid references public.orders(id) on delete set null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  code text unique,
  discount_type text not null check (discount_type in ('fixed','percentage')),
  discount_value integer not null check (discount_value > 0),
  minimum_order_yer integer not null default 0 check (minimum_order_yer >= 0),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at),
  check (discount_type <> 'percentage' or discount_value <= 100)
);

create table if not exists public.restaurant_hours (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),
  opens_at time,
  closes_at time,
  is_closed boolean not null default false,
  unique (restaurant_id, weekday),
  check (is_closed or (opens_at is not null and closes_at is not null and opens_at <> closes_at))
);

create index if not exists reviews_restaurant_created_idx on public.reviews(restaurant_id, created_at desc);
create index if not exists notifications_user_created_idx on public.notifications(user_id, created_at desc);
create index if not exists promotions_active_window_idx on public.promotions(is_active, starts_at, ends_at);

alter table public.favorites enable row level security;
alter table public.reviews enable row level security;
alter table public.notifications enable row level security;
alter table public.promotions enable row level security;
alter table public.restaurant_hours enable row level security;

drop policy if exists "customers manage own favorites" on public.favorites;
create policy "customers manage own favorites" on public.favorites
for all to authenticated using (customer_id = auth.uid())
with check (customer_id = auth.uid());

drop policy if exists "visible restaurant reviews" on public.reviews;
create policy "visible restaurant reviews" on public.reviews
for select to anon, authenticated using (is_visible or customer_id = auth.uid() or public.is_admin());

drop policy if exists "customers review delivered orders" on public.reviews;
create policy "customers review delivered orders" on public.reviews
for insert to authenticated with check (
  customer_id = auth.uid()
  and exists (
    select 1 from public.orders o
    where o.id = order_id and o.customer_id = auth.uid()
      and o.restaurant_id = restaurant_id and o.status = 'delivered'
  )
);

drop policy if exists "customers update own reviews" on public.reviews;
create policy "customers update own reviews" on public.reviews
for update to authenticated using (customer_id = auth.uid())
with check (customer_id = auth.uid());

drop policy if exists "users read own notifications" on public.notifications;
create policy "users read own notifications" on public.notifications
for select to authenticated using (user_id = auth.uid());

drop policy if exists "users mark own notifications read" on public.notifications;
create policy "users mark own notifications read" on public.notifications
for update to authenticated using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "active promotions public" on public.promotions;
create policy "active promotions public" on public.promotions
for select to anon, authenticated using (
  is_active and starts_at <= now() and (ends_at is null or ends_at > now())
  or public.is_admin()
);

drop policy if exists "admins manage promotions" on public.promotions;
create policy "admins manage promotions" on public.promotions
for all to authenticated using (public.is_admin())
with check (public.is_admin());

drop policy if exists "restaurant hours public" on public.restaurant_hours;
create policy "restaurant hours public" on public.restaurant_hours
for select to anon, authenticated using (
  exists (select 1 from public.restaurants r where r.id = restaurant_id and r.is_active)
  or public.is_admin() or public.is_restaurant_member(restaurant_id)
);

drop policy if exists "restaurant managers manage hours" on public.restaurant_hours;
create policy "restaurant managers manage hours" on public.restaurant_hours
for all to authenticated using (public.is_admin() or public.is_restaurant_member(restaurant_id))
with check (public.is_admin() or public.is_restaurant_member(restaurant_id));

alter function public.set_updated_at() set search_path = public, pg_temp;

-- Trigger-only function: prevent direct invocation through the Data API.
revoke all on function public.handle_new_user() from public, anon, authenticated;
grant execute on function public.handle_new_user() to service_role;

commit;
