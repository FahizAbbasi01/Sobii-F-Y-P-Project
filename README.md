# DeviceTrust — Mobile Device Registry & Verification Marketplace

FYP project. A Pakistani second-hand phone marketplace where every listed phone's IMEI is registered to its seller, buyers can check an IMEI before paying, ownership changes only when **both** buyer and seller confirm, and owners can report stolen phones for admin review.

> **Registry ≠ PTA.** DeviceTrust keeps its *own* community registry. It does not connect to PTA/DIRBS, CPLC or police databases, and every result screen says so. For official PTA status, users SMS the 15-digit IMEI to **8484** or use dvs.pta.gov.pk (per the [PTA DIRBS FAQ](https://dirbs.pta.gov.pk/faqs)).

## Repository layout

| Folder | What it is | Stack |
|---|---|---|
| `mobile/` | Android app (Android only — no iOS) | Flutter, go_router, provider, ML Kit text recognition |
| `backend/` | REST API, all business rules and permission checks | Node.js 20+, Express 5, PostgreSQL (`pg`), zod |
| `admin/` | Moderator web dashboard | React 19 + Vite |
| `supabase/migrations/` | Database schema (tables, constraints, RLS lockdown) | PostgreSQL / Supabase |
| `design/` | Original Stitch exports + `DESIGN.md` tokens, and the old static preview server | HTML / Tailwind |

```
Android app ──HTTPS/JSON──▶ Express API ──SQL──▶ Supabase PostgreSQL
Admin (browser) ─────────────▶      │
                                    └──▶ Supabase Storage (private bucket, signed URLs)
```

**Security model.** The app and dashboard never talk to the database. No Supabase key is in the app. The API derives the user from a signed token and re-reads their role/status from the database on every request; ownership, roles and user IDs sent by clients are never trusted. RLS is enabled on every table with no public policies, so Supabase's public REST API exposes nothing.

---

## 1. Prerequisites (Windows)

- **Node.js 20+** — `node -v`
- **Git**
- **Flutter SDK + Android SDK** — see [Install Flutter on Windows](#install-flutter-on-windows) if `flutter doctor` fails
- **PostgreSQL** — either a Supabase project (recommended) or local PostgreSQL for development

## 2. Database

### Option A — Supabase (target)
1. Go to <https://supabase.com> → **New project**. Pick region *Mumbai (ap-south-1)* or *Singapore* (closest to Pakistan). Save the database password.
2. **Project Settings → Database → Connection string → Session pooler**. Copy it; it looks like
   `postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres`
3. **Storage → New bucket** named `devicetrust-private`, **Public: OFF**.
4. **Project Settings → API**: copy the *Project URL* and the *service_role* key. The service_role key goes **only** in `backend/.env` — never in the app, the admin dashboard or git.

### Option B — Local PostgreSQL (development)
Create two databases: `devicetrust` and `devicetrust_test` (the test suite wipes the second one).

## 3. Backend

```powershell
cd backend
copy .env.example .env      # then edit .env (see comments inside)
npm install
npm run migrate             # creates all tables
npm run seed:admin -- you@example.com "Your Name" "AStrongPassw0rd"
npm run dev                 # http://localhost:4000/health
```

For Supabase set `DATABASE_URL` to the pooler string, `DATABASE_SSL=true`, `STORAGE_DRIVER=supabase`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`.
Generate `JWT_ACCESS_SECRET` with:
`node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"`

**Tests** (needs `TEST_DATABASE_URL` pointing at a throwaway database):
```powershell
npm test
```
22 tests cover role spoofing, forged tokens, refresh-token reuse, suspension, duplicate IMEIs (incl. across SIM slots), registry privacy, listing/ownership checks, two-party transfer confirmation, the concurrent-accept race, stolen-report effects, spoofed uploads and the append-only audit log.

## 4. Android app

```powershell
cd mobile
powershell -ExecutionPolicy Bypass -File .\setup_android.ps1   # one time: generates android\ and applies settings
flutter analyze
flutter test
flutter run
```

- **Android emulator:** the default API address `http://10.0.2.2:4000` reaches the backend on your PC.
- **Real phone (same Wi-Fi):** find your PC's IP with `ipconfig`, then
  `flutter run --dart-define=API_BASE_URL=http://192.168.x.x:4000`
  and allow Node.js through Windows Firewall when prompted.
- Plain HTTP is allowed in **debug builds only**; release builds need an HTTPS backend.
- IMEI scanning: tap the scan icon → photograph the box label or another phone's `*#06#` screen. Only numbers that pass the IMEI check-digit test are offered.

## 5. Admin dashboard

```powershell
cd admin
copy .env.example .env      # VITE_API_URL=http://localhost:4000
npm install
npm run dev                 # http://localhost:5173
```
Sign in with the account from `npm run seed:admin`. Ordinary users are refused.

---

## Install Flutter on Windows

1. Install **Android Studio** (includes the Android SDK). Open it once → *More Actions → SDK Manager* → under *SDK Tools* tick **Android SDK Command-line Tools** → Apply.
2. Download the Flutter SDK zip (stable) from <https://docs.flutter.dev/get-started/install/windows/mobile> and extract it to `C:\src\flutter` (not inside Program Files).
3. Add `C:\src\flutter\bin` to your **user PATH**: Start → "Edit environment variables for your account" → Path → New.
4. Open a **new** Command Prompt and run:
   ```
   flutter doctor --android-licenses     (answer y to each)
   flutter doctor
   ```
   You need ✓ for *Flutter* and *Android toolchain*. Chrome/Visual Studio warnings don't matter for an Android-only app.
5. Create an emulator: Android Studio → *Device Manager* → *Create device* → Pixel 7 → a recent system image. Or plug in a phone with **USB debugging** on.

---

## What works (tested)

| Area | Status | How it was tested |
|---|---|---|
| Auth: register, login, rotating refresh tokens, logout, change password, suspension | ✅ | Automated API tests |
| Device registration with IMEI check-digit + global duplicate check (both SIM slots) | ✅ | Automated + end-to-end script |
| Public registry lookup: Registered / Not Found / Reported Stolen / Invalid, no owner data leaked | ✅ | Automated + end-to-end |
| Marketplace: create/edit/withdraw listings, photos, search, filters, sort, pagination | ✅ | Automated + end-to-end |
| Purchase requests: send, accept, decline, withdraw | ✅ | Automated + end-to-end |
| Ownership transfer: two-party confirmation, history, one active transfer per device, race-safe | ✅ | Automated (incl. concurrency test) |
| Stolen reports → admin approve/reject → registry flag, market lockout | ✅ | Automated + browser test of admin |
| Disputes, document review, user suspension, listing removal | ✅ | Browser test of admin dashboard |
| Audit log (append-only at database level), suspicious-activity flags | ✅ | Automated + browser |
| Android app (13 screen groups) | ⚠️ Written; **must be compiled on your PC** | Flutter downloads were blocked in the build environment; imports cross-checked mechanically |

## Remaining work (≈30%)

1. **Compile and fix the Flutter app on a real emulator/phone**, then a full manual walkthrough of every screen.
2. Deploy the backend over **HTTPS** (Render/Railway/Fly.io) and point the app at it; release APK signing.
3. **Email/phone verification** and password reset (OTP); currently any email can register.
4. Push notifications (FCM). In-app notifications exist; nothing is pushed to the lock screen.
5. **Recovered device** flow (owner marks a stolen phone as found → admin un-flags).
6. In-app chat between buyer and seller; ratings/reviews of sellers.
7. PDF upload from the phone (images work; PDFs work via the API but the app has no file picker yet).
8. Admin: export reports, charts beyond 14 days, admin-role management in the UI (currently via script, by design).
9. Rate limiting is in-memory (single server); use Redis if you run more than one instance.
10. Formal test documentation, user manual and FYP report screenshots.
