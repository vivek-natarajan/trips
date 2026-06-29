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
- `ARRIVAL_DOCS` — `{id: path|null}`. Manual **fallback** path: drop the person's PDF in the repo (e.g. `docs/ruthu-tdac.pdf`), set their value to that path, push. Used only when there's no `?k` token / Supabase is unreachable; the live path is the Supabase backend (see below).
- `MIRA(code, hours)`, `LOMA`, `VILLA`, `MACS` — stay objects `{name, sub, addr, hours, ref, tel, map, copy}`. Addresses/phones/codes/GPS are taken from the actual bookings — treat as source of truth, don't paraphrase.
- `TRIP` — array of days `{date, dow, mon, m, label, fit, items[]}`. `fit` = the day's wardrobe (chips + count + note). `items` = timeline entries `{time, icon, node, title, detail?, warn?, wear?, party?, stay?, arrival?}`.

## Render functions
`applyCharacter(id)` → sets `current`, re-renders Documents + the open day. `renderDay(i)` → day selector + `buildFit` + `buildItem[]`. `buildItem` has a special `arrival:true` branch (renders the TDAC actions inline). `renderDocs()` → Documents tab: member own-card (upload/view/replace) or the organizer roster. `tdac` (IIFE, plain `fetch`, no supabase-js) does `list`/`signedUrl`/`upload`; `loadTdacState()` refreshes `tdacState` then re-renders. Both `renderDocs` and the arrival branch fall back to Generate/WhatsApp when there's no token. Delegated handlers: `.act-copy` (copy), `.tdac-view` (open signed URL), `.tdac-upload` (file picker → upload).

## Conventions (important)
- **Copy is terse and informative — never explanatory.** No "here's how this works", no scam warnings, no meta. Labels over sentences.
- Palette is in CSS `:root` vars (sea / surf / sand / coral / sun). Reuse them; don't introduce new colors casually.
- No to-do/checklist patterns. Wardrobe is read-only and informative.
- Personalization is per-device by design.

## Run & deploy
- Local: just open `index.html`, or `python3 -m http.server` then visit the printed URL.
- Deploy: commit + push to `trips` → Vercel rebuilds automatically. No commands.

## Current state
Timeline home with day selector, per-day wardrobe strips, inline stay cards (call/map/copy), the Black Moon Party + the Sat-27 drive warning, arrival card on day 1, Documents tab, informative Wardrobe tab, compact footer with emergency numbers. **Self-serve TDAC uploads** are live: open your personal `?k=` link → upload your card; you see your own, the organizer (Ruthu) sees all. No link / offline → falls back to Generate + Share on WhatsApp.

## Backend — self-serve TDAC uploads (Supabase)
- Per-person **secret link** `?k=<jwt>` is the identity (no login). The JWT (`sub`=personId, `app_role`=member|organizer) is the Supabase access token; opening the link auto-picks your character and is stripped from the address bar.
- Private Storage bucket **`tdac`**, one object per person `<personId>.pdf`. **RLS** (`supabase/setup.sql`) gates on `app_role='organizer' OR name=(auth.jwt()->>'sub')||'.pdf'` — a member can only touch their own card, the organizer reads all. Uses `auth.jwt()->>'sub'` (string ids), never `auth.uid()` (uuid cast would fail).
- Client is **plain `fetch`** against the Storage REST API — no `supabase-js`. Public `SUPABASE_URL` + anon key live in the `TDAC` config block at the top of the script; the **JWT secret is never in the repo** (local `.env.local` + Supabase dashboard only).
- Tokens minted by `scripts/mint-tokens.mjs` (HS256, Node built-in `crypto`, reads `.env.local`); 8 tokens total (Ruthu's doubles as organizer). RLS proven by `scripts/test-rls.sh`. Design + plan in `docs/superpowers/`.

## Roadmap
- Likely future additions, all as timeline items or new data: flight details, ferry booking times, an expense/settle-up split, a Samui restaurants/activities shortlist.
- Optional: group-wide "N/8 uploaded" status for non-organizers (only the organizer sees the roster today).
- iCloud Drive was ruled out for uploads (Sign in with Apple is auth-only; no public Drive API; CloudKit is app-container + paid + Apple-only).
