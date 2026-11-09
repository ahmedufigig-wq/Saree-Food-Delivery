-- Restrict helper RPC exposure while preserving private reads through authenticated RLS.
begin;

drop policy if exists "active restaurants public" on public.restaurants;
drop policy if exists "restaurants_public_active" on public.restaurants;
drop policy if exists "restaurants_private_for_admin_or_members" on public.restaurants;
create policy "restaurants_public_active" on public.restaurants
for select to anon, authenticated using (is_active);
create policy "restaurants_private_for_admin_or_members" on public.restaurants
for select to authenticated using (public.is_admin() or public.is_restaurant_member(id));

drop policy if exists "categories visible for active restaurants" on public.menu_categories;
drop policy if exists "categories_public_active" on public.menu_categories;
drop policy if exists "categories_private_for_admin_or_members" on public.menu_categories;
create policy "categories_public_active" on public.menu_categories
for select to anon, authenticated using (
  is_active and exists (select 1 from public.restaurants r where r.id = restaurant_id and r.is_active)
);
create policy "categories_private_for_admin_or_members" on public.menu_categories
for select to authenticated using (public.is_admin() or public.is_restaurant_member(restaurant_id));

drop policy if exists "available menu public" on public.menu_items;
drop policy if exists "menu_public_available" on public.menu_items;
drop policy if exists "menu_private_for_admin_or_members" on public.menu_items;
create policy "menu_public_available" on public.menu_items
for select to anon, authenticated using (
  is_available and exists (select 1 from public.restaurants r where r.id = restaurant_id and r.is_active)
);
create policy "menu_private_for_admin_or_members" on public.menu_items
for select to authenticated using (public.is_admin() or public.is_restaurant_member(restaurant_id));

drop policy if exists "visible restaurant reviews" on public.reviews;
drop policy if exists "reviews_public_visible" on public.reviews;
drop policy if exists "reviews_private_for_owner_or_admin" on public.reviews;
create policy "reviews_public_visible" on public.reviews
for select to anon, authenticated using (is_visible);
create policy "reviews_private_for_owner_or_admin" on public.reviews
for select to authenticated using (customer_id = auth.uid() or public.is_admin());

drop policy if exists "active promotions public" on public.promotions;
drop policy if exists "promotions_public_active" on public.promotions;
create policy "promotions_public_active" on public.promotions
for select to anon, authenticated using (
  is_active and starts_at <= now() and (ends_at is null or ends_at > now())
);

drop policy if exists "restaurant hours public" on public.restaurant_hours;
drop policy if exists "restaurant_hours_public_active" on public.restaurant_hours;
drop policy if exists "restaurant_hours_private_for_members" on public.restaurant_hours;
create policy "restaurant_hours_public_active" on public.restaurant_hours
for select to anon, authenticated using (
  exists (select 1 from public.restaurants r where r.id = restaurant_id and r.is_active)
);
create policy "restaurant_hours_private_for_members" on public.restaurant_hours
for select to authenticated using (public.is_admin() or public.is_restaurant_member(restaurant_id));

revoke all on function public.is_admin() from public, anon;
revoke all on function public.is_restaurant_member(uuid) from public, anon;
grant execute on function public.is_admin() to authenticated, service_role;
grant execute on function public.is_restaurant_member(uuid) to authenticated, service_role;

commit;