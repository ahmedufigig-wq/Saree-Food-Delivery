-- Add courier assignment state in its own migration so PostgreSQL commits the enum value before functions reference it.
alter type public.order_status add value if not exists 'assigned' before 'picked_up';
