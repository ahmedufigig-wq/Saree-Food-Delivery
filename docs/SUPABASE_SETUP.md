# إعداد Supabase لمنصة سريع

هذه الخطوات مطلوبة لتشغيل المنصة على الإنترنت. ملفات المستودع لا تحتوي على مفاتيح أو كلمات مرور.

## 1) إنشاء مشروع
1. افتح https://supabase.com/dashboard وأنشئ مشروعًا جديدًا باسم Saree.
2. اختر أقرب منطقة متاحة مناسبة لليمن، واحتفظ بكلمة مرور قاعدة البيانات في مكان آمن.
3. من SQL Editor شغّل الملف `supabase/migrations/202611080001_initial_schema.sql`.

## 2) بيانات الربط
من Project Settings → API انسخ:
- Project URL
- Publishable key (أو anon key القديم)

هذه مفاتيح عميل عامة ومناسبة للتطبيق عند حماية الجداول بسياسات RLS. لا تضع أبدًا service_role key داخل تطبيق Flutter أو في مستودع عام.

## 3) تهيئة GitHub Actions
أضف Repository Secrets التالية من Settings → Secrets and variables → Actions:
- `SUPABASE_URL`: رابط المشروع.
- `SUPABASE_ANON_KEY`: المفتاح العام (publishable/anon).

لا تضف كلمة مرور قاعدة البيانات أو service_role key إلى إعدادات بناء APK.

## 4) إنشاء حسابات الأدوار
يسجل المستخدم أولًا عبر Supabase Auth، ويُنشأ صف ملفه تلقائيًا بدور customer. تعيين دور admin أو courier أو restaurant_owner وربط مدير المطعم بجدول restaurant_members يجب أن يتم من لوحة الإدارة الآمنة/SQL Editor، وليس من التطبيق العام.

## 5) ملاحظات قبل الإطلاق التجاري
- أضف بيانات المطاعم الحقيقية وقوائمها وأسعارها بعد موافقة أصحابها.
- اختبر صلاحيات RLS بحسابات عميل ومطعم ومندوب منفصلة.
- اضبط سياسة الخصوصية وشروط الاستخدام وآلية دعم العملاء.
- الدفع الإلكتروني غير مفعل؛ الإصدار الأول يدعم الدفع النقدي عند الاستلام فقط.
- تتبع الموقع يتطلب موافقة المندوب وإعداد صلاحيات الموقع في Android.

## 6) منح الأدوار وربط أول مطعم

بعد تسجيل الحسابات من التطبيق، استخدم SQL Editor في Supabase. استبدل البريد الإلكتروني بالقيم الحقيقية للحسابات:

```sql
-- ترقية حساب المدير الأول (نفّذها من SQL Editor فقط).
update public.profiles
set role = 'admin'
where id = (select id from auth.users where email = 'admin@example.com');

-- ترقية حساب صاحب المطعم.
update public.profiles
set role = 'restaurant_owner'
where id = (select id from auth.users where email = 'restaurant@example.com');

-- ربط صاحب المطعم بمطعم موجود بالفعل.
insert into public.restaurant_members (restaurant_id, user_id, member_role)
select '00000000-0000-0000-0000-000000000000'::uuid, id, 'manager'
from auth.users
where email = 'restaurant@example.com'
on conflict do nothing;

-- ترقية حساب المندوب.
update public.profiles
set role = 'courier'
where id = (select id from auth.users where email = 'courier@example.com');
```

أنشئ المطعم أولًا من لوحة Supabase أو بعد استكمال لوحة الإدارة، ثم استخدم معرّف المطعم الحقيقي بدل UUID المثال أعلاه. لا تمنح دور admin لأي مستخدم غير موثوق.
