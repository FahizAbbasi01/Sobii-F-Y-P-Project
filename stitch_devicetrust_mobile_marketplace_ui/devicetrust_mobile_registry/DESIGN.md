---
name: DeviceTrust Mobile Registry
colors:
  surface: '#f7f9fc'
  surface-dim: '#d8dadd'
  surface-bright: '#f7f9fc'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f4f7'
  surface-container: '#eceef1'
  surface-container-high: '#e6e8eb'
  surface-container-highest: '#e0e3e6'
  on-surface: '#191c1e'
  on-surface-variant: '#44474d'
  inverse-surface: '#2d3133'
  inverse-on-surface: '#eff1f4'
  outline: '#75777e'
  outline-variant: '#c5c6ce'
  surface-tint: '#4d5f7e'
  primary: '#000d23'
  on-primary: '#ffffff'
  primary-container: '#10233f'
  on-primary-container: '#798bac'
  inverse-primary: '#b5c7eb'
  secondary: '#0051d3'
  on-secondary: '#ffffff'
  secondary-container: '#226afc'
  on-secondary-container: '#fefcff'
  tertiary: '#050e1a'
  on-tertiary: '#ffffff'
  tertiary-container: '#1a2430'
  on-tertiary-container: '#818b9b'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d6e3ff'
  primary-fixed-dim: '#b5c7eb'
  on-primary-fixed: '#071b37'
  on-primary-fixed-variant: '#364765'
  secondary-fixed: '#dbe1ff'
  secondary-fixed-dim: '#b3c5ff'
  on-secondary-fixed: '#00174a'
  on-secondary-fixed-variant: '#003ea6'
  tertiary-fixed: '#d9e3f4'
  tertiary-fixed-dim: '#bdc7d8'
  on-tertiary-fixed: '#121c28'
  on-tertiary-fixed-variant: '#3e4755'
  background: '#f7f9fc'
  on-background: '#191c1e'
  surface-variant: '#e0e3e6'
typography:
  headline-xl:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 34px
  headline-lg:
    fontFamily: Inter
    fontSize: 22px
    fontWeight: '700'
    lineHeight: 28px
  headline-md:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  label-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 18px
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
  label-sm:
    fontFamily: Inter
    fontSize: 10px
    fontWeight: '600'
    lineHeight: 14px
  mono-imei:
    fontFamily: JetBrains Mono
    fontSize: 15px
    fontWeight: '500'
    lineHeight: 20px
  mono-data:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style
The design system establishes a high-trust, institutional yet frictionless environment tailored for mobile device provenance, IMEI lifecycle tracking, and verified secondary market commerce. Designed natively for modern mobile viewports (baseline 393×852), it blends the operational clarity of high-grade financial tooling with the kinetic warmth of top-tier consumer marketplaces.

The aesthetic philosophy centers on **Precision Fintech**:
- **Trust Through Structure**: Strict visual hierarchy, unambiguous validation signals, cryptographic telemetry details, and verifiable status tags reinforce institutional credibility.
- **Modern Marketplace Polish**: Elevated soft cards, luminous electric accents, rhythmic negative space, and micro-interactions ensure the buying, selling, and verification workflows feel premium rather than bureaucratic.
- **Regional Grounding**: Formats, currency markers (`PKR`), regional city selectors (Lahore, Karachi, Islamabad), and government-adjacent regulatory disclosures (PTA approvals, customs cleared vs. non-compliant) are embedded naturally into standard transaction units.

## Colors
The color architecture relies on high-contrast authority balanced by clean, luminescent status surfaces.

- **Deep Navy (`#10233F`)**: Serves as the primary institutional anchor. Used for high-emphasis typography, primary actions, navigation shells, and biometric or cryptographic verification headers.
- **Electric Blue (`#246BFD`)**: The primary interactive accent. Drives key user actions, tap targets, focused inputs, active segmented controls, and hyper-critical visual anchors.
- **Slate Neutral (`#4B5563`)**: Used for secondary text, metadata labels, tertiary borders, and structural non-interactive icons.
- **Base Canvas (`#F7F9FC`) & Surface (`#FFFFFF`)**: The application operates on a crisp, off-white foundation that eliminates eye fatigue while elevating pure white layered cards.
- **Semantic Trust Indicators**:
  - **Emerald Green (`#10B981`)**: Signals authentic records, PTA registered status, pristine clean IMEI checks, and escrow completions.
  - **Amber (`#F59E0B`)**: Denotes devices currently under manual audit, pending PTA tax clearance, or incomplete counterparty confirmation.
  - **Crimson Red (`#EF4444`)**: Applied with strict containment for reported stolen flags, blacklisted IMEIs, law enforcement alerts, and high-risk counterparty warnings.

## Typography
The system employs `Inter` across all structural UI and consumer-facing copy for supreme legibility at high pixel densities, paired with `JetBrains Mono` for cryptographic, technical, and regulatory data (IMEI hashes, serial strings, transaction IDs, timestamps).

Rules for implementation:
- **Price Displays**: Currency strings must format explicitly as `PKR 245,000` using `headline-lg` or `headline-md` with tabular numerals enabled to maintain baseline alignment across multi-item lists.
- **Technical Readouts**: All 15-digit IMEI strings, carrier lock codes, and PTA tracking IDs strictly invoke `mono-imei` with spaced quad formatting (`3569 8211 4092 881`) to prevent reading errors during physical device checks.
- **Disclaimer & Micro-Copy**: Statutory text (such as PTA tax compliance caveats) must leverage `body-sm` or `label-sm` with a minimum contrast ratio of 4.5:1 against card backgrounds.

## Layout & Spacing
The layout adheres to an 8pt vertical cadence (with 4pt sub-increments for compact badges and indicators) engineered for a target canvas of 393×852 (portrait Android viewport).

- **Screen Boundaries**: Edge margins are fixed at `1rem` (16px) to maximize usable touch real estate on mobile devices while avoiding accidental edge activation.
- **Vertical Flow**:
  - Inter-card spacing sits strictly at `space-md` (16px) to maintain cohesive card stacking.
  - Section dividers and categorical breaks use `space-lg` (24px).
  - Floating action toolbars and pinned bottom verification buttons preserve safe area insets with a mandatory 16px bottom pad above gesture pills.
- **Touch Targets**: All primary interactive elements (buttons, filter chips, sheet triggers, list rows) maintain a minimum vertical height of 48px to prevent input error under one-handed thumb navigation.

## Elevation & Depth
Depth is produced through stratified tonal layering paired with warm ambient drop shadows, steering clear of stark skeuomorphism or harsh outlines.

- **Base Layer (Canvas)**: Color `#F7F9FC`. Receives standard non-interactive application scaffolding.
- **Level 1 (Card & Row Surfaces)**: Pure `#FFFFFF` background with a subtle ambient shadow: `box-shadow: 0px 4px 16px -2px rgba(16, 35, 63, 0.05), 0px 1px 2px rgba(16, 35, 63, 0.03)`. Finished with a 1px hairline border in `rgba(16, 35, 63, 0.06)`.
- **Level 2 (Modals, Overlays, and Verification Drawers)**: Pure `#FFFFFF` background with elevated projection: `box-shadow: 0px 12px 32px -4px rgba(16, 35, 63, 0.12), 0px 4px 8px -2px rgba(16, 35, 63, 0.04)`.
- **Level 3 (Floating CTA Banners & Floating Search Bars)**: Elevated by `box-shadow: 0px 8px 24px -2px rgba(36, 107, 253, 0.18)` when utilizing active brand tones, reinforcing clear tactile lift over scrolling marketplace feeds.

## Shapes
The design adopts a refined curvature scale anchored by `rounded-2xl` for primary structural elements, providing a polished, high-end mobile app feel.

- **Cards & Sheets**: Primary content cards, verification panels, and modal bottom sheets utilize `rounded-2xl` (16px).
- **Interactive Controls**: Primary inputs, search bars, and full-width buttons leverage `rounded-xl` (12px) to provide balanced, structured ergonomics.
- **Pills & Status Badges**: All verification badges, city tags, PTA indicators, and notification pips use a full rounded-full (9999px) pill treatment.

## Components

### Buttons
- **Primary Action**: Solid `#246BFD` with pure white text, 48px minimum height, `rounded-xl`, `label-lg` typography. Subtle focus glow of `0 0 0 3px rgba(36, 107, 253, 0.25)`.
- **Institutional Primary**: Solid `#10233F` with pure white text, applied for final contract verification, escrow execution, or official registry generation.
- **Secondary / Ghost**: Pure white surface, 1px border `rgba(16, 35, 63, 0.12)`, text `#10233F`. Hover/pressed state shifts to `#F7F9FC`.
- **Critical Alert Action**: Crimson Red (`#EF4444`) filled or outlined, reserved strictly for "Report Stolen" or "Dispute Registry" actions.

### Registry Badges & Chips
- **Verified PTA Status**: Full pill (`rounded-full`), `#10B981` at 10% opacity background, solid `#059669` text and leading checkmark icon. Displays "PTA Approved" or "Official Registry Match".
- **Pending Audit**: Full pill, `#F59E0B` at 12% opacity background, solid `#D97706` text with clock glyph.
- **Blacklisted / Stolen Warning**: Full pill, `#EF4444` at 12% opacity background, solid `#DC2626` text with shield alert icon.
- **Location Selector Chip**: Full pill, surface white, 1px solid `rgba(16, 35, 63, 0.1)`, displaying regional clusters (e.g., "Lahore • Hafeez Centre", "Karachi • Saddar", "Islamabad • Blue Area").

### IMEI Verification Cards
- Multi-tier card with a distinct 4px top accent border reflecting registry status (Green = Clean, Red = Alert, Amber = Verification In Progress).
- Features dual-row monospace layout for IMEI 1 and IMEI 2, accompanied by a quick-action "Copy" and "Verify against Police DB" trigger.
- **PTA Distinction Disclaimer Box**: An integrated muted callout container at the foot of the card: soft slate background (`rgba(75, 85, 99, 0.05)`), featuring a small info shield and micro-prose explaining the distinct separation between legal PTA regulatory tax payment status and internal ownership transfer verification.

### Form Inputs
- 52px touch-friendly height, pure white surface, 1.5px border in `rgba(16, 35, 63, 0.12)`.
- Active focus state transitions to electric blue `#246BFD` border with a 3px soft blue ring.
- IMEI input variant features built-in character grouping formatting, an in-line camera icon for physical barcode/box scanning, and instant verification debounce feedback.

### Marketplace Device Cards
- Structured layout with 1:1 hardware imagery container, floating verified badge top-right, and immediate price readout in `PKR` (e.g., `PKR 185,000`).
- Footer micro-row displaying physical battery health, PTA approval badge, and city location tag.