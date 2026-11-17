# Saree capacity and integration readiness

## Existing capabilities verified in the current project
- Order creation is performed in PostgreSQL through `create_order_with_gps` / `create_order`, which recalculates item prices and validates availability inside the database transaction.
- Orders and courier locations are already in the Supabase Realtime publication.
- A database trigger writes in-app notifications for new restaurant orders, customer order status changes, and courier assignment.
- Customer order tracking and courier location map are already implemented in Flutter.
- A restaurant review is already stored per order.

## Changes in this update
- Separate food and courier ratings are now stored on each review.
- Notifications are now streamed live in the app, and the notifications table has been added to Supabase Realtime.
- Existing data is retained: only nullable review columns and publication membership were added.

## 10-user concurrent load test
Use `tests/load/orders-k6.js` with k6 against a **staging Supabase project**, never production. The test creates real orders, so use a dedicated staging restaurant, menu item, and test customer JWT. It defaults to 10 virtual users / 10 iterations. Supply environment variables documented at the top of the script. Check HTTP error rate and p95 latency, then remove the test orders from staging.

This repository change alone does not prove production capacity. A measured test report must include database region/compute, p95/p99 latency, error rate, and Supabase resource metrics.

## Push notifications
The app currently stores and streams in-app notifications. True Android push notifications require Firebase Cloud Messaging credentials, Android Firebase configuration, and a trusted server/Edge Function to send messages. Those credentials are not present in this repository context, so no fake push-delivery success is claimed.

## POS integration
No POS vendor, API documentation, credentials, or network endpoint has been provided. POS integration cannot safely be implemented generically. Once the restaurant's POS provider and API contract are known, implement a server-side adapter with idempotency keys and order reconciliation; never expose POS secrets in the Android app.
