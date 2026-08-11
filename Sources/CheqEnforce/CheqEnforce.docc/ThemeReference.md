# Theme Reference

Complete reference for the `enforce_theme.json` document and the ``EnforceTheme`` type: every key, its type, default, and the UI it styles.

This document is the **canonical cross-SDK specification**: the same theme JSON is consumed by the CHEQ web and Android SDKs, which implement to match the behavior described here.

## Overview

A theme has two independent sections, `banner` and `modal`. **Every key is optional**: omit anything and it falls back per the resolution rules below. An empty theme (`{}`) is valid and renders the custom UI entirely with light-mode defaults.

```json
{
  "banner": { ... },
  "modal":  { ... }
}
```

### Resolution rules

1. **Buttons**: each property resolves as `specific button → buttons.global → framework default`, *per property* (e.g. a button may take its `backgroundColor` from `acceptAll` and its `borderRadius` from `global`).
2. **Everything else**: `value → framework default`.
3. **Invalid values never fail the UI**: a bad hex string or unknown font name is logged (subsystem `Cheq`) and the default is used. A structurally invalid document (wrong types, malformed JSON) fails to *decode*, and the error surfaces at `EnforceTheme(bundleFile:)` / `JSONDecoder`.
4. **Empty string `""` means "not set"** and falls through like an omitted key.
5. Themed UI is **light-mode based**; the `appearance` configuration setting is ignored when a theme is present (a log message notes this).

## Banner keys

The banner is a bottom sheet that slides up from the bottom edge.

| Key | Type | Default | Styles |
|---|---|---|---|
| `logoUrl` | string (URL) | none | Remote logo image (raster only, see Logo rules) |
| `logoImage` | string | none | Platform-local image resource name (iOS: asset catalog) |
| `logoAlignment` | `"left"` \| `"center"` \| `"right"` \| `"full"` | `"center"` | Logo placement at the top of the sheet |
| `backgroundColor` | hex color | `#FFFFFF` | Sheet background |
| `separatorColor` | hex color | none (no line drawn) | 1pt divider between description and buttons |
| `overlayColor` | hex color | `#00000080` (black 50%) | Dimming overlay behind the sheet |
| `summary.description` | TextStyle | see TextStyle defaults | The banner message text |
| `buttons.order` | array of button names | `["acceptAll", "rejectAll", "openModal", "close"]` | Top-to-bottom button order (see Button ordering) |
| `buttons.acceptAll` | ButtonStyle | primary defaults | Accept All button |
| `buttons.rejectAll` | ButtonStyle | primary defaults | Deny All button (defaults match Accept All so neither consent choice is visually privileged, per GDPR guidance) |
| `buttons.openModal` | ButtonStyle | secondary defaults | Preferences button |
| `buttons.close` | ButtonStyle | text-only defaults | Close button |
| `buttons.global` | ButtonStyle | n/a | Fallback for any missing per-button value |

> Note: which buttons *appear* is not controlled by the theme; it comes from the remote `environment.json` (`bannerConfig`). The theme only styles buttons the remote config enables.

## Modal keys

The consent preferences modal (category toggles).

| Key | Type | Default | Styles |
|---|---|---|---|
| `presentationStyle` | `"card"` \| `"fullScreen"` | `"card"` | Centered card over a dimmed background, or full-screen overlay |
| `logoUrl` / `logoImage` / `logoAlignment` | as banner | as banner | Logo above the title |
| `backgroundColor` | hex color | `#FFFFFF` | Card / screen background |
| `separatorColor` | hex color | none | Divider between the summary and the categories |
| `overlayColor` | hex color | `#00000080` | Dimming overlay (not visible in `fullScreen`) |
| `summary.title` | TextStyle | 18pt bold, centered, `#000000` | Modal title |
| `summary.description` | TextStyle | 14pt regular, centered, `#000000` | Modal description |
| `buttons.order` | array of button names | `["acceptAll", "rejectAll", "save", "close"]` | Button order (see Button ordering) |
| `buttons.acceptAll` | ButtonStyle | primary defaults | Accept All |
| `buttons.rejectAll` | ButtonStyle | primary defaults | Deny All (defaults match Accept All, per GDPR guidance) |
| `buttons.save` | ButtonStyle | secondary defaults | Save |
| `buttons.close` | ButtonStyle | text-only defaults | Cancel/Close |
| `buttons.global` | ButtonStyle | n/a | Fallback for missing per-button values |
| `categories.toggleOnColor` | hex color | system blue | Switch on-state tint |
| `categories.toggleOffColor` | hex color | `#D9D9D9`-equivalent gray | Switch off-state track |
| `categories.separatorColor` | hex color | none (no lines drawn) | 1pt divider between category rows; never drawn after the last row |
| `categories.title` | TextStyle | 16pt bold, `#000000` | Category name label |
| `categories.description` | TextStyle | 14pt regular, `#000000` | Category description label |

### Button ordering

`buttons.order` is an array of button names, e.g. `"order": ["rejectAll", "acceptAll", "close"]`:

- Named buttons render first, in the given order; buttons not listed follow in the default order.
- Duplicate names are ignored (first occurrence wins) and logged.
- Unknown names, and names for buttons the remote configuration doesn't show, are logged and skipped.
- Omitting `order` keeps the default order shown in the tables above.

## Shared blocks

### TextStyle

| Key | Type | Default |
|---|---|---|
| `fontName` | string (platform font name; iOS: PostScript name) | system font |
| `fontSize` | number | role-dependent (see tables above) |
| `fontWeight` | `"regular"` \| `"medium"` \| `"semibold"` \| `"bold"` | role-dependent | 
| `textAlignment` | `"left"` \| `"center"` \| `"right"` \| `"justified"` \| `"natural"` | role-dependent |
| `textColor` | hex color | `#000000` |

- `fontWeight` applies only when no custom `fontName` is set (a named font carries its own weight).
- Prefer `"natural"` alignment for body text: it follows the user's language direction (left for LTR, right for RTL). Use `"left"`/`"right"` only to force a fixed edge.
- An unresolvable `fontName` logs and falls back to the system font.

### ButtonStyle

| Key | Type | Primary default (acceptAll, rejectAll) | Secondary default (openModal, save) | Text-only default (close) |
|---|---|---|---|---|
| `backgroundColor` | hex color | system blue | `#EBEBEB`-equivalent gray | transparent |
| `textColor` | hex color | `#FFFFFF` | `#000000` | gray |
| `fontName` | string | system | system | system |
| `fontSize` | number | 16 | 16 | 16 |
| `fontWeight` | weight enum | `semibold` | `regular` | `regular` |
| `borderColor` | hex color | transparent | transparent | transparent |
| `borderWidth` | number | 0 | 0 | 0 |
| `borderRadius` | number | 8 | 8 | 8 |

## Cross-platform conventions

These rules keep one theme document rendering identically on iOS, Android, and web:

- **Hex colors**: `#RGB`, `#RRGGBB`, or `#RRGGBBAA` with **alpha last** (CSS convention); the leading `#` is optional. Android implementations must not pass 8-digit values directly to `Color.parseColor`, which expects alpha-first `#AARRGGBB`; reorder first.
- **Numbers are device-independent units**: points on iOS, dp/sp on Android, px on web.
- **Logo source precedence**: programmatic image (native API only, not expressible in JSON) → `logoImage` (platform-local resource) → `logoUrl` (remote fetch, short timeout, silent fallback to no logo on failure).
- **`logoUrl` must be a raster format** (PNG recommended; transparency respected). SVG works only on web, because native mobile SDKs cannot decode SVG at runtime. SVG logos should be supplied via each platform's local asset pipeline instead.
- **Logo rendering (iOS)**: 40pt tall, aspect-fit. `full` spans the container width; over-wide logos compress proportionally to fit rather than overflow.
- **File name convention**: `enforce_theme.json` (lowercase + underscores, required for Android `res/raw` compatibility). On iOS, load with `EnforceTheme(bundleFile: "enforce_theme")`.
- **Unknown keys are ignored** by all decoders (forward compatibility: new tokens must not break older SDK versions).

## Full example

```json
{
  "banner": {
    "logoImage": "BrandLogo",
    "logoAlignment": "center",
    "backgroundColor": "#FFFFFF",
    "separatorColor": "#E5E5E5",
    "overlayColor": "#00000080",
    "summary": {
      "description": { "fontName": "AvenirNext-Regular", "fontSize": 14, "fontWeight": "regular", "textAlignment": "natural", "textColor": "#1A1A1A" }
    },
    "buttons": {
      "acceptAll": { "backgroundColor": "#1E478F", "textColor": "#FFFFFF", "fontSize": 16, "fontWeight": "semibold", "borderRadius": 8 },
      "rejectAll": {},
      "openModal": {},
      "close":     { "backgroundColor": "#00000000", "textColor": "#888888" },
      "global":    { "backgroundColor": "#EBEBEB", "textColor": "#000000", "borderRadius": 8 }
    }
  },
  "modal": {
    "presentationStyle": "card",
    "logoImage": "BrandLogo",
    "logoAlignment": "center",
    "backgroundColor": "#FFFFFF",
    "separatorColor": "#E5E5E5",
    "overlayColor": "#00000080",
    "summary": {
      "title":       { "fontSize": 18, "fontWeight": "bold", "textColor": "#1A1A1A" },
      "description": { "fontSize": 14, "textColor": "#1A1A1A" }
    },
    "buttons": {
      "acceptAll": { "backgroundColor": "#1E478F", "textColor": "#FFFFFF", "fontWeight": "semibold", "borderRadius": 8 },
      "rejectAll": {}, "save": {}, "close": {},
      "global":    { "backgroundColor": "#EBEBEB", "textColor": "#000000", "borderRadius": 8 }
    },
    "categories": {
      "toggleOnColor": "#1E478F",
      "toggleOffColor": "#D9D9D9",
      "separatorColor": "#E5E5E5",
      "title":       { "fontSize": 16, "fontWeight": "bold", "textColor": "#1A1A1A" },
      "description": { "fontSize": 14, "textColor": "#666666" }
    }
  }
}
```
