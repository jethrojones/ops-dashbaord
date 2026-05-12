# Glassline Design Tokens

This file is intentionally standalone so the dashboard design can be tweaked without rewriting the build guide.

```yaml
version: alpha
name: Glassline
description: Fog-grey neutrals with a cobalt pinprick.
colors:
  primary: "#0F1419"
  secondary: "#4A5568"
  tertiary: "#2C5EF5"
  neutral: "#F1F3F5"
  surface: "#FFFFFF"
  on-primary: "#FFFFFF"
typography:
  display:
    fontFamily: Geist
    fontSize: 3.75rem
    fontWeight: 600
    letterSpacing: "-0.03em"
  h1:
    fontFamily: Geist
    fontSize: 2.25rem
    fontWeight: 600
    letterSpacing: "-0.02em"
  body:
    fontFamily: Geist
    fontSize: 0.95rem
    lineHeight: 1.55
  label:
    fontFamily: Geist Mono
    fontSize: 0.75rem
    letterSpacing: "0"
rounded:
  sm: 6px
  md: 10px
  lg: 16px
spacing:
  sm: 8px
  md: 16px
  lg: 32px
components:
  button-primary:
    backgroundColor: "{colors.tertiary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.md}"
    padding: 12px 20px
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.primary}"
    rounded: "{rounded.lg}"
    padding: 24px
```

## Overview

Glassline is a cool, quiet palette built around high-contrast neutrals and one cobalt action color. The interface should feel calm, operational, and fast to scan.

## Colors

- **Primary (`#0F1419`):** Headlines, dense table text, and core UI copy.
- **Secondary (`#4A5568`):** Borders, captions, metadata, secondary labels, and muted icons.
- **Tertiary (`#2C5EF5`):** The sole action color. Reserve it for one primary action per screen.
- **Neutral (`#F1F3F5`):** Page foundation and quiet separation.
- **Surface (`#FFFFFF`):** Tool panels, rows, repeated cards, modals, and form areas.
- **On Primary (`#FFFFFF`):** Text on cobalt or dark surfaces.

## Typography

- **Display:** Geist, 3.75rem, 600 weight.
- **H1:** Geist, 2.25rem, 600 weight.
- **Body:** Geist, 0.95rem, 1.55 line height.
- **Label:** Geist Mono, 0.75rem, zero letter spacing.

For compact dashboards, avoid using display type inside tables, sidebars, forms, or cards. Prefer small, precise headings and consistent row heights.

## Layout Rules

- Use dense but readable tables for workflow and run lists.
- Use tabs for major settings groups.
- Use icon buttons for repeated row actions.
- Use status chips sparingly and keep labels short.
- Keep page sections unframed; use cards only for repeated items, modals, or contained tools.
- Avoid gradients, decorative blobs, and marketing-style hero sections.
- Do not introduce alternate accent colors unless the owner explicitly changes the design system.

## Starting Screens

- **Dashboard:** summary metrics, workflows table, recent failures, usage footer.
- **Workflow detail:** metadata, current schedule, last runs, manual run button, edit/export controls.
- **Run detail:** status timeline, redacted structured log, retry button, copy debug payload.
- **Settings:** service connections, notification recipients, Cloudflare resource status, users/roles.
