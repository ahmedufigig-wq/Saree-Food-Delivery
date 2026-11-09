-- Applied to the Saree Supabase project on 2026-11-09.
-- Starting prices approved by the user (lowest value in each supplied range).
update public.menu_items
set price_yer = case name
  when 'مندي دجاج' then 3500 when 'مندي لحم' then 7000 when 'البرم' then 7000
  when 'السلتة اليمنية' then 2000 when 'الفحسة اليمنية' then 2500 when 'الملوج الساخن' then 300
  when 'البروست والدجاج المقرمش' then 3500 when 'جمبري بروست مقرمش' then 5000
  when 'البرجر' then 1500 when 'الشاورما' then 1000 when 'السمك الطازج' then 4500
  when 'الجمبري والمأكولات البحرية' then 5500 when 'البيتزا' then 3500 when 'تشكيلة الحلويات' then 1500
  else price_yer end,
updated_at = now()
where restaurant_id = '3b0368c3-376e-4b18-8479-4bb69c36e155';

create or replace function public.create_order(
  p_restaurant_id uuid, p_customer_name text, p_customer_phone text,
  p_delivery_address text, p_items jsonb, p_notes text default ''
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_restaurant public.restaurants%rowtype;
  v_order_id uuid;
  v_item jsonb;
  v_menu public.menu_items%rowtype;
  v_qty integer;
  v_subtotal integer := 0;
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول أولاً'; end if;
  if length(trim(coalesce(p_customer_name,''))) < 2 then raise exception 'اسم المستلم غير صحيح'; end if;
  if length(trim(coalesce(p_customer_phone,''))) < 7 then raise exception 'رقم الهاتف غير صحيح'; end if;
  if length(trim(coalesce(p_delivery_address,''))) < 5 then raise exception 'عنوان التوصيل غير مكتمل'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'السلة فارغة'; end if;
  select * into v_restaurant from public.restaurants where id=p_restaurant_id and is_active=true for share;
  if not found then raise exception 'المطعم غير متاح حالياً'; end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    if coalesce(v_item->>'menu_item_id','') = '' then raise exception 'يوجد صنف غير صالح في السلة'; end if;
    v_qty := (v_item->>'quantity')::integer;
    if v_qty < 1 or v_qty > 50 then raise exception 'كمية الصنف غير صالحة'; end if;
    select * into v_menu from public.menu_items
    where id=(v_item->>'menu_item_id')::uuid and restaurant_id=p_restaurant_id and is_available=true and price_yer>0 for share;
    if not found then raise exception 'أحد الأصناف لم يعد متاحاً للطلب'; end if;
    v_subtotal := v_subtotal + v_menu.price_yer * v_qty;
  end loop;
  insert into public.orders(customer_id,restaurant_id,status,customer_name,customer_phone,delivery_address,
    subtotal_yer,delivery_fee_yer,total_yer,payment_method,notes)
  values(v_uid,p_restaurant_id,'pending',trim(p_customer_name),trim(p_customer_phone),trim(p_delivery_address),
    v_subtotal,v_restaurant.delivery_fee_yer,v_subtotal+v_restaurant.delivery_fee_yer,'cash_on_delivery',coalesce(p_notes,''))
  returning id into v_order_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    select * into v_menu from public.menu_items where id=(v_item->>'menu_item_id')::uuid and restaurant_id=p_restaurant_id;
    insert into public.order_items(order_id,menu_item_id,item_name,unit_price_yer,quantity)
    values(v_order_id,v_menu.id,v_menu.name,v_menu.price_yer,v_qty);
  end loop;
  return v_order_id;
end; $$;

create or replace function public.transition_order(
  p_order_id uuid, p_next_status public.order_status, p_cancellation_reason text default null
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders%rowtype;
  v_uid uuid := auth.uid();
  v_allowed boolean := false;
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found then raise exception 'الطلب غير موجود'; end if;
  if v_order.customer_id=v_uid then
    v_allowed := v_order.status='pending' and p_next_status='cancelled';
  elsif public.is_restaurant_member(v_order.restaurant_id) or public.is_admin() then
    v_allowed := (v_order.status='pending' and p_next_status in ('accepted','cancelled'))
      or (v_order.status='accepted' and p_next_status='preparing')
      or (v_order.status='preparing' and p_next_status='ready_for_pickup');
  elsif v_order.courier_id=v_uid then
    v_allowed := (v_order.status='assigned' and p_next_status='picked_up')
      or (v_order.status='picked_up' and p_next_status='delivered');
  end if;
  if not v_allowed then raise exception 'لا يمكن تغيير حالة الطلب بهذه الصلاحية أو من هذه الحالة'; end if;
  update public.orders set status=p_next_status,
    cancellation_reason=case when p_next_status='cancelled' then coalesce(nullif(trim(p_cancellation_reason),''),'تم إلغاء الطلب') else cancellation_reason end,
    updated_at=now() where id=p_order_id;
end; $$;

create or replace function public.claim_delivery_order(p_order_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'يرجى تسجيل الدخول'; end if;
  if not exists(select 1 from public.profiles where id=v_uid and role='courier') then raise exception 'هذه العملية متاحة للمندوب فقط'; end if;
  update public.orders set courier_id=v_uid,status='assigned',updated_at=now()
  where id=p_order_id and status='ready_for_pickup' and courier_id is null;
  if not found then raise exception 'الطلب لم يعد متاحاً للاستلام'; end if;
end; $$;

revoke all on function public.create_order(uuid,text,text,text,jsonb,text) from public,anon;
revoke all on function public.transition_order(uuid,public.order_status,text) from public,anon;
revoke all on function public.claim_delivery_order(uuid) from public,anon;
grant execute on function public.create_order(uuid,text,text,text,jsonb,text) to authenticated;
grant execute on function public.transition_order(uuid,public.order_status,text) to authenticated;
grant execute on function public.claim_delivery_order(uuid) to authenticated;
