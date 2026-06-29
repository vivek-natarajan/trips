# CLAUDE.md — Koh Samui Trip Hub

Context for continuing this project in Claude Code.

## What this is
A single-file, mobile-first web app for a group Thailand trip (8 friends, **26 Jun – 5 Jul 2026**: Phuket → Don Sak → Koh Samui → Koh Phangan/Black Moon Party → Phuket). It's a quick reference, not a planner. Deployed as a static site on **Vercel** from the GitHub repo `trips`. Pushing to the repo auto-deploys.

## Stack & hard constraints
- **Vanilla HTML + CSS + JS in one file: `index.html`.** No framework, no build step, no dependencies, no bundler.
- Fonts via Google Fonts `@import` (Caprasimo + Outfit). Everything else is inline `<style>` and `<script>`.
- **No backend.** Per-person state (selected character) uses `localStorage` only — it's per-device, not shared.
- Target width ~560px, designed for phones. Must work opened from a plain URL.
- Keep it a single file unless we deliberately decide to modularize.

## Layout of `index.html`
- **Picker overlay** (`#picker`) — "Who are you?" character select; first visit or via the top-bar avatar. Choice saved to `localStorage` key `kohsamui-character`.
- **Top bar** (`.top`) — title + dates + avatar chip (tap = re-open picker).
- **Three tab views**, switched by the fixed bottom **tab bar** (`.tabbar`): 
  - `#view-timeline` (home) — sticky **day selector** (`#daysel`) + rendered day (`#dayView`).
  - `#view-docs` — per-character Documents (arrival card).
  - `#view-wardrobe` — informative packing list (no checkboxes).
- **Footer** (`.foot`) — compact emergency numbers + meta. (No share button — users share the URL natively.)

## JS data model (top of the `<script>`)
- `CHARACTERS` — 8 people `{id, nick, full, emoji, color}`. (Vk/Vivek, Ruthu/Ruthvika, Xavi/Abhishek, Nati/Nihal, Vroom/Varun, Peeps/Deepthi, Deepthy, Adarshi/Adarsh.)
- `ARRIVAL_DOCS` — `{id: path|null}`. **This is how a TDAC becomes viewable:** drop the person's PDF in the repo (e.g. `docs/ruthu-tdac.pdf`), set their value to that path, push. Their card flips from "Generate" to "View arrival card" everywhere (timeline + Documents).
- `MIRA(code, hours)`, `LOMA`, `VILLA`, `MACS` — stay objects `{name, sub, addr, hours, ref, tel, map, copy}`. Addresses/phones/codes/GPS are taken from the actual bookings — treat as source of truth, don't paraphrase.
- `TRIP` — array of days `{date, dow, mon, m, label, fit, items[]}`. `fit` = the day's wardrobe (chips + count + note). `items` = timeline entries `{time, icon, node, title, detail?, warn?, wear?, party?, stay?, arrival?}`.

## Render functions
`applyCharacter(id)` → sets `current`, re-renders Documents + the open day. `renderDay(i)` → day selector + `buildFit` + `buildItem[]`. `buildItem` has a special `arrival:true` branch (renders the TDAC actions inline). `renderDocs()` → Documents tab. Copy-to-clipboard is delegated on `.act-copy`.

## Conventions (important)
- **Copy is terse and informative — never explanatory.** No "here's how this works", no scam warnings, no meta. Labels over sentences.
- Palette is in CSS `:root` vars (sea / surf / sand / coral / sun). Reuse them; don't introduce new colors casually.
- No to-do/checklist patterns. Wardrobe is read-only and informative.
- Personalization is per-device by design.

## Run & deploy
- Local: just open `index.html`, or `python3 -m http.server` then visit the printed URL.
- Deploy: commit + push to `trips` → Vercel rebuilds automatically. No commands.

## Current state
Timeline home with day selector, per-day wardrobe strips, inline stay cards (call/map/copy), the Black Moon Party + the Sat-27 drive warning, arrival card on day 1, Documents tab (Generate / View + Share on WhatsApp), informative Wardrobe tab, compact footer with emergency numbers.

## Open decisions / roadmap
- **Self-serve uploads:** current flow is Generate TDAC → share PDF on WhatsApp → organizer collects → set `ARRIVAL_DOCS` path. If we want people to upload directly and have it appear for everyone live, that needs a backend — **Supabase** (Auth + Storage + Postgres, free tier, works cross-platform, deploys alongside Vercel) is the chosen option. iCloud Drive is **not viable** (Sign in with Apple is auth-only; no public API to read/write a user's Drive; CloudKit is app-container only + paid + Apple-only).
- Likely future additions, all as timeline items or new data: flight details, ferry booking times, an expense/settle-up split, a Samui restaurants/activities shortlist.
