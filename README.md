# RBLX SCRPT HUB

A universal **Roblox script hub GUI** powered by the public **ScriptBlox API**
([docs.scriptblox.com](https://docs.scriptblox.com)).

Search the whole ScriptBlox catalogue, browse what is trending, and execute
scripts - all from one clean, mobile-friendly GUI. **This repo is standalone
and NOT connected to the Spider-Man Movement Engine project.**

---

## Load (executor)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/TheStrongestOfTomorrow/Rblx-SCRPT-HUB/main/hub.lua?v=1.0"))()
```

Raw file: https://raw.githubusercontent.com/TheStrongestOfTomorrow/Rblx-SCRPT-HUB/main/hub.lua

> Note: raw.githubusercontent.com can cache for ~5 minutes after an update.
> The `?v=1.0` helps your executor skip its own cached copy. To confirm the
> newest build is running, open the (F9) console and look for:
> `[RBLX SCRPT HUB v1.0] ready`

## Features

- **SEARCH / TRENDING / LATEST** tabs, live from ScriptBlox
- Search filters via the official API parameters:
  - `SORT` cycle: updated -> most viewed -> top liked (`sortBy`)
  - `KEYLESS: ON/OFF` (`key=0`)
  - `HIDE PATCHED: ON/OFF` (`patched=0`)
- Pagination (`Page x / y`) for search + latest
- One-tap **EXEC** on every result row
- Detail view: script source preview, **EXECUTE**, **COPY SRC**, **KEY LINK**,
  features + owner (fetched per script via `/api/script/:slug`)
- Badges: `VERIFIED` / `KEY` / `PAID` / `UNIVERSAL` / `PATCHED`
- Scripts with no embedded source (e.g. trending) are auto-fetched from
  `/api/script/raw/:slug`
- Draggable panel, **X** close button, draggable floating **HUB** icon
- Mobile friendly: tap targets, fit-to-screen panel, touch dragging

## Controls

| Action                | How                                                    |
|-----------------------|--------------------------------------------------------|
| Open / close the hub  | `RightShift` (PC) **or** tap the floating HUB icon     |
| Move the HUB icon     | Drag it anywhere (it stays clamped on screen)          |
| Close the panel       | `X` button (top-right of the panel)                    |
| Move the panel        | Drag the top bar                                       |
| Search                | Type in the box + `SEARCH` button (or press Enter)     |
| Open a script         | Tap a result row                                       |
| Execute instantly     | `EXEC` button on a result row                          |

## How it works

1. The hub calls ScriptBlox endpoints through `game:HttpGet`
   (`/api/script/search`, `/api/script/trending`, `/api/script/fetch`,
   `/api/script/raw/:slug`, `/api/script/:slug`).
2. Responses are JSON-decoded locally with `HttpService`.
3. Script sources are executed locally with `loadstring` - nothing is
   uploaded, proxied, or sent anywhere; no remotes are used.

## Requirements & troubleshooting

- Your executor must support `game:HttpGet` + `loadstring` (almost all do).
- **PAID** entries cannot be executed - their source is not public.
- **KEY** entries may ask for a key; use `KEY LINK` to copy the key page URL.
- If the API rate-limits you (HTTP 429), wait a few seconds and retry.
- If nothing loads, check the console (F9) for `[RBLX SCRPT HUB v1.0]`.

## Disclaimer

Educational / personal use only. All scripts are fetched live from the
ScriptBlox community and executed locally on your own client - you are
responsible for what you run. Respect the Roblox Terms of Service.
