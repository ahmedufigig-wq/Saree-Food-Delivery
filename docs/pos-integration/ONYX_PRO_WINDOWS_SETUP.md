# Windows deployment — YemenSoft ONYX Pro bridge

This is the first integration milestone for a restaurant using ONYX Pro Restaurant Management on a Windows PC inside the restaurant.

## What is active now

- Supabase connector registry and durable order outbox.
- Order-created trigger that snapshots order header and lines after the order transaction commits.
- Edge Function at `/functions/v1/saree-onyx-bridge`.
- Admin-only token provisioning endpoint (`POST /provision`).
- Per-restaurant bridge-token authentication for job polling and acknowledgements.

This milestone queues Saree orders and returns them to the restaurant Windows agent. It does **not** yet create a posted ONYX invoice or write to ONYX's accounting database. Vendor-approved API/SDK/import specifications are still required for that adapter.

## Provision a restaurant bridge

A Saree administrator must first sign in and obtain a current Supabase user access token. Use the administrator session JWT, not an anon key or service-role key:

```http
POST https://zfhqprnsrcxahzvwevse.supabase.co/functions/v1/saree-onyx-bridge/provision
Authorization: Bearer <ADMIN_USER_ACCESS_TOKEN>
Content-Type: application/json

{
  "restaurant_id": "<RESTAURANT_UUID>",
  "vendor_version": "unknown"
}
```

The endpoint checks the signed-in user's row in `profiles` and requires `role = admin`. It returns a random per-restaurant bridge token once. Copy it securely; the raw token is not stored in the database and cannot be retrieved later. Provisioning rotates the previous token for that restaurant.

Never place the admin JWT, Supabase service-role key, or raw bridge token in GitHub, Flutter source, screenshots, or shared chat.

## Windows environment

Set these environment variables for the Windows service account (PowerShell example):

```powershell
[Environment]::SetEnvironmentVariable("SAREE_BRIDGE_URL", "https://zfhqprnsrcxahzvwevse.supabase.co/functions/v1/saree-onyx-bridge", "User")
[Environment]::SetEnvironmentVariable("SAREE_BRIDGE_TOKEN", "<ONE_TIME_TOKEN_FROM_PROVISION>", "User")
[Environment]::SetEnvironmentVariable("SAREE_RESTAURANT_ID", "<RESTAURANT_UUID>", "User")
```

Install Python 3.11+, open a new PowerShell session, then run:

```powershell
python .\pos-bridge\bridge.py
```

Keep the process running under a dedicated Windows service account. The current sample writes a kitchen ticket to stdout; redirect output to a protected log while testing. Do not install it on the live POS workstation until the restaurant approves the test window.

## Test checklist

1. Provision one test restaurant and confirm the raw token is saved securely.
2. Start the Windows agent; confirm its last-seen timestamp changes in the connector record.
3. Create one low-value test order in Saree and verify a single job appears in the queue and the ticket prints/displays.
4. Restart the agent and verify the same event is not printed again locally.
5. Disable internet briefly, restore it, and verify the job is retried without losing the local processed-event database.
6. Verify a bridge token from another restaurant cannot read or acknowledge this restaurant's jobs.

## ONYX Pro-specific completion gate

Because the restaurant has ONYX Restaurant Management but its exact build is unknown, ask the restaurant's YemenSoft implementer to identify:
- ONYX Pro version/build and database engine.
- Restaurant module's supported external order interface (API, SDK, import service, or vendor-approved stored procedure).
- Required branch, warehouse, menu item, and POS terminal identifiers.
- Whether Saree orders should enter ONYX as kitchen tickets, restaurant orders, sales orders, or posted invoices.
- How COD and delivery charges should be represented.

Once this information is confirmed, implement and test a dedicated adapter without changing the Saree outbox contract.
