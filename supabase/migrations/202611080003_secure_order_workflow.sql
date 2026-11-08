-- Secure transactional order creation and role-based status transitions.
-- Prevent customers from promoting themselves to privileged roles.
revoke update on public.profiles from authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

-- Orders must be created through the validated RPC below, never by trusting client totals.
drop policy if exists "customers create own orders" on public.orders;
drop policy if exists "restaurant and courier update assigned orders" on public.orders;
drop policy if exists "customers add items to own pending orders" on public.order_items;
revoke insert, update, delete on public.orders from authenticated;
revoke insert, update, delete on public.order_items from authenticated;

create or replace function public.create_order(
  p_restaurant_id uuid,
  p_customer_name text,
  p_customer_phone text,
  p_delivery_address text,
  p_items jsonb,
  p_notes text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_order_id uuid;
  v_subtotal integer := 0;
  v_delivery_fee integer;
  v_item jsonb;
  v_menu_item public.menu_items%rowtype;
  v_qty integer;
begin
  if v_user is null then raise exception 'يجب تسجيل الدخول أولاً'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'السلة فارغة';
  end if;
  if length(trim(coalesce(p_customer_name, ''))) < 2
     or length(trim(coalesce(p_customer_phone, ''))) < 7
     or length(trim(coalesce(p_delivery_address, ''))) < 5 then
    raise exception 'بيانات التوصيل غير مكتملة';
  end if;

  if not exists (select 1 from public.restaurants r where r.id = p_restaurant_id and r.is_active) then
    raise exception 'المطعم غير متاح حالياً';
  end if;

  select r.delivery_fee_yer into v_delivery_fee
  from public.restaurants r where r.id = p_restaurant_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item->>'quantity')::integer;
    if v_qty < 1 or v_qty > 50 then raise exception 'كمية غير صالحة'; end if;

    select * into v_menu_item
    from public.menu_items mi
    where mi.id = (v_item->>'menu_item_id')::uuid
      and mi.restaurant_id = p_restaurant_id
      and mi.is_available
    for share;

    if not found then raise exception 'إحدى الوجبات لم تعد متاحة'; end if;
    v_subtotal := v_subtotal + (v_menu_item.price_yer * v_qty);
  end loop;

  insert into public.orders (
    customer_id, restaurant_id, status, customer_name, customer_phone,
    delivery_address, subtotal_yer, delivery_fee_yer, total_yer,
    payment_method, notes
  ) values (
    v_user, p_restaurant_id, 'pending', trim(p_customer_name),
    trim(p_customer_phone), trim(p_delivery_address), v_subtotal,
    v_delivery_fee, v_subtotal + v_delivery_fee, 'cash_on_delivery',
    coalesce(p_notes, '')
  ) returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item->>'quantity')::integer;
    select * into v_menu_item from public.menu_items
    where id = (v_item->>'menu_item_id')::uuid and restaurant_id = p_restaurant_id;
    insert into public.order_items(order_id, menu_item_id, item_name, unit_price_yer, quantity)
    values (v_order_id, v_menu_item.id, v_menu_item.name, v_menu_item.price_yer, v_qty);
  end loop;

  return v_order_id;
end;
$$;

create or replace function public.transition_order(
  p_order_id uuid,
  p_next_status public.order_status,
  p_cancellation_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_role public.app_role;
  v_is_restaurant boolean;
  v_admin boolean;
begin
  if auth.uid() is null then raise exception 'يجب تسجيل الدخول'; end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'الطلب غير موجود'; end if;

  select role into v_role from public.profiles where id = auth.uid();
  v_admin := coalesce(v_role = 'admin', false);
  v_is_restaurant := public.is_restaurant_member(v_order.restaurant_id);

  if v_admin then
    update public.orders set status = p_next_status,
      cancellation_reason = case when p_next_status = 'cancelled' then p_cancellation_reason else cancellation_reason end
    where id = p_order_id;
    return;
  end if;

  if v_order.customer_id = auth.uid() and v_order.status = 'pending' and p_next_status = 'cancelled' then
    update public.orders set status = 'cancelled',
      cancellation_reason = coalesce(p_cancellation_reason, 'ألغاه العميل')
    where id = p_order_id;
    return;
  end if;

  if v_is_restaurant and (
    (v_order.status = 'pending' and p_next_status in ('accepted','cancelled')) or
    (v_order.status = 'accepted' and p_next_status = 'preparing') or
    (v_order.status = 'preparing' and p_next_status = 'ready_for_pickup')
  ) then
    update public.orders set status = p_next_status,
      cancellation_reason = case when p_next_status = 'cancelled' then p_cancellation_reason else cancellation_reason end
    where id = p_order_id;
    return;
  end if;

  if v_order.courier_id = auth.uid() and v_role = 'courier' and (
    (v_order.status = 'assigned' and p_next_status = 'picked_up') or
    (v_order.status = 'picked_up' and p_next_status = 'delivered')
  ) then
    update public.orders set status = p_next_status where id = p_order_id;
    return;
  end if;

  raise exception 'ليس لديك صلاحية لتنفيذ هذا التغيير أو أن انتقال الحالة غير مسموح';
end;
$$;

create or replace function public.claim_delivery_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.app_role;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is distinct from 'courier' then raise exception 'هذه الخدمة للمندوبين فقط'; end if;

  update public.orders
  set courier_id = auth.uid(), status = 'assigned'
  where id = p_order_id and status = 'ready_for_pickup' and courier_id is null;

  if not found then raise exception 'الطلب غير متاح أو استلمه مندوب آخر'; end if;
end;
$$;

create policy "couriers can see ready orders" on public.orders
for select to authenticated using (
  status = 'ready_for_pickup'
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'courier')
);

grant execute on function public.create_order(uuid,text,text,text,jsonb,text) to authenticated;
grant execute on function public.transition_order(uuid,public.order_status,text) to authenticated;
grant execute on function public.claim_delivery_order(uuid) to authenticated;
revoke all on function public.create_order(uuid,text,text,text,jsonb,text) from public, anon;
revoke all on function public.transition_order(uuid,public.order_status,text) from public, anon;
revoke all on function public.claim_delivery_order(uuid) from public, anon;
