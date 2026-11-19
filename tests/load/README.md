# Saree order burst test (10 concurrent customers)

This is a controlled load-test harness for the existing `create_order_with_gps`
database RPC. It launches 10 virtual users at once, each creating exactly one
test order.

## Safety requirements

- Run only against a dedicated **staging** Supabase project.
- Use a test restaurant and a test menu item that are active and available.
- Use a dedicated test customer access token.
- The script creates 10 database orders. It does not dispatch couriers or send
  food; the notes/address explicitly mark the orders as test data.
- Never point this test at the live customer production project.

## Run

Install k6, then set these environment variables:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `TEST_CUSTOMER_ACCESS_TOKEN`
- `TEST_RESTAURANT_ID`
- `TEST_MENU_ITEM_ID`

Run:

```bash
k6 run tests/load/order_burst.js
```

The test fails its thresholds if the RPC error rate reaches 1% or the 95th
percentile request duration reaches 3 seconds. A passing result is evidence
only for the tested staging configuration; it is not a production capacity
guarantee.

## What this does not test

This RPC test measures concurrent order creation and database validation. It
does not simulate push delivery, courier GPS streaming, restaurant dashboard
rendering, support-agent workflows, or POS vendor APIs. Those require separate
end-to-end tests and the relevant service credentials.
