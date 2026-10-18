# Overheard design system

Everything in the app looks like a naturalist's field journal: hand-drawn birds in ink and watercolor on parchment. The mockups in `design/mockups/` are the visual reference; this file holds the rules.

## Themes

Two themes, chosen in settings (default: follow the system).

- **Parchment** (light): warm paper chrome, with a lighter journal page sitting on it.
- **By Candlelight** (dark): a dark room with the journal page lit warmly from the center. It is not an inverted palette. The page stays paper-colored and keeps dark ink.

### Color tokens

| Token | Parchment | By Candlelight | Use |
|---|---|---|---|
| `chromeBg` | `#ebdfc3` | `#17100a` | Screen background around the page |
| `chromeInk` | `#2a1f15` | `#f2e2c0` | Text on chrome |
| `chromeSoft` | `#665441` | `#c4a77b` | Secondary text on chrome |
| `tabBg` | `#e5d7b8` | `#120c07` | Tab bar |
| `tabSoft` | `#6e5b46` | `#a98f68` | Inactive tab |
| `rule` | `rgba(90,66,38,.25)` | `rgba(242,226,192,.14)` | Dividers on chrome |
| `accent` | `#8b2f1c` (iron-gall red) | `#e9a24f` (candle flame) | Active tab, primary button, "Listening" |
| `accentInk` | `#f7efdc` | `#1b130c` | Text on `accent` |
| `pageInk` | `#2a1f15` | `#2a1f15` | Text on the journal page (both themes) |
| `pageSoft` | `#6a5741` | `#4e3a22` | Secondary text on the page |
| `accentOnPage` | `#8b2f1c` | `#7a2812` | Red-ink notes and flourishes on the page |

**Journal page fill** (a radial gradient that reads as paper):
- Parchment: `radial-gradient(120% 90% at 50% 30%, #f6edd6, #efe3c6 60%, #e0cfa8)`
- Candlelight: `radial-gradient(115% 100% at 50% 38%, #ecd3a4, #d8b986 50%, #b8935e 85%, #8f6d42)`

Keep page text inside the lit area. Don't let the candlelight edges get darker than `#8f6d42`, or the dark ink stops being readable.

## Typography

| Role | Face | Use |
|---|---|---|
| Display | IM Fell English (and italic) | Screen titles, walk titles |
| Small caps label | IM Fell English SC, letter-spacing 0.1–0.14em | "Listening", "Heard · 6 species", tab-like labels |
| Body | EB Garamond 400/500/600 | UI text, lists, buttons |
| Hand | Caveat 500/600 | Annotations on the page: bird labels, dates, notes, flourishes |

All four are on Google Fonts. Bundle them in the app (check each license; all are OFL). Species names in lists are set in italic body. Numbers use tabular figures.

## Bird art

- **Style:** dip-pen ink linework with light pencil construction lines, a soft watercolor wash and visible hatching. Accurate field marks.
- **Generation:** `gemini-3-pro-image` via the Batch API. Always prompt for a **flat white background** and no text, frame or border. See `art/model-comparison/` for the trial and prompts.
- **Cut-out:** run background removal (e.g. BiRefNet) to get a transparent PNG. Birds always composite onto one shared page, never as separate rectangles.
- **Variations:** edit the base image (season, perch, pose), keeping the same bird and style. Review before they go live.

## Page composition rules

- **Size by call count** on the Listen and Journal pages. More calls make a bigger bird, with a minimum and maximum size so one chatty bird can't dominate. On Listen, a bird grows as repeat calls come in.
- **Cluster** birds closely with slight overlap of empty margins. Avoid a grid.
- **Flock cards:** every bird is the same size, in an even row of up to 3, then "+N more".
- **Labels** are handwritten (Hand font) next to each bird: name plus `×count`. Use `pageSoft` for the count.
- **Being sketched:** a newly heard bird appears faint and grayscale inside a dashed red-ink circle, with "sketching…", then draws in.
- **Naturalist flourish** for rare birds: a red-ink (`accentOnPage`) handwritten note with a hand-drawn arrow, rotated about -3°. Example: "uncommon here this late in October". Rarity comes from BirdNET's location/week occurrence score. Size still means only call count.
- **Life birds** get a ★ in the species list, and a flourish if they're also rare.

## Components

- **Buttons:** pill-shaped, 48 pt tall. Primary is filled `accent`; secondary is a 1.5 pt outline in `chromeInk`.
- **Touch targets:** at least 44 pt.
- **Tab bar:** Listen, Journal, Flock, Me. Thin-stroke line icons (1.6 pt) and no emoji.
- **Journal page:** 6 pt corner radius and a soft shadow in Parchment (a warm glow in Candlelight), inset 12 pt from the screen edges.
