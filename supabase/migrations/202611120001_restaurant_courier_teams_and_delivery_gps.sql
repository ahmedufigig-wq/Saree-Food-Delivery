-- Restaurant-owned courier teams and secure order assignment.

-- Existing customer, restaurant, courier and order records are preserved.

create table if not exists public.restaurant_couriers (

  restaurant_id uuid not null references public.restaurants(id) on delete cascade,

  courier_id uuid not null references public.profiles(id) on delete cascade,

  is_active boolean not null default true,

  added_by uuid references public.profiles(id) on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  primary key (restaurant_id, courier_id)

);

create index if not exists restaurant_couriers_courier_idx on public.restaurant_couriers(courier_id, is_active);

alter table public.restaurant_couriers enable row level security;

drop policy if exists restaurant_couriers_read_team on public.restaurant_couriers;

create policy restaurant_couriers_read_team on public.restaurant_couriers

for select to authenticated using (

  courier_id = (select auth.uid()) or public.is_admin() or

  (public.is_restaurant_member(restaurant_id) and exists (

    select 1 from public.profiles p where p.id = (select auth.uid())

      and p.role = 'restaurant_owner' and p.approval_status = 'approved' and p.is_blocked = false

  ))

);

CREATE OR REPLACE FUNCTION public.assign_order_courier(p_order_id uuid, p_courier_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_restaurant_id uuid;
  v_order_number bigint;
  v_address text;
  v_lat double precision;
  v_lng double precision;
  v_restaurant_name text;
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = v_uid and p.role = 'restaurant_owner'
      and p.approval_status = 'approved' and p.is_blocked = false
  ) then raise exception 'حساب المطعم غير معتمد'; end if;

  select o.restaurant_id, o.order_number, o.delivery_address,
         o.delivery_latitude, o.delivery_longitude
    into v_restaurant_id, v_order_number, v_address, v_lat, v_lng
  from public.orders o
  where o.id = p_order_id and o.status = 'ready_for_pickup'
    and o.courier_id is null
  for update;
  if v_restaurant_id is null then
    raise exception 'الطلب غير جاهز أو تم تعيين مندوب له بالفعل';
  end if;
  if not public.is_restaurant_member(v_restaurant_id) then
    raise exception 'ليس لديك صلاحية إدارة هذا الطلب';
  end if;
  if not exists (
    select 1
    from public.restaurant_couriers rc
    join public.profiles p on p.id = rc.courier_id
    join public.courier_locations cl on cl.courier_id = p.id
    where rc.restaurant_id = v_restaurant_id
      and rc.courier_id = p_courier_id
      and rc.is_active = true
      and p.role = 'courier'
      and p.approval_status = 'approved'
      and p.is_blocked = false
      and cl.is_available = true
      and cl.updated_at >= now() - interval '15 minutes'
  ) then
    raise exception 'هذا المندوب ليس ضمن فريق المطعم أو غير متاح حاليًا';
  end if;

  update public.orders
  set courier_id = p_courier_id, status = 'assigned', updated_at = now()
  where id = p_order_id and restaurant_id = v_restaurant_id
    and status = 'ready_for_pickup' and courier_id is null;
  if not found then raise exception 'تعذر تعيين المندوب؛ ربما تم تحديث الطلب من جهاز آخر'; end if;

  select name into v_restaurant_name from public.restaurants where id = v_restaurant_id;
  insert into public.notifications(user_id,title,body,kind,related_order_id)
  values(
    p_courier_id,
    'طلب توصيل جديد من ' || coalesce(v_restaurant_name,'المطعم'),
    'تم إسناد الطلب #' || v_order_number || ' إليك. عنوان العميل: ' || coalesce(v_address,'') ||
      case when v_lat is not null and v_lng is not null
        then ' | الإحداثيات: ' || v_lat::text || ',' || v_lng::text
        else ' | لم يحدد العميل إحداثيات GPS؛ يرجى التواصل معه لتأكيد الموقع.' end,
    'delivery_assignment',
    p_order_id
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.available_couriers_for_restaurant(p_restaurant_id uuid)
 RETURNS TABLE(courier_id uuid, full_name text, phone text, last_seen timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = v_uid and p.role = 'restaurant_owner'
      and p.approval_status = 'approved' and p.is_blocked = false
  ) or not public.is_restaurant_member(p_restaurant_id) then
    raise exception 'ليس لديك صلاحية إدارة مندوبي هذا المطعم';
  end if;
  return query
  select p.id, p.full_name, p.phone, cl.updated_at
  from public.restaurant_couriers rc
  join public.profiles p on p.id = rc.courier_id
  join public.courier_locations cl on cl.courier_id = p.id
  where rc.restaurant_id = p_restaurant_id
    and rc.is_active = true
    and p.role = 'courier'
    and p.approval_status = 'approved'
    and p.is_blocked = false
    and cl.is_available = true
    and cl.updated_at >= now() - interval '15 minutes'
  order by cl.updated_at desc, p.full_name;
end;
$function$


CREATE OR REPLACE FUNCTION public.restaurant_add_courier(p_restaurant_id uuid, p_phone text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_uid uuid := auth.uid(); v_courier_id uuid; v_restaurant_name text;
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = v_uid and p.role = 'restaurant_owner'
      and p.approval_status = 'approved' and p.is_blocked = false
  ) or not public.is_restaurant_member(p_restaurant_id) then
    raise exception 'ليس لديك صلاحية إضافة مندوب لهذا المطعم';
  end if;
  select p.id into v_courier_id
  from public.profiles p
  where p.phone = trim(coalesce(p_phone, ''))
    and p.role = 'courier'
    and p.approval_status = 'approved'
    and p.is_blocked = false;
  if v_courier_id is null then
    raise exception 'لم نجد مندوبًا معتمدًا بهذا الرقم. يجب أن ينشئ المندوب حسابًا ويعتمده المدير أولاً.';
  end if;
  insert into public.restaurant_couriers(restaurant_id, courier_id, is_active, added_by)
  values(p_restaurant_id, v_courier_id, true, v_uid)
  on conflict (restaurant_id, courier_id)
  do update set is_active = true, added_by = excluded.added_by, updated_at = now();
  select name into v_restaurant_name from public.restaurants where id = p_restaurant_id;
  insert into public.notifications(user_id,title,body,kind)
  values(v_courier_id,'تمت إضافتك إلى فريق توصيل مطعم',
    'أضافك مطعم ' || coalesce(v_restaurant_name,'') || ' إلى فريق مندوبيه.',
    'restaurant_team');
  return v_courier_id;
end;
$function$


CREATE OR REPLACE FUNCTION public.restaurant_courier_team(p_restaurant_id uuid)
 RETURNS TABLE(courier_id uuid, full_name text, phone text, is_active boolean, is_available boolean, last_seen timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = v_uid and p.role = 'restaurant_owner'
      and p.approval_status = 'approved' and p.is_blocked = false
  ) or not public.is_restaurant_member(p_restaurant_id) then
    raise exception 'ليس لديك صلاحية إدارة فريق هذا المطعم';
  end if;

  return query
  select p.id, p.full_name, p.phone, rc.is_active,
         coalesce(cl.is_available and cl.updated_at >= now() - interval '15 minutes', false),
         cl.updated_at
  from public.restaurant_couriers rc
  join public.profiles p on p.id = rc.courier_id
  left join public.courier_locations cl on cl.courier_id = p.id
  where rc.restaurant_id = p_restaurant_id
  order by rc.is_active desc, p.full_name;
end;
$function$


CREATE OR REPLACE FUNCTION public.restaurant_remove_courier(p_restaurant_id uuid, p_courier_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_uid uuid := auth.uid(); v_active_order boolean;
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = v_uid and p.role = 'restaurant_owner'
      and p.approval_status = 'approved' and p.is_blocked = false
  ) or not public.is_restaurant_member(p_restaurant_id) then
    raise exception 'ليس لديك صلاحية إدارة فريق هذا المطعم';
  end if;
  select exists(
    select 1 from public.orders o
    where o.restaurant_id = p_restaurant_id and o.courier_id = p_courier_id
      and o.status in ('assigned','picked_up')
  ) into v_active_order;
  if v_active_order then
    raise exception 'لا يمكن إزالة المندوب ولديه طلب توصيل نشط';
  end if;
  update public.restaurant_couriers
  set is_active = false, updated_at = now()
  where restaurant_id = p_restaurant_id and courier_id = p_courier_id;
  if not found then raise exception 'المندوب غير موجود ضمن فريق المطعم'; end if;
end;
$function$


create or replace function public.create_order_with_gps(
  p_restaurant_id uuid,
  p_customer_name text,
  p_customer_phone text,
  p_delivery_address text,
  p_items jsonb,
  p_delivery_latitude double precision,
  p_delivery_longitude double precision,
  p_notes text default ''
)
returns uuid
language sql
security invoker
set search_path = public
as $function$
  select public.create_order(
    p_restaurant_id,
    p_customer_name,
    p_customer_phone,
    p_delivery_address,
    p_items,
    p_delivery_latitude,
    p_delivery_longitude,
    p_notes
  );
$function$;

revoke execute on function public.create_order_with_gps(uuid, text, text, text, jsonb, double precision, double precision, text) from public, anon;
grant execute on function public.create_order_with_gps(uuid, text, text, text, jsonb, double precision, double precision, text) to authenticated;

revoke execute on function public.restaurant_courier_team(uuid) from public, anon;

revoke execute on function public.restaurant_add_courier(uuid, text) from public, anon;

revoke execute on function public.restaurant_remove_courier(uuid, uuid) from public, anon;

revoke execute on function public.available_couriers_for_restaurant(uuid) from public, anon;

revoke execute on function public.assign_order_courier(uuid, uuid) from public, anon;

grant execute on function public.restaurant_courier_team(uuid) to authenticated;

grant execute on function public.restaurant_add_courier(uuid, text) to authenticated;

grant execute on function public.restaurant_remove_courier(uuid, uuid) to authenticated;

grant execute on function public.available_couriers_for_restaurant(uuid) to authenticated;

grant execute on function public.assign_order_courier(uuid, uuid) to authenticated;

