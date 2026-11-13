-- Restaurant-owned promotions and public menu photography.
alter table public.promotions
  add column if not exists restaurant_id uuid references public.restaurants(id) on delete cascade;

create index if not exists promotions_restaurant_window_idx
  on public.promotions(restaurant_id, is_active, starts_at, ends_at);

drop policy if exists "restaurant members manage own promotions" on public.promotions;
create policy "restaurant members manage own promotions"
  on public.promotions
  for all to authenticated
  using (restaurant_id is not null and public.is_restaurant_member(restaurant_id))
  with check (restaurant_id is not null and public.is_restaurant_member(restaurant_id));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('menu-photos', 'menu-photos', true, 8388608, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
set public = true,
    file_size_limit = 8388608,
    allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "restaurant members upload menu photos" on storage.objects;
create policy "restaurant members upload menu photos"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'menu-photos' and public.is_restaurant_member((storage.foldername(name))[1]::uuid));

drop policy if exists "restaurant members update menu photos" on storage.objects;
create policy "restaurant members update menu photos"
  on storage.objects for update to authenticated
  using (bucket_id = 'menu-photos' and public.is_restaurant_member((storage.foldername(name))[1]::uuid))
  with check (bucket_id = 'menu-photos' and public.is_restaurant_member((storage.foldername(name))[1]::uuid));

drop policy if exists "restaurant members delete menu photos" on storage.objects;
create policy "restaurant members delete menu photos"
  on storage.objects for delete to authenticated
  using (bucket_id = 'menu-photos' and public.is_restaurant_member((storage.foldername(name))[1]::uuid));
