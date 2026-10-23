# Design

Move your existing Stitch exports here so the repo matches the monorepo layout:

- `design/stitch/` ← the `stitch_devicetrust_mobile_marketplace_ui/` screen folders (splash, onboarding, login, home + `DESIGN.md`)
- `design/preview/` ← the old static preview `index.html`, `server.js`, `package.json` (run with `node server.js` to view the HTML prototypes)

`devicetrust_mobile_registry/DESIGN.md` is the source of the colours, type scale, radii and shadows in
`mobile/lib/core/theme.dart` and `admin/src/styles.css`. Screens without a Stitch export (sell, IMEI check,
devices, requests, transfers, reports, notifications, profile) were built from those same tokens.
Prototype copy that claimed live PTA/CPLC/escrow integrations was replaced with accurate wording.
