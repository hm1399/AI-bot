# AI Bot App DESIGN.md

> Scope: this file applies only to `app/`.
>
> Source inspiration: `https://getdesign.md/design-md/linear.app/DESIGN.md`, translated for a Flutter desktop application.
>
> Positioning: this is a Linear-inspired operator workspace for AI-bot. It should feel precise, dark, compact, and technical. It must not drift into a marketing site, a documentation site, or a playful chat app aesthetic.

## 0. Product Scope and Non-Goals

AI Bot App is a desktop control surface for a backend-driven AI assistant system. It has a real connection flow, a runtime dashboard, backend-driven chat, task and event management, a control center, and backend settings. The UI should feel like a serious product tool used to monitor state and trigger actions quickly.

This project is not a clone of Linear's information architecture. The visual language should be close to Linear, but the product structure must remain AI-bot specific.

### Keep

- A separate connection entry flow before the main app shell.
- The current in-app six-area structure: `home`, `chat`, `agenda`, `tasks`, `control`, `settings`.
- Direct visibility of connection, demo, and backend readiness states.
- Explicit product copy that tells the user what is ready, what is simulated, and what is not yet available.
- Dense, tool-like interaction patterns centered on lists, panels, inline actions, dialogs, and bottom sheets.

### Do Not Introduce

- A marketing hero layout.
- An issue-tracker-style navigation model that displaces the current AI-bot workspace semantics.
- Large decorative gradients, ambient blobs, glassmorphism, or bright chromatic backgrounds.
- Web landing-page navigation patterns such as top-level marketing nav, social proof, pricing-style cards, or big dual CTA hero sections.
- Notion-style paper surfaces, beige backgrounds, or editorial notebook styling.

## 1. Visual Theme & Atmosphere

Dark mode is the native medium. The base canvas should be near-black, with hierarchy built through very small luminance steps instead of loud color blocks. Surfaces should emerge from darkness in a controlled way: canvas first, then panel, then elevated surface, then hover surface.

The overall impression should be:

- engineered
- quiet
- compact
- technical
- cool-toned
- high signal, low ornament

Linear's signature tension should remain visible:

- compressed, precise typography
- whisper-thin borders
- minimal but sharp accent usage
- very restrained motion
- dense UI without visual clutter

For AI-bot specifically, the atmosphere should read as "operator console" rather than "project management dashboard". Voice handoff, device state, task queue, reminders, and backend readiness should feel like parts of one system control surface.

## 2. Color Palette & Roles

### Core Dark Tokens

| Token | Hex | Role |
|---|---|---|
| `canvas` | `#08090A` | App background, deepest shell background |
| `panel` | `#0F1011` | Primary panels, navigation surfaces, app shell containers |
| `surface` | `#191A1B` | Cards, dialogs, bottom sheets, input surfaces |
| `surfaceHover` | `#28282C` | Hovered list rows, selected neutral surfaces |
| `textPrimary` | `#F7F8F8` | Main headings and primary text |
| `textSecondary` | `#D0D6E0` | Body text and key secondary text |
| `textTertiary` | `#8A8F98` | Help text, placeholder text, supportive copy |
| `textQuaternary` | `#62666D` | Disabled states, timestamps, minor metadata |
| `brandIndigo` | `#5E6AD2` | Primary action background |
| `accentViolet` | `#7170FF` | Focus, active state, selected state, links |
| `accentHover` | `#828FFF` | Hover state for accent elements |
| `success` | `#27A644` | Success and healthy active states |
| `successSoft` | `#10B981` | Success pills and completion tags |
| `borderPrimary` | `#23252A` | Strong separators on dark surfaces |
| `borderSecondary` | `#34343A` | Medium separators |
| `borderTertiary` | `#3E3E44` | Lightest solid border |
| `borderSubtle` | `rgba(255,255,255,0.05)` | Default subtle border |
| `borderStandard` | `rgba(255,255,255,0.08)` | Card, input, sheet border |
| `overlayPrimary` | `rgba(0,0,0,0.85)` | Modal barrier |

### AI-bot Semantic States

Linear's palette is intentionally narrow, but AI-bot needs strong operational states. Preserve the distinctions, while rendering them with Linear discipline.

| State | Preferred treatment | Notes |
|---|---|---|
| Connected / healthy | `success` or `successSoft` text and pill treatment | Keep obvious at a glance |
| Reconnecting / degraded | muted amber or subdued warning accent | Must remain visible; do not hide it as a tiny icon |
| Error / disconnected | restrained red ring, text, or banner accent | Clear but not neon |
| Demo mode | muted indigo-lavender treatment | Prefer cool lavender over bright orange in future UI work |
| Focused / selected | `accentViolet` ring or active surface | Use sparingly |

### Usage Rules

- The interface should remain mostly grayscale.
- `brandIndigo` and `accentViolet` are reserved for primary action, selection, focus, and key active affordances.
- Do not flood cards, banners, or screen backgrounds with accent color.
- Primary text should be `#F7F8F8`, not pure white.
- Borders on dark surfaces should usually be semi-transparent white rather than opaque gray fills.

## 3. Typography Rules

### Font Family

- Primary font: `Inter`
- Preferred if available: variable font behavior close to Linear's Inter Variable
- Monospace companion: `Berkeley Mono` if installed; otherwise a clean monospace fallback is acceptable

If the Flutter app does not yet ship Inter, future UI work should still aim for Inter-like proportions and weights rather than generic Material defaults.

### Weight System

- Reading weight: `400`
- Signature UI emphasis weight: `510` equivalent
- Strong emphasis: `590` equivalent

In Flutter, where true `510` and `590` may not exist without variable font support:

- map `510` to the closest practical medium emphasis, usually `w500`
- map `590` to the closest practical semibold emphasis, usually `w600`
- avoid heavy `w700` unless there is a rare accessibility-driven reason

### Scale

| Role | Size | Weight | Line Height | Letter Spacing | Flutter intent |
|---|---|---|---|---|---|
| Display | `48` | `510` | `1.00` | `-1.056` | Rare; only for connection or empty-state hero moments |
| Heading 1 | `32` | `400` | `1.13` | `-0.704` | Major screen titles |
| Heading 2 | `24` | `400` | `1.33` | `-0.288` | Section headlines |
| Heading 3 | `20` | `590` | `1.33` | `-0.24` | Card headers, important panel titles |
| Body Large | `18` | `400` | `1.60` | `-0.165` | Introductory explanatory text |
| Body | `16` | `400` | `1.50` | `0` | Standard text |
| Body Medium | `16` | `510` | `1.50` | `0` | Emphasized rows, navigation labels |
| Small | `15` | `400` | `1.60` | `-0.165` | Secondary supporting copy |
| Caption | `14` | `510` | `1.50` | `-0.182` | Small section labels |
| Meta | `13` | `510` | `1.50` | `-0.13` | Timestamps, metadata |
| Label | `12` | `510` | `1.40` | `0` | Button labels, pills, compact controls |
| Mono Body | `14` | `400` | `1.50` | `0` | Technical values, IDs, code-like text |
| Mono Label | `12` | `400` | `1.40` | `0` | Technical tags and compact metadata |

### Typography Principles

- Large headings use negative letter spacing.
- Below `16px`, spacing should be near-normal and readability first.
- Avoid oversized visual contrast between heading and body text. Linear feels compact because hierarchy is tight, not theatrical.
- Use monospace only where technical meaning benefits from it: IDs, command snippets, state labels, compact metadata.

## 4. Layout Principles

### Product Structure

The UI must preserve the current app structure:

- `Connect` remains a dedicated entry screen outside the main shell.
- `Demo` remains a separate non-primary route outside the main shell.
- The main shell keeps the current six areas: `Home`, `Chat`, `Agenda`, `Tasks`, `Control`, `Settings`.
- The app-wide connection state must stay visible at shell level.
- On wide screens, the current shell may use a left sidebar. On compact screens, it may collapse to the bottom dock. Both are valid expressions of the same information architecture.

### Density

The app should feel denser than stock Material, but not cramped.

- default spacing grid: `4, 8, 12, 16, 20, 24, 32`
- primary rhythm: `8, 16, 24, 32`
- use `12` and `16` frequently inside cards and forms
- use `24` and `32` to separate major sections

### Panels

- Prefer stacked panels, cards, lists, and inline action bars.
- Use panels to separate functional groups, not to decorate the page.
- Screen backgrounds should blend into the shell; cards should do the organizational work.

### Page Semantics

- `Home` is a runtime dashboard.
- `Chat` is a system conversation and voice handoff workspace.
- `Tasks` is list-and-dialog management, not a kanban board.
- `Control` is an operations console.
- `Settings` is a backend configuration form.

Future UI work must preserve those semantics even when restyling visuals.

## 5. Border Radius & Shape

| Token | Value | Use |
|---|---|---|
| `radiusMicro` | `2` | subtle badges |
| `radiusSmall` | `4` | compact containers |
| `radiusControl` | `6` | buttons, text fields, segmented controls |
| `radiusCard` | `8` | cards, list panels |
| `radiusPanel` | `12` | sheets, dialogs, larger grouped panels |
| `radiusLarge` | `22` | rare larger floating surfaces |
| `radiusPill` | `9999` | chips, filters, status pills |

Shape should stay restrained:

- no oversized playful rounding
- no iOS-style bubble softness
- no square brutalism either

## 6. Depth, Borders, and Elevation

Linear-like depth on dark surfaces should be achieved primarily with:

- luminance stepping
- subtle border opacity
- occasional ring-style shadows

Not with:

- large blurry Material shadows
- colored glow effects
- dramatic lifted cards

### Elevation Model

| Level | Treatment | Use |
|---|---|---|
| `Flat` | `canvas` only | app background |
| `Panel` | `panel` + subtle border | shell containers |
| `Surface` | `surface` + `borderStandard` | cards, forms, list panels |
| `Hover` | `surfaceHover` or slightly brighter fill | hovered rows and controls |
| `Elevated` | `surface` + ring or light shadow | menus, popovers, floating toolbars |
| `Dialog` | `surface` + stronger multi-layer shadow | alerts, modal dialogs, command surfaces |
| `Focus` | 2px accent ring | keyboard focus and important active fields |

### Border Rules

- Cards and inputs should usually have visible borders.
- Borders on dark mode should usually be `rgba(255,255,255,0.05)` to `rgba(255,255,255,0.08)`.
- Avoid relying on `elevation` alone for card separation.
- Prefer `shape + side + fill` over heavy drop shadow.

## 7. Component Stylings

### App Shell

- Keep the shell compact and dark.
- The top connection status bar must remain immediately visible and high-contrast.
- The bottom navigation may remain structurally the same, but should visually move toward a compact dark dock with subtle active indication and less default Material pill behavior.
- The current wide-screen sidebar is valid because it already exists in the active product shell; future redesigns should preserve the same AI-bot information architecture instead of drifting into a generic issue tracker.

### Buttons

#### Primary

- Fill: `brandIndigo`
- Text: white
- Radius: `6`
- Weight: medium emphasis
- Hover: toward `accentHover`

Use for:

- primary save / create / connect actions
- the single dominant action in a local area

#### Secondary / Ghost

- Fill: near-transparent white, around `rgba(255,255,255,0.02)` to `0.04`
- Border: `borderPrimary` or `borderStandard`
- Text: `textSecondary`

Use for:

- refresh
- alternate actions
- toolbar controls

#### Tonal Buttons

Current UI uses many `FilledButton.tonal` variants. Future styling should make these feel like compact dark utility controls, not pastel Material pills.

### Inputs

- Dark surface fill
- Visible subtle border
- Radius `6`
- Focus ring in `accentViolet`
- Placeholder and helper copy in tertiary text
- Error ring in restrained red

Avoid default bright Material outlines and default blue focus behavior.

### Cards and Panels

- Default card fill should be `surface`
- Border should usually be `borderStandard`
- Radius `8`
- Padding usually `16` or `20`
- Hover can slightly increase surface luminance or border contrast

Cards must remain functional containers. Avoid decorative illustration cards or oversized marketing tiles.

### Chips, Tags, and Status Pills

- Use full pill or near-pill shape
- Keep text small and crisp
- Success pills can use semi-transparent green backgrounds
- Neutral pills should use border + transparent fill
- Version or compact badges can use `radiusMicro`

### Dialogs and Bottom Sheets

- Radius `12`
- Use `surface` with visible border
- Keep actions aligned and compact
- Avoid giant airy dialogs
- Dialog copy should remain explicit about constraints and consequences

### Lists and Rows

- Prefer list rows with clear primary text, secondary supporting line, and trailing actions
- Hover and selection should be understated
- Dense content is acceptable as long as hierarchy stays clean
- Rows should feel like control surfaces, not chat bubbles or social feed cards

### Chat

The chat page should remain tool-like:

- session summary panel first
- voice handoff status panel second
- message stream next
- compact composer at bottom

Chat should not become playful, rounded, or consumer-messenger-like. Future message styling should move away from bright blue Material bubbles and toward darker panel logic with accent reserved for active user emphasis only.

### Settings

The settings page is an operational form, not a preferences toybox.

- Use dense form panels
- Keep warning and limitation copy visible
- Use muted but clear distinction for config-only fields
- Do not hide important caveats in tooltips only

### Tasks and Events

- Stay list-first
- Keep segmented switching between tasks and events
- Use dialogs for create and edit flows unless product scope changes
- Avoid turning this into a kanban or roadmap board by default

### Control Center

- Preserve its identity as an operations panel
- Use grouped surfaces for commands, notifications, and reminders
- Keep quick actions obvious
- Reminders and notifications should feel like inline system controls, not like content cards

## 8. Interaction and Motion

### Motion

- Keep transitions short: roughly `120ms` to `180ms`
- Favor opacity, border, and surface tone changes
- Avoid bounce, overshoot, scaling theatrics, or springy playful motion

### Hover

- Slightly brighten surface or border
- Do not create dramatic hover lifts

### Focus

- Always visible
- Prefer 2px accent ring or a crisp border transition
- Keyboard focus must be clearer than hover

### Pressed

- Slight darkening or compression of contrast
- No heavy scale-down effect

### Disabled

- Lower contrast
- Preserve legibility
- Do not drop disabled text into near-invisible gray

## 9. Responsive and Platform Behavior

This app is desktop-first even if Flutter web support exists.

### Desktop First

- Design primarily for desktop widths and pointer interaction.
- Keep touch targets reasonable, but do not let mobile heuristics bloat the desktop UI.
- Use tighter spacing and stronger information density than a typical phone-first Flutter app.

### Mobile and Narrow Widths

- Collapse stacked action rows cleanly.
- Preserve the same functional order; do not invent alternate IA.
- On narrow layouts, reduce spacing before reducing hierarchy clarity.

## 10. Flutter Translation Rules

This document is intended for Flutter-native implementation, not HTML/CSS recreation.

### Theme Architecture

- Use `ThemeData` with `useMaterial3: true`, but do not rely on stock Material styling.
- Do not use `ColorScheme.fromSeed` for future theme work.
- Use explicit `ColorScheme` values plus `ThemeExtension` for custom tokens.

### Token Targets

When implementing this design, define tokens for:

- shell backgrounds
- panel backgrounds
- surface backgrounds
- hover surfaces
- border subtle / standard / strong
- focus ring
- spacing scale
- radius scale
- status semantics

### Theme Areas That Matter

Future visual work should explicitly theme:

- `NavigationBarThemeData`
- `CardThemeData`
- `InputDecorationTheme`
- `FilledButtonThemeData`
- `OutlinedButtonThemeData`
- `TextButtonThemeData`
- `ChipThemeData`
- `DialogThemeData`
- `BottomSheetThemeData`
- `SegmentedButtonThemeData`
- `ListTileThemeData`

### Implementation Intent

- Prefer explicit `Container`, `DecoratedBox`, `shape`, and `side` control when Material defaults get in the way.
- Prefer crisp dark surfaces over generated tonal palettes.
- Prefer border-defined surfaces over shadow-defined surfaces.

## 11. Do's and Don'ts

### Do

- Keep the UI dark-mode-native.
- Use cool neutral surfaces with minimal chroma.
- Reserve indigo-violet accents for important interactive states.
- Keep typography compact, precise, and slightly compressed.
- Preserve the current AI-bot information architecture and state visibility.
- Keep warning and backend-readiness copy explicit.
- Treat this app like an operator console.

### Don't

- Do not build a Linear marketing page inside the app.
- Do not introduce beige, paper-like, or editorial surfaces.
- Do not use large gradients, glass blur panels, or decorative background art.
- Do not hide connection state inside low-priority UI.
- Do not replace existing direct-action controls with ornamental dashboards.
- Do not use generic bright Material blue as the default accent.
- Do not make cards fluffy, soft, or overly rounded.
- Do not overuse purple; one accent is enough.
- Do not turn `Tasks` into a board view or `Chat` into a consumer messenger unless explicitly requested.

## 12. Agent Guidance for Future UI Work

When an AI agent updates Flutter UI in `app/`, it should follow this order:

1. preserve existing app structure and product semantics
2. move surfaces, controls, and typography toward the Linear-inspired token system
3. reduce default Material appearance
4. keep operational states obvious
5. prefer subtle borders, dark surfaces, compact spacing, and restrained accent usage

If there is a conflict between "looking more like Linear" and "preserving AI-bot's real workflow clarity", preserve AI-bot's workflow clarity and adapt the styling more carefully.
