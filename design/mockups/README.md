# Mockups

The source for the screen mockups on the Overheard Screens design canvas: https://claude.ai/artifact/GSRabYsYPQJsSGMqQmDBnP (private).

| File | Screen |
|---|---|
| `Main.dc.html` | Listen (live walk) |
| `Journal.dc.html` | Journal page (finished walk) |
| `Feed.dc.html` | Flock (friends' walks) |
| `*Night.dc.html` | The same screen in the By Candlelight theme |

Each screen takes a `theme` prop (`parchment` or `candlelight`), and the theme colors live in its `THEMES` script. The bird images are `/_blob/...` assets stored on the canvas; they're the Gemini 3 Pro trial images from `art/model-comparison/`.

Rules and tokens: `docs/design.md`.
