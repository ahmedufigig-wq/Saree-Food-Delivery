-- Add indexes for the two uncovered foreign keys identified by Supabase performance advisors.
-- This is additive and does not modify or delete existing application data.
create index if not exists restaurant_courier_history_courier_id_idx
  on public.restaurant_courier_history (courier_id);

create index if not exists restaurant_courier_history_actor_id_idx
  on public.restaurant_courier_history (actor_id);
