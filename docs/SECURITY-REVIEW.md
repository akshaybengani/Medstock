# Security & privacy review — Medstock

Reviewed 2026-08-31 against the whole codebase, the Android manifest, the iOS
Info.plist, the Gradle config and the git hygiene.

Medstock's threat model is narrow but not empty. There is **no network code and
no accounts**, so the classic web risks (auth bypass, SSRF, injection via
untrusted input, secret leakage to a server) do not apply. What does apply is
that the app stores **health information about identifiable family members** on
a phone, and that it is about to be published as a public repository.

## Findings and fixes

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| 1 | **Critical** | iOS `Info.plist` had no `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription`. iOS terminates the app the instant `image_picker` runs without them — "Add photo" was a guaranteed crash on iOS. | Added both strings (plus `NSPhotoLibraryAddUsageDescription`), worded to say photos stay on the device. |
| 2 | **High** | Refill notifications used the default *public* lock-screen visibility, so `Lithosun SR 400mg is running low` was readable by anyone who picked up the locked phone — a medical disclosure. | `visibility: NotificationVisibility.private`. The notification still arrives; its content is hidden until unlock. |
| 3 | **High** | `android:allowBackup` was unset, i.e. Android's default of `true`. The whole medicine database was swept into Google cloud backup and was extractable via `adb backup` from an unlocked device. | `allowBackup="false"` plus a `data_extraction_rules.xml` excluding database, prefs and files from cloud backup *and* device-to-device transfer. **Trade-off documented below.** |
| 4 | **High** | `.gitignore` did not cover signing material. A `key.jks` or `key.properties` in the tree would have been committed to a public repo on the first `git add -A`. | Added `*.jks`, `*.keystore`, `android/key.properties`, and the Google services files. |
| 5 | **High** | `.gitignore` (from the original scaffold) contained `/lib/constants.dart` — a **real source file** holding the medicine types, schedule types and order statuses. The public repo would not have compiled for anyone who cloned it. | Removed that line; added a check that no source file matches an ignore rule. |
| 6 | Medium | Every displayed figure derives from "today", but nothing recomputed at midnight. An app left open overnight kept showing yesterday's stock, coverage and run-out dates. | `AppProvider.refreshIfDayChanged()`, called from a lifecycle observer on resume. Covered by tests. |
| 7 | Medium | `StockMath.status()` was called from inside the sort comparator, so it ran O(n log n) times per tab per rebuild, each call walking forward day by day. | Decorate–sort–undecorate: O(n) status calls. |

## Checked and found clean

- **SQL injection** — every query uses `where:` + `whereArgs` placeholders. The
  only interpolation into SQL is `${K.defaultLowStockDays}`, a compile-time
  `int` in a `CREATE TABLE` default. No `rawQuery` with user input anywhere.
- **Secrets** — no passwords, keys, tokens or credentials in source or config.
- **Network** — the release APK declares no `INTERNET` permission. There is no
  HTTP client, socket or WebSocket in the codebase. (Debug builds add
  `INTERNET` for hot reload; that is the Flutter tool's debug manifest, not
  ours.)
- **Logging** — `debugPrint` calls carry error text only, never patient names,
  medicine names or dosages.
- **Exported components** — only `MainActivity` is exported (required for the
  launcher). Both notification receivers are `exported="false"`.
- **File handling** — medicine photos are copied into the app's private
  documents directory with generated timestamp filenames. No user-controlled
  path is ever concatenated, so there is no traversal.
- **WhatsApp hand-off** — the order text is passed through
  `Uri.encodeComponent`. Note this is an *intentional* export of medicine names
  to WhatsApp; it is the feature. Nothing else leaves the device.
- **Foreign keys** — `PRAGMA foreign_keys = ON` with `ON DELETE CASCADE` on
  assignments and `SET NULL` on order lines, so deleting a patient or medicine
  cannot leave orphan rows or lose order history.

## The backup trade-off (your decision)

Finding 3 is fixed in the privacy-preserving direction: **nothing is backed up,
so nothing leaks — but there is also no automatic restore when you change
phones.** Your medicine book would start empty on a new device.

To prefer convenience over privacy, in
`android/app/src/main/AndroidManifest.xml` set `android:allowBackup="true"` and
delete the `dataExtractionRules` / `fullBackupContent` attributes.

The better long-term answer is a **manual export/import** (a JSON or CSV file
you save yourself). That is not built yet, and it is the one feature I would
add next given the data has no other copy.

## Not applicable / deliberately out of scope

- **Encryption at rest.** The database is in the app's private sandbox, which
  is already protected by the device lock and full-disk encryption on any
  modern Android or iOS device. Adding SQLCipher would mean managing a key,
  and the realistic threat (a stranger with your unlocked phone) is not solved
  by it.
- **Certificate pinning, auth, rate limiting** — no network surface.
- **Obfuscation.** The release build already shrinks and minifies. Full Dart
  obfuscation (`--obfuscate --split-debug-info`) is available if you ever
  publish commercially; it makes crash reports unreadable without the symbol
  files, so it is not worth it for a personal app.
