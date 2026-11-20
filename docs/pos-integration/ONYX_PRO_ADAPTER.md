# YemenSoft ONYX Pro adapter — implementation plan

## Verified product scope

YemenSoft publicly describes ONYX ERP as an integrated ERP suite and lists Sales, Inventory, Restaurant Management, and Point of Sale solutions. Its public support material describes customer-specific implementation, permissions, backups, and support workflows. Public mobile-app material mentions configuring server/login details and user permissions.

**Important boundary:** the public material reviewed for this connector does not publish a stable third-party REST API specification, endpoint list, authentication scheme, database schema, or a supported direct-write contract for ONYX Pro. Therefore this repository does not invent ONYX endpoints and does not write directly into ONYX SQL tables. A supported integration interface must be obtained from YemenSoft for the customer's exact ONYX version and licensed modules.

## Target data flow

Saree order -> Supabase outbox (pos_jobs) -> authenticated Windows Bridge -> ONYX-approved integration adapter -> ONYX Pro.

The first safe milestone is a kitchen-ticket bridge. Once YemenSoft supplies an approved API/SDK/import format, replace the print-only adapter with OnyxProAdapter while retaining the same normalized Saree event contract.

## Initial field mapping

| Saree normalized field | ONYX concept to map | Required confirmation |
|---|---|---|
| restaurant/company | Company / entity | ONYX company code |
| restaurant branch | Branch | Branch identifier |
| restaurant POS terminal | POS point / terminal | Terminal configuration |
| order.number | External reference / source order no. | Supported external reference field |
| order.items[].id | Item code | Exact item-code namespace |
| order.items[].quantity | Quantity | Unit and precision rules |
| order.items[].unit_price | Selling price | Whether ONYX price list overrides imported price |
| order.customer | Customer account / cash customer | Customer creation policy |
| order.delivery | Delivery method/address | Delivery service setup |
| payment COD | Cash-on-delivery / collection account | Correct accounting treatment |
| event idempotency key | External unique reference | Duplicate prevention supported by ONYX |

Do not post a completed cash sale or payment voucher simply because a Saree order was received. The restaurant must choose whether ONYX should create a quotation/order, kitchen ticket, or posted sales invoice. COD collection and delivery fees need explicit accounting configuration.

## Connector configuration required per restaurant

- ONYX product name and exact version/build.
- Installed modules: Restaurant, POS, Sales, Inventory.
- Deployment: local Windows server or hosted server.
- Database engine/version (information only; credentials are not requested here).
- Company, branch, warehouse, POS terminal and price list codes.
- Supported integration method confirmed by YemenSoft: REST/SOAP API, SDK, import service, or approved database procedure.
- Test company/database and a technical contact from YemenSoft or the authorized local implementer.

Never send database passwords, admin passwords, service-role keys, or production backups through chat. Use a separate least-privilege integration account and a test company first.

## Windows bridge deployment

The bridge uses:

- SAREE_BRIDGE_URL=https://zfhqprnsrcxahzvwevse.supabase.co/functions/v1/saree-onyx-bridge
- SAREE_BRIDGE_TOKEN=<per-restaurant token provisioned securely by Saree admin>
- SAREE_RESTAURANT_ID=<restaurant UUID>

The token is a one-time secret; store it in Windows Credential Manager or a protected service configuration, never commit it. The currently deployed Edge Function authenticates the SHA-256 token hash against pos_connectors, polls queued orders and accepts acknowledgements.

At this stage the sample bridge is a safe queue/ticket prototype. Its stdout ticket output is not yet a certified thermal-printer driver and is not an ONYX sales transaction. Production printer support must be tested against the restaurant's printer model and Windows driver.

## Acceptance tests before enabling a real restaurant

1. Pull the same order twice: ONYX must not create duplicate tickets/documents.
2. Disconnect internet for 10 minutes, restore it, and verify queued orders are delivered in order.
3. Confirm every line item, quantity, modifier/note, subtotal, delivery fee, and grand total.
4. Confirm the POS response/reference is stored against the Saree job.
5. Confirm a rejected or failed POS import does not mark the Saree order as accepted/delivered.
6. Reconcile one day's Saree orders against ONYX reports before enabling accounting posting.

## Official vendor references reviewed

- ONYX ERP Point of Sale and Sales/Inventory product areas: https://onyxproerp.com/
- ONYX technical support: https://onyxproerp.com/support/
- ONYX publications and manuals: https://onyxproerp.com/publications/
- YemenSoft customer services / implementation process: https://yemensoft.com/ar-customers-services/

Request from YemenSoft: the current ONYX Pro integration/API guide, API/SDK license requirements, supported endpoints or import templates, test environment, and written approval for external order creation.
