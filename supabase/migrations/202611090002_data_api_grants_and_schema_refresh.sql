-- Explicitly expose the platform tables to the Supabase Data API.
-- RLS remains enabled on every public application table.
grant select on public.restaurants, public.menu_categories, public.menu_items to anon;
grant select on public.restaurants, public.restaurant_members, public.menu_categories,
  public.menu_items, public.customer_addresses, public.orders, public.order_items,
  public.courier_locations, public.profiles to authenticated;
grant insert, update, delete on public.restaurants, public.restaurant_members,
  public.menu_categories, public.menu_items, public.customer_addresses,
  public.courier_locations to authenticated;

-- Keep the database migration compatible with the courier claim transition.
alter type public.order_status add value if not exists 'assigned';

notify pgrst, 'reload schema';
