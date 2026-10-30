# Homepage and README media (HyperFrames)

The product loops on alliswell.space, the one-minute film and the README animations are HTML
compositions rendered to video with [HyperFrames](https://github.com/heygen-com/hyperframes)
(ADR-0061). The compositions and their inputs are committed; renders, the music file and the
copied screenshots are not.

| Composition | Output | What it shows |
| --- | --- | --- |
| `compositions/loop-hero.html` | `loop-hero` (12 s) | Home leans in, a task is ticked off, the urgent reminder rings on Silent |
| `compositions/loop-tour-*.html` | `loop-tour-{tasks,notes,alarms,files,repeats}` | One tour pane each, 9 to 10 s |
| `compositions/loop-mcp.html` | `loop-mcp-en`, `loop-mcp-tr` | A request to an assistant, the approval, the real app updating |
| `compositions/loop-selfhost.html` | `loop-selfhost` (10 s) | `docker compose up` and the web app answering |
| `compositions/film.html` | `film-en`, `film-tr` (56 s, music) | Eight scenes; words from `film/film-<lang>.json` |

Every loop's last frame is its first, so it plays without a seam. Loops carry no words of their
own except the MCP loop, which is rendered per language. The film's captions
(`film/film-<lang>.vtt`) and the page's transcript say the same lines as `film/film-<lang>.json`.

## Making them

```bash
cd media/hyperframes
npm run shots      # copies the screenshots (and the hero photograph) into assets/shots/
npm run render     # or: node scripts/render.mjs loop-hero film-tr
cd ../.. && npm run media:promote   # encodes, hashes, writes apps/landing/src/home/media.json
npm run check:media
```

`npm run shots` takes the film's photograph from `media/.cache` when the original is there
(`npm run media:promote -- photo-fog` downloads it) and otherwise from the promoted JPEG. Renders need ffmpeg and the CLI pinned in
`scripts/render.mjs` (`npx` fetches it and its own headless Chrome). Look at frames before
promoting: `ffmpeg -ss 5 -i renders/loop-hero.mp4 -frames:v 1 frame.png`.

## What it is made of

- **Screenshots:** the committed captures in `/screenshots` and `/docs/screenshots`, from the
  demo seed (docs/SCREENSHOTS.md). No real user data.
- **Photograph:** "Brouillard dans la vallée de la Savoureuse au coucher du Soleil" by Thomas
  Bresson, [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/), via
  [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Vallee-brouillard.jpg); cropped,
  resized and re-encoded. Credited on the page's footer.
- **Type:** Wix Madefor Display and Text, SIL Open Font License (`assets/fonts/OFL.txt`).
- **Music:** composed for this project by `scripts/music.py` (sine partials, a fixed seed, no
  samples), so there is no third-party licence. `python3 scripts/music.py 56` regenerates the
  exact file.
- **Icons:** Lucide (ISC), drawn inline.
