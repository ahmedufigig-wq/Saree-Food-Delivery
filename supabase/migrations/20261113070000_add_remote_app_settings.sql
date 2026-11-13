-- Additive remote configuration foundation for Saree.
-- This migration does not alter or delete existing customer, restaurant, courier, or order data.

create table if not exists public.app_remote_settings (
  key text primary key check (char_length(key) between 1 and 100),
  value jsonb not null,
  description text not null default '',
  is_public boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null
);

create index if not exists app_remote_settings_public_idx
  on public.app_remote_settings (is_public, key);

alter table public.app_remote_settings enable row level security;

grant select on public.app_remote_settings to anon, authenticated;
grant insert, update, delete on public.app_remote_settings to authenticated;

drop policy if exists "public can read public app settings" on public.app_remote_settings;
create policy "public can read public app settings"
  on public.app_remote_settings
  for select to anon, authenticated
  using (is_public = true);

drop policy if exists "admins manage app settings" on public.app_remote_settings;
create policy "admins manage app settings"
  on public.app_remote_settings
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

insert into public.app_remote_settings (key, value, description, is_public)
values
  ('maintenance_mode', 'false'::jsonb, 'إيقاف استقبال الاستخدام مؤقتاً عند الحاجة', true),
  ('maintenance_message', '"التطبيق متوقف مؤقتاً للصيانة. حاول لاحقاً."'::jsonb, 'رسالة الصيانة الظاهرة للمستخدمين', true),
  ('feature_flags', '{"customer_app":true,"restaurant_portal":true,"courier_portal":true,"promotions":true,"menu_photos":true,"support_center":true}'::jsonb, 'مفاتيح تشغيل المزايا المدعومة في التطبيق', true),
  ('app_branding', '{"name":"سريع","tagline":"طعامك يصل إليك","city":"رداع"}'::jsonb, 'معلومات العلامة التجارية العامة', true)
on conflict (key) do nothing;

comment on table public.app_remote_settings is
  'Public-safe remote configuration and feature flags for Saree. Never store secrets here.';
