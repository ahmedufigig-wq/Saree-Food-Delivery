-- Remove cashier membership workflow and the unused external POS connector.
-- Preserve profiles, restaurants, orders, order_items, couriers and delivery data.

delete from public.restaurant_members rm
where rm.member_role = 'staff'
  and exists (
    select 1
    from public.restaurant_cashier_applications ca
    where ca.applicant_id = rm.user_id
  );

drop trigger if exists link_accepted_cashier_to_restaurant
  on public.restaurant_cashier_applications;
drop function if exists public.link_accepted_cashier_to_restaurant();
drop function if exists public.cashier_set_order_status(uuid, text);

drop trigger if exists orders_enqueue_pos_job on public.orders;
drop function if exists public.enqueue_saree_pos_order();

drop table if exists public.restaurant_cashier_applications;
drop table if exists public.pos_jobs;
drop table if exists public.pos_connectors;
