-- Saree cashier workflow schema reference.
-- The corresponding changes have already been applied to Supabase project
-- zfhqprnsrcxahzvwevse. This file is a reference for future environments.
-- Cashiers remain normal customer auth profiles and are linked via
-- restaurant_members.member_role = 'staff'; no auth role constraint is changed.

create table if not exists public.restaurant_cashier_applications (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  applicant_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  full_name text not null default '',
  phone text not null default '',
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id)
);
alter table public.restaurant_cashier_applications enable row level security;
create index if not exists restaurant_cashier_applications_restaurant_status_idx
  on public.restaurant_cashier_applications (restaurant_id, status, created_at desc);
create index if not exists restaurant_members_user_role_idx
  on public.restaurant_members (user_id, member_role);
create unique index if not exists restaurant_cashier_applications_one_pending_idx
  on public.restaurant_cashier_applications (restaurant_id, applicant_id) where status = 'pending';

drop policy if exists "cashier applicants read own requests" on public.restaurant_cashier_applications;
create policy "cashier applicants read own requests" on public.restaurant_cashier_applications
for select to authenticated using (applicant_id = (select auth.uid()) or public.is_admin());

drop policy if exists "restaurant managers read cashier requests" on public.restaurant_cashier_applications;
create policy "restaurant managers read cashier requests" on public.restaurant_cashier_applications
for select to authenticated using (
  exists (select 1 from public.restaurant_members rm
    where rm.restaurant_id = restaurant_cashier_applications.restaurant_id
      and rm.user_id = (select auth.uid()) and rm.member_role = 'manager')
);

drop policy if exists "users request cashier membership" on public.restaurant_cashier_applications;
create policy "users request cashier membership" on public.restaurant_cashier_applications
for insert to authenticated with check (
  applicant_id = (select auth.uid()) and status = 'pending'
  and exists (select 1 from public.profiles p where p.id = (select auth.uid())
    and p.role = 'customer' and p.approval_status = 'approved' and not p.is_blocked)
  and exists (select 1 from public.restaurants r where r.id = restaurant_cashier_applications.restaurant_id and r.is_active)
  and not exists (select 1 from public.restaurant_members rm
    where rm.restaurant_id = restaurant_cashier_applications.restaurant_id and rm.user_id = (select auth.uid()))
);

drop policy if exists "restaurant managers review cashier requests" on public.restaurant_cashier_applications;
create policy "restaurant managers review cashier requests" on public.restaurant_cashier_applications
for update to authenticated
using (public.is_admin() or exists (
  select 1 from public.restaurant_members rm where rm.restaurant_id = restaurant_cashier_applications.restaurant_id
    and rm.user_id = (select auth.uid()) and rm.member_role = 'manager'))
with check (status in ('accepted','rejected') and (
  public.is_admin() or (reviewed_by = (select auth.uid()) and exists (
    select 1 from public.restaurant_members rm where rm.restaurant_id = restaurant_cashier_applications.restaurant_id
      and rm.user_id = (select auth.uid()) and rm.member_role = 'manager'))
));

create or replace function public.link_accepted_cashier_to_restaurant()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_name text; v_phone text;
begin
  if tg_op = 'UPDATE' and (new.restaurant_id is distinct from old.restaurant_id or new.applicant_id is distinct from old.applicant_id) then
    raise exception 'لا يمكن تغيير صاحب الطلب أو المطعم المرتبط به';
  end if;
  if tg_op = 'INSERT' then
    select p.full_name, coalesce(p.phone,'') into v_name, v_phone
    from public.profiles p where p.id = new.applicant_id and p.role = 'customer'
      and p.approval_status = 'approved' and not p.is_blocked;
    if v_name is null then raise exception 'حساب الكاشير غير مؤهل للانضمام'; end if;
    new.full_name := v_name; new.phone := v_phone;
  elsif new.status = 'accepted' and old.status is distinct from new.status then
    if not exists (select 1 from public.profiles p where p.id = new.applicant_id
      and p.role = 'customer' and p.approval_status = 'approved' and not p.is_blocked) then
      raise exception 'حساب الكاشير غير مؤهل للانضمام';
    end if;
    if exists (select 1 from public.restaurant_members rm where rm.user_id = new.applicant_id
      and rm.member_role = 'staff' and rm.restaurant_id <> new.restaurant_id) then
      raise exception 'هذا الحساب مرتبط بالفعل بمطعم آخر ككاشير';
    end if;
    insert into public.restaurant_members (restaurant_id,user_id,member_role)
      values (new.restaurant_id,new.applicant_id,'staff') on conflict (restaurant_id,user_id) do nothing;
    new.reviewed_at := now();
  elsif new.status = 'rejected' and old.status is distinct from new.status then
    new.reviewed_at := now();
  end if;
  return new;
end; $$;
revoke all on function public.link_accepted_cashier_to_restaurant() from public, anon, authenticated;
drop trigger if exists link_accepted_cashier_to_restaurant on public.restaurant_cashier_applications;
create trigger link_accepted_cashier_to_restaurant before insert or update of status
on public.restaurant_cashier_applications for each row execute function public.link_accepted_cashier_to_restaurant();

create or replace function public.cashier_set_order_status(p_order_id uuid,p_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_restaurant_id uuid; v_current_status text;
begin
  if auth.uid() is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if p_status not in ('accepted','preparing','ready_for_pickup') then raise exception 'حالة الطلب غير مسموحة للكاشير'; end if;
  select o.restaurant_id,o.status::text into v_restaurant_id,v_current_status
    from public.orders o where o.id = p_order_id for update;
  if v_restaurant_id is null then raise exception 'الطلب غير موجود'; end if;
  if not exists (select 1 from public.restaurant_members rm where rm.restaurant_id = v_restaurant_id
    and rm.user_id = auth.uid() and rm.member_role = 'staff') then raise exception 'ليس لديك صلاحية إدارة طلبات هذا المطعم'; end if;
  if not exists (select 1 from public.profiles p where p.id = auth.uid()
    and p.approval_status = 'approved' and not p.is_blocked) then raise exception 'الحساب غير مفعل'; end if;
  if not ((v_current_status = 'pending' and p_status = 'accepted')
    or (v_current_status = 'accepted' and p_status = 'preparing')
    or (v_current_status = 'preparing' and p_status = 'ready_for_pickup')) then
    raise exception 'لا يمكن نقل الطلب من الحالة الحالية إلى الحالة المطلوبة';
  end if;
  update public.orders set status = p_status::public.order_status, updated_at = now()
    where id = p_order_id and restaurant_id = v_restaurant_id;
end; $$;
revoke all on function public.cashier_set_order_status(uuid,text) from public, anon;
grant execute on function public.cashier_set_order_status(uuid,text) to authenticated;

-- Cashiers may read orders through existing restaurant-member SELECT policies.
-- Direct order updates remain limited to managers, admins and assigned couriers.
drop policy if exists "restaurant and courier update assigned orders" on public.orders;
drop policy if exists "restaurant managers and couriers update assigned orders" on public.orders;
create policy "restaurant managers and couriers update assigned orders" on public.orders
for update to authenticated using (
  public.is_admin()
  or (exists (select 1 from public.restaurant_members rm where rm.restaurant_id = orders.restaurant_id
      and rm.user_id = (select auth.uid()) and rm.member_role = 'manager')
    and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.approval_status = 'approved'))
  or (courier_id = (select auth.uid()) and exists (select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.role = 'courier' and p.approval_status = 'approved'))
) with check (
  public.is_admin()
  or (exists (select 1 from public.restaurant_members rm where rm.restaurant_id = orders.restaurant_id
      and rm.user_id = (select auth.uid()) and rm.member_role = 'manager')
    and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.approval_status = 'approved'))
  or (courier_id = (select auth.uid()) and exists (select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.role = 'courier' and p.approval_status = 'approved'))
);

-- Restrict restaurant catalog and settings write access to managers.
drop policy if exists "restaurant members manage categories" on public.menu_categories;
create policy "restaurant managers manage categories" on public.menu_categories for all to authenticated
using (public.is_admin() or exists (select 1 from public.restaurant_members rm where rm.restaurant_id = menu_categories.restaurant_id and rm.user_id = (select auth.uid()) and rm.member_role = 'manager'))
with check (public.is_admin() or exists (select 1 from public.restaurant_members rm where rm.restaurant_id = menu_categories.restaurant_id and rm.user_id = (select auth.uid()) and rm.member_role = 'manager'));

drop policy if exists "restaurant members manage menu" on public.menu_items;
create policy "restaurant managers manage menu" on public.menu_items for all to authenticated
using (public.is_admin() or exists (select 1 from public.restaurant_members rm where rm.restaurant_id = menu_items.restaurant_id and rm.user_id = (select auth.uid()) and rm.member_role = 'manager'))
with check (public.is_admin() or exists (select 1 from public.restaurant_members rm where rm.restaurant_id = menu_items.restaurant_id and rm.user_id = (select auth.uid()) and rm.member_role = 'manager'));

drop policy if exists "restaurant members manage own promotions" on public.promotions;
create policy "restaurant managers manage own promotions" on public.promotions for all to authenticated
using (public.is_admin() or (restaurant_id is not null and exists (select 1 from public.restaurant_members rm where rm.restaurant_id = promotions.restaurant_id and rm.user_id = (select auth.uid()) and rm.member_role = 'manager')))
with check (public.is_admin() or (restaurant_id is not null and exists (select 1 from public.restaurant_members rm where rm.restaurant_id = promotions.restaurant_id and rm.user_id = (select auth.uid()) and rm.member_role = 'manager')));

drop policy if exists "promotion_items_manage_restaurant" on public.promotion_menu_items;
create policy "promotion_items_manage_restaurant_managers" on public.promotion_menu_items for all to authenticated
using (public.is_admin() or exists (select 1 from public.promotions p join public.restaurant_members rm on rm.restaurant_id = p.restaurant_id where p.id = promotion_menu_items.promotion_id and rm.user_id = (select auth.uid()) and rm.member_role = 'manager'))
with check (public.is_admin() or exists (select 1 from public.promotions p join public.restaurant_members rm on rm.restaurant_id = p.restaurant_id where p.id = promotion_menu_items.promotion_id and rm.user_id = (select auth.uid()) and rm.member_role = 'manager'));

drop policy if exists "restaurant managers manage hours" on public.restaurant_hours;
create policy "restaurant managers manage hours" on public.restaurant_hours for all to authenticated
using (public.is_admin() or exists (select 1 from public.restaurant_members rm where rm.restaurant_id = restaurant_hours.restaurant_id and rm.user_id = (select auth.uid()) and rm.member_role = 'manager'))
with check (public.is_admin() or exists (select 1 from public.restaurant_members rm where rm.restaurant_id = restaurant_hours.restaurant_id and rm.user_id = (select auth.uid()) and rm.member_role = 'manager'));

drop policy if exists "restaurant managers update" on public.restaurants;
create policy "restaurant managers update" on public.restaurants for update to authenticated
using (public.is_admin() or (exists (select 1 from public.restaurant_members rm where rm.restaurant_id = restaurants.id and rm.user_id = (select auth.uid()) and rm.member_role = 'manager') and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.approval_status = 'approved')))
with check (public.is_admin() or (exists (select 1 from public.restaurant_members rm where rm.restaurant_id = restaurants.id and rm.user_id = (select auth.uid()) and rm.member_role = 'manager') and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.approval_status = 'approved')));

-- The existing transition RPC is retained for owners/admins/customers/couriers,
-- but its restaurant branch explicitly requires a manager membership.
