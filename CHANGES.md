# Feature Update: Order Types, Tables, Roles, Staff Attendance, Product Photos

This document covers everything added on top of the original Fast N Fresh Cafe app, per the
two feature requests (order type/table/role system, and staff attendance tracking). Nothing
in the original app was removed or renamed — all changes are additive or are permission
tightenings enforced identically on both the API and the Flutter UI.

---

## 1. Files changed

### Backend (new)
```
backend/src/models/Table.js
backend/src/controllers/tableController.js
backend/src/controllers/userController.js
backend/src/controllers/attendanceController.js
backend/src/controllers/uploadController.js
backend/src/middleware/upload.js
backend/src/routes/tableRoutes.js
backend/src/routes/userRoutes.js
backend/src/routes/attendanceRoutes.js
backend/src/routes/uploadRoutes.js
backend/uploads/products/               (new upload directory)
```

### Backend (modified)
```
backend/src/models/User.js              role enum: admin|staff -> admin|manager|staff
backend/src/models/Order.js             + orderType, table, tableCustomerLabel, deliveryInfo,
                                         + attendedByHistory, status now open|completed|voided,
                                         paymentMethod/subtotal/grandTotal made optional/defaulted
                                         (to support the open/unpaid dine-in state)
backend/src/models/Product.js           + imageUrl
backend/src/models/index.js             + Table export
backend/src/controllers/orderController.js   refactored: shared priceAndValidate/
                                         applyInventoryAndCredit helpers; + startTableOrder,
                                         updateOpenOrderItems, checkoutOrder, cancelOpenOrder,
                                         reassignAttendee; listOrders/getOrder order-type & table
                                         aware; createOrder unchanged in spirit for takeaway/delivery
backend/src/controllers/creditController.js   + grantCredit (staff-facing "give credit")
backend/src/controllers/customerController.js getCustomer redacts transaction ledger for staff
backend/src/controllers/productController.js  create/update accept imageUrl
backend/src/controllers/reportController.js   sales report + dine-in/takeaway/delivery breakdown
backend/src/routes/orderRoutes.js       + items/checkout/cancel/attendee routes
backend/src/routes/creditRoutes.js      role-gated: grant (all) vs overview/transactions/payment
                                         (admin+manager)
backend/src/routes/customerRoutes.js    payment route restricted to admin+manager
backend/src/routes/reportRoutes.js      per-route authorize (credit report now admin+manager)
backend/src/routes/index.js             + tables/uploads/users/attendance routers
backend/src/app.js                      + static /uploads serving, relaxed CORP for images
backend/src/utils/seed.js               + manager seed user, + 6 sample tables
backend/.env.example                    + SEED_MANAGER_* vars
backend/package.json                    + multer dependency
backend/README.md                       updated API table, new sections
```

### Mobile (new)
```
lib/models/table.dart
lib/services/table_service.dart
lib/services/upload_service.dart
lib/screens/pos/new_order_screen.dart
lib/screens/products/product_image_picker.dart
lib/screens/tables/tables_screen.dart
lib/screens/tables/table_detail_screen.dart
lib/screens/tables/table_form_screen.dart
lib/screens/users/users_screen.dart
lib/screens/attendance/attendance_screen.dart
lib/screens/attendance/staff_attendance_detail_screen.dart
```

### Mobile (modified)
```
lib/models/user.dart            + isManager, canViewCreditHistory, canManageTables,
                                 canManageRoles, canViewStaffPerformance, canViewDashboard
lib/models/order.dart           + orderType, tableId/tableName/tableCustomerLabel, deliveryInfo
lib/models/product.dart         + imageUrl, hasImage
lib/providers/cart_provider.dart + orderType/table/openOrderId context, hydrateFromOpenOrder,
                                 clearItems (preserves context), clear (resets context)
lib/services/order_service.dart + orderType/tableId/deliveryInfo on createOrder,
                                 + updateOpenOrderItems, checkoutOrder, cancelOpenOrder,
                                 reassignAttendee, orderType/table filters on list()
lib/services/misc_services.dart + UserService, AttendanceService, CreditService.grantCredit
lib/services/catalog_service.dart  (unchanged — Product.fromJson already picks up imageUrl)
lib/core/network/api_config.dart + resolveAssetUrl/assetHost (for product photo URLs)
lib/screens/pos/pos_screen.dart  now accepts orderType/tableId/openOrderId/autoOpenCart;
                                 defaults preserve exact original takeaway behavior
lib/screens/pos/cart_sheet.dart  Clear now preserves order-type context; delivery-aware hint
lib/screens/pos/payment_sheet.dart  branches: open-order checkout vs direct createOrder;
                                 requires a customer for delivery orders
lib/screens/orders/orders_screen.dart      + order-type filter chips, order-type/table display
lib/screens/orders/order_detail_screen.dart + order-type/table/attendee display
lib/screens/customers/customer_detail_screen.dart  role-aware: Give Credit (staff) vs
                                 Record Payment + full ledger (manager/admin)
lib/screens/products/products_screen.dart  + photo thumbnail
lib/screens/products/product_form_screen.dart  + ProductImagePicker field
lib/screens/reports/reports_screen.dart  + creditOnly mode for Manager's limited view
lib/screens/settings/more_screen.dart    role-conditional sections (admin/manager)
lib/screens/main/main_shell.dart         3-tier role nav (admin/manager get Dashboard+More)
lib/services/receipt_service.dart        PDF receipt shows Order Type + Table
android/app/src/main/AndroidManifest.xml + camera/media permissions for product photos
pubspec.yaml                    + image_picker, flutter_image_compress
mobile/README.md                new sections for this update
```

---

## 2. Database / model changes

**User** — `role` enum extended from `admin|staff` to `admin|manager|staff`. No migration
needed for existing documents (existing `admin`/`staff` values remain valid).

**Table** (new collection) — `name`, `capacity`, `status` (available/occupied/reserved — occupied
is derived at read time from open orders, not trusted from this stored field), `active`
(soft-delete flag, never hard-deleted so historical order/report data referencing a table stays
intact).

**Order** — additive fields only, all optional/defaulted so existing documents remain valid:
- `orderType`: `dine_in | takeaway | delivery` (defaults to `takeaway`)
- `table`: ObjectId ref Table, nullable
- `tableCustomerLabel`: display label ("Customer 1", "Customer 2"...) distinguishing multiple
  simultaneous orders on the same table
- `deliveryInfo`: `{ address, phone }`, only used for delivery orders without relying on a new
  customer database — reuses the existing `Customer` model wherever a saved customer is selected
- `status` enum extended from `completed|voided` to `open|completed|voided` — `open` represents an
  unpaid, in-progress dine-in tab; `paymentMethod`/`subtotal`/`grandTotal` were made
  optional/defaulted to support this pre-payment state
- `attendedByHistory`: array of `{ user, from, to }`, populated only on handover (reassignment);
  the existing `staff` field continues to be the single source of truth for "who is currently
  attending this order"

**Product** — `imageUrl` (string, relative URL, default `''`).

**Table → multiple active orders**: implemented as a one-to-many reference (`Order.table` points
at `Table._id`), not by cramming multiple customers into one Order document. Each customer at a
table is a fully independent `Order` row with its own items/total/payment/status — this is what
makes "separate bill per customer" possible without any bill-merging logic.

---

## 3. New API endpoints

```
GET    /api/tables
GET    /api/tables/:id
POST   /api/tables                        (admin, manager)
PUT    /api/tables/:id                    (admin, manager)
DELETE /api/tables/:id                    (admin, manager)  — deactivates, never hard-deletes
POST   /api/tables/:tableId/orders        — start a new open (unpaid) customer tab on a table

PUT    /api/orders/:id/items              — edit an open dine-in tab's cart
POST   /api/orders/:id/checkout           — bill an open dine-in tab (atomic, same as createOrder)
DELETE /api/orders/:id                    — cancel an open (unpaid) tab
PATCH  /api/orders/:id/attendee           (admin, manager) — handover / reassign attendee

POST   /api/credits/grant                 — staff can register a new credit/UDHAR transaction

GET    /api/users                         (admin)
POST   /api/users                         (admin) — create staff or manager account
PATCH  /api/users/:id/role                (admin) — staff <-> manager only, never touches admin
PATCH  /api/users/:id/status              (admin) — activate/deactivate, protects last admin

GET    /api/attendance/summary            (admin) — staff performance across all employees
GET    /api/attendance/:staffId           (admin) — one employee's detailed activity/orders

POST   /api/uploads/product-image         (admin) — multipart upload, returns relative URL
```

Existing endpoints changed only in **who can call them** (see permission matrix below) or gained
new optional request fields (`orderType`, `tableId`, `deliveryInfo` on `POST /api/orders`;
`imageUrl` on product create/update) — no existing required field or response shape was removed.

---

## 4. Permission matrix (as implemented, enforced in both API middleware and Flutter UI)

| Feature | Admin | Manager | Staff |
|---|---|---|---|
| Dine-In / Takeaway / Delivery orders | Yes | Yes | Yes |
| Table management (add/edit/deactivate) | Yes | Yes | No (view/select only) |
| Multiple customers per table | Yes | Yes | Yes |
| Create credit (`/credits/grant`) | Yes | Yes | Yes |
| View credit history / outstanding reports | Yes | Yes | **No** |
| Pay down existing UDHAR balance | Yes | Yes | **No** |
| Manage staff/manager roles | Yes | **No** | **No** |
| Create manager/staff accounts | Yes | **No** | **No** |
| Deactivate accounts | Yes | **No** | **No** |
| Staff attendance auto-recording | Automatic | Automatic | Automatic |
| View staff performance / attendance report | Yes | **No** | **No** |
| Void a completed sale | Yes | **No** | **No** |
| Add/edit product photo | Yes | No (existing product-mgmt policy: admin only) | No |
| Sales / Products / Staff-sales reports | Yes | **No** | **No** |
| Expenses | Yes | **No** | **No** |
| App settings | Yes | **No** | **No** |
| Dashboard | Yes | Yes | No (staff lands on POS directly) |

---

## 5. New Flutter screens/widgets

- `NewOrderScreen` — Dine-In/Takeaway/Delivery chooser, the POS tab's new entry point
- `TablesScreen`, `TableDetailScreen`, `TableFormScreen` — table grid with live status, per-table
  multi-customer view, add/edit table
- `UsersScreen` (+ add-user sheet) — admin role management
- `AttendanceScreen`, `StaffAttendanceDetailScreen` — admin staff-performance report
- `ProductImagePicker` — pick/capture, compress, upload a product photo
- `PosScreen` extended (not duplicated) to serve Takeaway/Delivery/Dine-In-tab billing from one
  codebase, as originally required

---

## 6. Environment variables added

```
# backend/.env
SEED_MANAGER_NAME=Vikas
SEED_MANAGER_USERNAME=manager
SEED_MANAGER_PHONE=7777777777
SEED_MANAGER_PASSWORD=Manager@123
```

No new required variables for the mobile app — product photos resolve automatically against the
existing `API_BASE_URL`.

---

## 7. Commands to run/build

Unchanged from the base app — see `backend/README.md` and `mobile/README.md`. After pulling this
update:

```bash
cd backend
npm install            # picks up the new multer dependency
npm run seed            # creates the new manager account + sample tables (idempotent — safe
                         # to re-run on an existing database, it skips anything that already exists)
npm run dev

cd mobile
flutter pub get         # picks up image_picker + flutter_image_compress
flutter run
```

---

## 8. Testing status

**Verified in this environment** (no live MongoDB or Flutter SDK available here, same constraint
as the original build):
- Full backend require-graph loads with zero errors after every change (re-run after each batch
  of edits).
- Every backend route file syntax-checked individually.
- Full Flutter project (69 files): all relative imports resolve, zero duplicate class names, all
  braces/parens/brackets balanced in every file.
- Manually traced the code path for each of the 30 scenarios you listed (see below) against the
  actual controller/route/screen logic — this is a code-level trace, not an executed test run.

**Scenario trace** (1–30 from your test list):

| # | Scenario | Where it's implemented |
|---|---|---|
| 1–2 | Admin logs in, creates a manager | `POST /api/users` role=manager, `UsersScreen` add sheet |
| 3 | Admin creates staff | same endpoint, role=staff |
| 4 | Admin changes staff→manager | `PATCH /api/users/:id/role`, `UsersScreen._changeRole` |
| 5–6 | Manager/Staff cannot change roles | `/users/*` routes are `authorize('admin')` only; no UI entry point exists for non-admins (More menu conditionally omits it) |
| 7 | Staff creates a credit transaction | `POST /api/credits/grant`, reachable from any role via `CustomerDetailScreen` |
| 8 | Staff cannot open credit history | `GET /credits*` routes require admin/manager; `CustomerDetailScreen` hides the ledger and swaps the button for staff; staff has no Reports/More tab at all |
| 9–10 | Manager/Admin can see credit history | `ReportsScreen`/`CustomerDetailScreen` show it when `canViewCreditHistory` is true |
| 11 | Admin creates Table 1 | `POST /api/tables`, `TableFormScreen` |
| 12 | Staff starts dine-in order on Table 1 | `TableDetailScreen._addCustomer` → `POST /tables/:id/orders` |
| 13 | Customer A orders ₹300 | items added in `PosScreen`, saved via `PUT /orders/:id/items` at checkout time |
| 14 | Customer B joins Table 1 | `TableDetailScreen._addCustomer` again — independent open order |
| 15 | Customer B orders ₹500 | same as #13 for the second order |
| 16–17 | Separate bills for A and B | each open order checks out independently via `POST /orders/:id/checkout`; separate `orderNumber`, separate receipt |
| 18 | Customer A pays | checkout completes A's order only |
| 19 | Customer B remains active | B's order is untouched, still `status: open` |
| 20 | Table still occupied | `liveStatus` computed from remaining open orders — still ≥1 |
| 21 | Customer B pays | checkout completes B's order |
| 22 | Table becomes available | `openOrderCount` drops to 0 → `liveStatus: available` |
| 23 | Staff creates takeaway order | `NewOrderScreen` → Takeaway → unchanged original `PosScreen` flow |
| 24 | Staff creates delivery order | `NewOrderScreen` → Delivery → same flow, customer required |
| 25–26 | Admin adds item with photo, shows in POS | `ProductImagePicker` in `ProductFormScreen`; thumbnail rendered in `ProductsScreen` and `PosScreen`'s product card |
| 27–30 | Existing billing/PDF/inventory/reports still work | Takeaway/Delivery/direct-createOrder path is the original code, untouched; inventory deduction and PDF receipt generation logic unchanged, just extended with order-type display |

I traced every scenario against the code but could not execute them against a running server —
please run through them once on your machine, since a live end-to-end run can surface issues a
code trace can't (concurrency edge cases, actual MongoDB transaction behavior, real device camera
permissions, etc.).

---

## 9. Known gaps / remaining issues

- **Delivery address**: reuses the existing `Customer.address` field. If a selected customer
  doesn't have an address on file, the delivery order will save with an empty address — there's
  no hard validation forcing an address to be filled in before billing a delivery order. Easy to
  add if you want it stricter (validate `customer.address.isNotEmpty` in `PaymentSheet` before
  allowing delivery checkout).
- **Manager's product-photo permission**: the requirement doc listed this as "according to
  existing permission," and the existing policy was admin-only for all product management, so I
  kept it admin-only rather than opening it to managers. Say the word if you'd rather managers
  could also add/edit product photos.
- **Attendance "customers attended" metric**: defined as distinct people served (dedupes repeat
  visits from the same saved `Customer`, falls back to one-per-order for walk-ins with no saved
  customer). This is a reasonable interpretation but wasn't 100% unambiguous in the spec — flag if
  you want a different definition.
- Not executed against a live backend/emulator in this environment (see Testing Status above) —
  please do a real run-through before shipping to the cafe.
