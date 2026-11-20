# Saree POS Integration Contract (MVP)

Current app release target: `1.2.9+27`.

This is the vendor-neutral contract for connecting Saree to restaurant POS systems in Rada'a.

## Architecture

1. Saree mobile app writes orders only to Supabase.
2. A server-side POS middleware creates one integration job per restaurant order (outbox pattern).
3. A connector is selected per restaurant:
   - `local_bridge`: Windows Local Agent polls the authenticated Saree endpoint and prints kitchen tickets, or calls a vendor-approved local API.
   - `cloud_api`: server-side adapter calls a cloud POS REST API and receives signed webhooks.
   - `manual`: dashboard/thermal ticket only; no accounting-system write.
4. Every message has an immutable `event_id`, `order_id`, and `idempotency_key`. Repeated delivery must not create duplicate POS receipts.
5. POS credentials are stored server-side (Vault/Edge Function secrets), never in Flutter or this repository.

## Normalized order JSON v1

```json
{
  "schema_version": "1.0",
  "event_id": "evt_01J...",
  "event_type": "order.created",
  "idempotency_key": "saree:restaurant-uuid:order-uuid",
  "occurred_at": "2026-11-20T17:30:00Z",
  "restaurant": {
    "id": "restaurant-uuid",
    "name": "مطعم تجريبي",
    "currency": "YER"
  },
  "order": {
    "id": "order-uuid",
    "number": "SR-1042",
    "status": "accepted",
    "notes": "بدون بصل",
    "customer": {"name": "عميل", "phone": "7XXXXXXXX"},
    "delivery": {"type": "delivery", "address": "رداع - ...", "fee": 100},
    "items": [
      {"id": "menu-item-uuid", "sku": null, "name": "وجبة", "quantity": 2,
       "unit_price": 800, "discount": 100, "line_total": 1400,
       "notes": "حار"}
    ],
    "totals": {"subtotal": 1600, "discount": 200, "delivery_fee": 100, "grand_total": 1500}
  }
}
```

All monetary values are integer Yemeni rials. The normalized payload is a contract, not a direct mirror of any one vendor's database.

## Normalized menu JSON v1

```json
{
  "schema_version": "1.0",
  "restaurant_id": "restaurant-uuid",
  "revision": "menu-revision-or-timestamp",
  "items": [
    {"id": "menu-item-uuid", "sku": null, "name": "وجبة", "description": "",
     "category": "وجبات", "price": 800, "currency": "YER",
     "available": true, "image_url": null,
     "updated_at": "2026-11-20T17:30:00Z"}
  ]
}
```

## Connector API contract

- `POST /pos/v1/orders`: create/accept a normalized order (idempotent).
- `GET /pos/v1/bridge/jobs?after=<cursor>`: Local Bridge long-polls for pending jobs.
- `POST /pos/v1/bridge/jobs/{job_id}/ack`: report `printed`, `accepted`, or `failed`, plus vendor reference and error.
- `GET /pos/v1/menu?restaurant_id=...`: normalized menu snapshot.
- `POST /pos/v1/webhooks/{connector}`: receive signed status/menu events from cloud POS.
- Webhook signatures use HMAC-SHA256, timestamp validation, and replay protection.

These routes are the target API contract. They must be implemented in Supabase Edge Functions and backed by an outbox/jobs table before a real bridge can connect. Do not point the sample agent at the production project until those routes are deployed.

## Windows Local Bridge

The sample agent in this folder:
- polls the configured bridge endpoint,
- persists completed event IDs in SQLite to prevent duplicate printing after restarts,
- writes a kitchen ticket to stdout by default,
- can be extended with a vendor-supported local API or a tested ESC/POS printer adapter,
- retries transient network errors and retains local state during internet outages.

It intentionally does NOT write directly to SQL Server/MySQL or inject rows into Amin, YemenSoft, Al-Mutakamil, Sama, or Al-Manar. Those systems have different schemas and accounting rules. Add a separate tested adapter per vendor/version, preferably using a documented API or official import interface.

## Rollout plan

- Phase 0: manual ticket + customer order screen; works without POS integration.
- Phase 1: Windows bridge prints kitchen tickets; offline queue and retry.
- Phase 2: cloud POS adapters (Odoo first where API entitlement/configuration allows); sync menu and status.
- Phase 3: vendor-approved local database/API adapters one POS version at a time.
- Phase 4: reconciliation dashboard, failed-job alerts, duplicate detection, audit logs.

## Security and reliability

- Each restaurant has a separate connector identity and scoped token.
- Never ship Supabase service-role keys or POS API keys in the Flutter APK or Local Bridge config committed to Git.
- Use TLS, token rotation, least privilege, signed webhooks, idempotency, and audit logs.
- Do not mark a Saree order completed because a print job succeeded; printing is not proof of kitchen acceptance or delivery.
- Keep the Saree order as the source of truth until a confirmed POS status event is received.
