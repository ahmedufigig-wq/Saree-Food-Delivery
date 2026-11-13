-- Apply the operator-approved commercial defaults to active Saree restaurants.
-- Idempotent and additive: existing orders, users, menus, and restaurant records are preserved.
update public.restaurants
set delivery_fee_yer = 100,
    minimum_order_yer = 500,
    updated_at = now()
where is_active = true;

insert into public.restaurant_hours (restaurant_id, weekday, opens_at, closes_at, is_closed)
select r.id, d.weekday, time '09:00', time '23:00', false
from public.restaurants r
cross join generate_series(0,6) as d(weekday)
where r.is_active = true
on conflict (restaurant_id, weekday)
do update set opens_at = excluded.opens_at,
              closes_at = excluded.closes_at,
              is_closed = false;

insert into public.app_remote_settings (key,value,description,is_public)
values
 ('default_delivery_fee_yer','100'::jsonb,'رسوم التوصيل الافتراضية للمتاجر النشطة بالريال اليمني',true),
 ('default_minimum_order_yer','500'::jsonb,'الحد الأدنى الافتراضي للطلب بالريال اليمني',true),
 ('default_business_hours','{"opens_at":"09:00","closes_at":"23:00","timezone":"Asia/Aden","days":[0,1,2,3,4,5,6]}'::jsonb,'ساعات العمل الافتراضية من الأحد إلى السبت بتوقيت اليمن',true),
 ('coupon_system_requested','true'::jsonb,'طلب تفعيل كوبونات الخصم؛ يتطلب تحديد قيمة الخصم ورمز الكوبون وربط واجهة إدخاله',true)
on conflict (key) do update
set value=excluded.value, description=excluded.description,
    is_public=excluded.is_public, updated_at=now();
