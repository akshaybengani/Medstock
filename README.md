<div align="center">

<img src="assets/branding/icon.png" width="104" alt="Medstock" />

# Medstock

**A fully offline stock book for a household's medicines.**

Not a pill reminder — a logistics ledger. How much of each medicine is left,
when it runs out, and exactly how much to buy to reach a given date.

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-00696D)](#)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-00696D)](#)
[![Offline](https://img.shields.io/badge/network-none-00696D)](#no-network-at-all)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial-00696D)](LICENSE)

</div>

---

## Why this exists

I buy roughly a thousand pills a month for my grandparents, my parents and
myself. The hard part was never remembering to take them — it was knowing, on
any given day, how much of each medicine was actually left, and what to put in
the next order to the pharmacy.

Every app I found was a pill reminder. This one is a stock book.

## The idea that makes it work: stock is derived, never decremented

The obvious design is a nightly job that subtracts each day's doses. It is also
lossy: the phone is off, the app is killed, Doze defers the alarm — miss one
night and the number is silently wrong forever, with nothing to detect it.

Medstock stores a **snapshot** instead: how many units you had, and the date you
counted them. Current stock is *replayed* from that date on every read.

```
remaining(today) = stock_qty − consumption over [stock_as_of, today)
```

Coverage then walks forward one day at a time, subtracting each day's scheduled
dose until a day cannot be met — that day is the run-out date. Walking rather
than dividing by an average is what makes Mon/Wed/Fri and alternate-day
schedules land on the right date.

Nothing depends on the app having run on any particular day. Open it after a
month away and the figures are still correct. `Add stock`, `Recount` and
`Mark received` simply write a new snapshot dated today — the only writes there
are.

The engine is [`lib/helpers/stock_math.dart`](lib/helpers/stock_math.dart), and
it is pure functions with no I/O, which is why it is cheap to test exhaustively.

## Per-patient dosage on a shared medicine

Dosage lives on a `dose_assignments` join row — one per (medicine, patient) —
never on the medicine itself. That is what makes the case this app was built
for work properly:

| | Dytor 5 |
|---|---|
| Mom | 1 / day |
| Dad | 2 / day |
| **All tab** | **3 / day** |

Each patient tab reads only their own row; the "All" tab sums them. The add/edit
form shows the running household total as you toggle people on.

Each assignment supports:

- units per intake (halves allowed) × intakes per day
- **Every day**, **Specific days** (weekday picker), **Every N days**, or
  **One unit lasts N days**

### Things you can't count per dose

Eye drops, syrups, inhalers, creams and patches aren't taken in countable
doses — you know a bottle lasts about a month, not how many drops are in it.
Those use **One unit lasts N days**, which burns stock down *continuously*:

```
consumption per day = units ÷ days it lasts
```

A 30-day bottle opened 12 days ago therefore reads **0.6 bottles in stock, 18
days left**. A discrete "one every 30 days" schedule would have shown 0 bottles
the moment it was opened — which is why this is its own mode rather than reusing
the interval one. Cards phrase it `1 bottle / 30 days`, never
`0.03 bottles / day`, and picking Drops or Syrup selects the mode automatically.

Ordering still resolves to whole containers: 90 days of cover with one bottle in
hand asks for 2 more.

## Ordering

Pick the date your stock should last until. For each medicine:

```
order = ceil( doses from today through the target date − stock on hand )
```

rounded up to whole packs where a pack size is set. The draft is fully editable,
and once created can be sent to WhatsApp in the format the pharmacy expects:

```
Lithosun SR 400mg
40 tablets

Nexito 10mg
45 tablets
```

Sharing uses a `wa.me/<number>?text=…` link. A saved pharmacy contact opens that
chat directly; without one, WhatsApp shows its own contact picker.
**Mark received** adds the ordered quantities back into stock, closing the loop.

Where a price is recorded, orders also show an **estimated total**. Price is
asked for **per pack** — a strip, a bottle, a box — because that is how
medicines are bought; the per-unit cost is then `packPrice ÷ packSize`. Setting
a price therefore *requires* a pack size, which the form enforces rather than
silently costing nothing.

Estimates use the exact quantity rather than whole packs, since pharmacies here
cut a strip to the count asked for. Lines with no price are excluded rather than
guessed at, and the number of those is shown so the total is never quietly
wrong. The per-unit price is snapshotted onto the order line, so repricing a
medicine never rewrites the cost of an order already placed.

## Medicine history

Every medicine keeps a read-only, append-only log: added to the book, stock
added, recounted, order received, price changed, dosage changed. It exists to
answer "when did I last touch this?" — useful when you cannot remember whether
you already topped something up.

## Refill reminders

Because consumption is deterministic, reminders need no background job. For each
medicine Medstock computes the exact date stock falls to its warning threshold
and schedules a concrete local notification for 9 a.m. that day. The set is
rebuilt on launch and after every write.

Two deliberate choices:

- **Permission is not requested on first launch.** A cold prompt gets a reflex
  denial, and on Android that is close to permanent. The explainer appears after
  you add your first medicine, when the feature has visible value.
- **Notifications are `private` visibility**, so medicine names stay hidden on a
  locked screen. They are health data.

## No network at all

There is no HTTP client, socket or WebSocket anywhere in the codebase, and the
release APK declares **no `INTERNET` permission**. Debug builds add it — that is
the Flutter tool's own manifest for hot reload, not this app.

The database is also excluded from Android cloud backup and device-to-device
transfer, so a family's medical data is not swept into someone else's
infrastructure. The trade-off is that **there is no automatic restore on a new
phone** — which is why export exists.

See [`docs/SECURITY-REVIEW.md`](docs/SECURITY-REVIEW.md) for the full review,
including the findings that were fixed and the reasoning behind each.

## Backup & restore

Drawer → **Backup & restore** exports the entire book — medicines, patients,
pharmacies, orders, order lines and history — as one readable JSON file, then
opens the share sheet.

Import shows you what the file contains and what it will replace before it
touches anything, and the restore runs in a **single transaction**: a bad file
leaves your current book exactly as it was.

## Database migrations

App updates must never cost you your data, so the schema is versioned with real
migration steps ([`lib/services/database_service.dart`](lib/services/database_service.dart)):

- Every version between the installed one and the current one is applied in
  order, so skipping several releases still lands correctly. `v3` moved price
  from per-unit to per-pack and converted existing rows so no recorded cost
  changed.
- Steps only ever **add** tables or columns.
- A fresh install replays the same migrations on top of v1, so `onCreate` and
  `onUpgrade` can never drift apart — [there is a test asserting the two produce
  identical schemas](test/migration_test.dart).
- Downgrades are **refused** rather than allowed to wipe the file.

## Screens

| | |
|---|---|
| **Dashboard** | Search, a dynamic tab row (`All` + one per patient), and cards showing dose, units left, run-out date, coverage bar and who takes it. Low and out-of-stock float to the top; the strip above the tabs names the soonest run-out. |
| **Medicine** | Derived stock, per-patient dosage breakdown, optional detail fields, and the history log. |
| **Orders** | Past orders with item counts and cost estimates; the draft flow and the WhatsApp message preview. |
| **Drawer** | Patients, pharmacy contacts, appearance, backup & restore, and the build number. |

Search matches every medicine field plus patient names, AND-ing terms so
`mom dytor` narrows rather than widens.

Appearance offers **Match device / Light / Dark**, defaulting to the system
setting and remembered across launches.

## Layout

```
lib/
  constants.dart          medicine types, schedule types, order status, event types
  helpers/
    stock_math.dart       the projection engine (pure functions, no I/O)
    date_helpers.dart     whole-day, DST-safe date arithmetic; unit pluralisation
  models/                 patient, medicine, dose_assignment, order, pharmacy, event
  services/
    database_service.dart schema + versioned migrations
    backup_service.dart   JSON export / validated import
    notification_service.dart
    whatsapp_service.dart message formatting + wa.me launch
    image_service.dart    picks and persists photos privately
    settings_service.dart theme + prompt state
  repositories/           one per table
  providers/              app_provider (single source of truth), theme_provider
  components/             atoms, cards, dose editor, drawer, dialogs
  screens/                dashboard, medicine, orders, patients, pharmacy, settings
tool/branding.py          generates every icon and splash asset from one function
```

State is `provider` + `ChangeNotifier`. The dataset is a family medicine
cabinet — tens of rows — so it is held in memory and reloaded after each write,
which keeps every derived figure consistent without a caching layer. The one
thing not cached is the history log, which is read on demand.

## Running it

```bash
flutter pub get
flutter test
flutter run
```

On a device or emulator, the full app can be driven end to end:

```bash
flutter test integration_test/app_test.dart -d <device-id>
```

Release build:

```bash
flutter build apk --release        # Android
flutter build ipa                  # iOS (needs your own signing)
```

Requires Flutter 3.44+ / Dart 3.10+.

### Regenerating branding

All icons and splash images come from one drawing function, so the mark can
never drift between platforms:

```bash
python3 tool/branding.py
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

### Signing (Android)

Release signing reads `android/key.properties`, which is **not** in the
repository. Without it the release build falls back to debug signing and prints
a warning — fine for testing, never for publishing. To set up your own:

```bash
keytool -genkeypair -v -keystore android/medstock-release.jks \
  -alias medstock -keyalg RSA -keysize 4096 -validity 10950 -storetype PKCS12
```

then create `android/key.properties`:

```properties
storeFile=medstock-release.jks
storePassword=…
keyAlias=medstock
keyPassword=…
```

Back up both files somewhere private. Losing them means you can never update an
app already published under that key.

## Tests

```
flutter analyze   # clean
flutter test      # 123 tests
```

- **Projection engine** — snapshot replay, coverage, order quantities,
  weekday / interval / duration schedules, reminder dates, pluralisation.
- **End-to-end through the real sqflite schema**, no mocks, via
  `sqflite_common_ffi` — the shared-medicine case, search, orders, receiving,
  history events, cost estimates, and a full backup round trip.
- **Migrations** — a hand-built v1 database is upgraded and checked row by row.
- **Widget tests** rendering the real screens, including a 360×640 phone surface
  to catch layout overflow, and both themes.
- **Integration tests** driving the real app on a device.

A note on the last two: several genuine bugs in this codebase were found only by
rendering and driving it, not by reading it — duplicate hero tags that asserted
on every route transition, a `Material` that crashed on exactly the low-stock
cards, and interactions that silently no-opped against off-screen widgets. The
suite exists because of them.

## Licence

[PolyForm Noncommercial 1.0.0](LICENSE) — read it, run it, change it, share it
for any noncommercial purpose. Commercial use needs written permission.

**Medstock is not a medical device.** It does not give medical advice or check
interactions, and its reminders must not be relied on clinically. See
[NOTICE](NOTICE).
