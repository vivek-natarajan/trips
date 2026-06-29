# Self-serve TDAC uploads — design

**Status:** approved (brainstorming complete)
**Repo:** `vivek-natarajan/trips` (Koh Samui trip hub)
**Date:** 2026-06-29

## Goal

Let each of the 8 friends upload their own Thailand arrival-card (TDAC) PDF directly from the app, so it's available without the organizer hand-wiring `ARRIVAL_DOCS` and pushing. Replaces today's flow: *Generate → share PDF on WhatsApp → organizer collects → set path → push*.

**Success bar:** must work for this trip. The feature is purely additive — if Supabase is unreachable, the token is missing, or anything fails, the app silently falls back to today's static behavior and nothing breaks.

## Decisions (locked during brainstorming)

| Decision | Choice |
|---|---|
| Bar | Must work for this trip; defensive, additive-only |
| Visibility | You view your **own** card; the **organizer** (Ruthvika) views **all**; others see neither |
| Identity | **Per-person secret link** (`?k=<jwt>`) — the link *is* the identity. No login, no email |
| Backend enforcement | **Approach A**: private Storage bucket + RLS + pre-minted per-person JWTs |
| Client library | **None** — plain `fetch` against the Storage REST API (preserves single-file, zero-dependency, no-build constraint) |
| v1 scope cut | No group-wide "5/8 uploaded" status board for ordinary members; only the organizer sees the roster |

## Architecture

The static `index.html` stays as-is and renders fully from its static data **first**. A small, lazily-initialized `tdac` layer activates **only** when a `?k=<jwt>` token is present (in the URL or persisted in `localStorage`).

- **Backend:** one Supabase project, with a **private** Storage bucket `tdac` and RLS policies on `storage.objects`.
- **No `supabase-js`, no Edge Functions, no build step.** The client uses `fetch` against `…/storage/v1/object/…` with `Authorization: Bearer <jwt>` and the public `apikey: <anon key>` header.
- **Public, embeddable in HTML:** `SUPABASE_URL`, anon key. **Never in repo:** the JWT secret (lives only in the local mint script's env + the Supabase dashboard).

## Identity & tokens

A one-time local script `scripts/mint-tokens.mjs` mints 9 JWTs (HS256, signed with the project JWT secret). Claims per token:

- `sub` = personId (e.g. `"ruthu"`) — becomes `auth.uid()`
- `role` = `"authenticated"` (reserved Supabase claim; required so Storage treats the request as an authed user)
- `aud` = `"authenticated"`
- `app_role` = `"member"` | `"organizer"` (custom claim, read in RLS via `auth.jwt() ->> 'app_role'`)
- `exp` ≈ `2026-07-10` (trip end + buffer)

The organizer (Ruthvika) gets `{ sub: "ruthu", app_role: "organizer" }` — both herself and the organizer.

Output: 9 links `https://<site>/?k=<jwt>`, distributed once by the organizer via WhatsApp.

**On load:** read `?k`; if it decodes to a known person, store it in `localStorage` (key `kohsamui-token`), **auto-apply that person's character**, then `history.replaceState` to strip `?k` from the address bar (avoid shoulder-surfing / accidental copy-paste). Persisting in `localStorage` is intended — convenient reopen on a personal phone.

## Storage layout & RLS

Bucket `tdac`, **private**. One object per person at the bucket root: `<personId>.pdf` (e.g. `ruthu.pdf`).

Policies on `storage.objects` where `bucket_id = 'tdac'`:

- **SELECT (download):** `(auth.jwt() ->> 'app_role') = 'organizer'` **OR** `name = auth.uid() || '.pdf'`
- **INSERT (upload):** `(auth.jwt() ->> 'app_role') = 'organizer'` **OR** `name = auth.uid() || '.pdf'`
- **UPDATE (replace):** same as INSERT
- **DELETE:** same as INSERT (so a wrong upload can be replaced)

A member literally cannot fetch another member's bytes — Supabase returns 403. This is the cryptographic enforcement of the visibility decision.

## Client UX

- **Member viewing own card** (Documents tab + day-1 timeline arrival item):
  - Not uploaded → **Generate** (`https://tdac.immigration.go.th`, unchanged) + **Upload your card** (accepts PDF/image).
  - On file → **View arrival card** (authed `fetch` → blob URL → open) + **Replace**.
- **Organizer** (Documents tab): a **roster of all 8** — name · on-file/missing · View. Backed by a Storage `list` call. Satisfies "organizer sees all."
- **No token** (plain URL): exactly today's behavior (Generate / Share on WhatsApp) + a gentle line "open your personal link to upload your card." Zero Supabase calls.

## Safety / "must not break"

- Every Supabase code path is wrapped: no token, fetch failure, or offline → silent fallback to current static behavior. No Supabase call blocks initial render.
- Bucket is private → the public anon key alone reads nothing (RLS denies).
- JWT secret only in the local mint script env + Supabase dashboard. `.gitignore` covers token output and `.env*`.

## Components & boundaries

| Unit | Purpose | Depends on | Interface |
|---|---|---|---|
| `tdac` client module (in `index.html`) | Read token, talk to Storage REST, expose `getCard`, `uploadCard`, `listAll`, `state` | `fetch`, embedded `SUPABASE_URL`/anon key, the `?k` JWT | small async functions returning data or `null` on any failure |
| Documents/arrival render (in `index.html`) | Render member/organizer/no-token states | `tdac` module + `current` character | DOM render functions, unchanged signatures where possible |
| `scripts/mint-tokens.mjs` | Mint 9 JWTs from the JWT secret → links | Node built-in `crypto` only (hand-rolled HS256, **no npm install**), env `JWT_SECRET` | CLI, prints links; never deployed |
| `setup.sql` (or `supabase/` migration) | Create bucket + RLS policies reproducibly | Supabase SQL editor / CLI | idempotent SQL |

## Setup sequence & dependency

1. **VK (interactive):** create / log into a Supabase project.
2. Apply `setup.sql` (bucket + policies); collect `SUPABASE_URL` + anon key (→ embed in HTML) and JWT secret (→ local env).
3. Mint 9 tokens → links.
4. Test the full matrix against the **real** project: member upload/view, member blocked from another's card (expect 403), organizer-sees-all, no-token fallback, Supabase-down fallback.
5. Commit + push (with VK's approval) → Vercel deploys.
6. Organizer distributes the 8 links via WhatsApp.

## Testing matrix

- Member uploads own card → object appears at `<personId>.pdf`; state flips to "On file."
- Member opens own card → blob opens.
- Member attempts another member's path → 403 (enforced, not just hidden).
- Organizer lists → all 8 rows; can open any on-file card.
- No token → Generate/Share fallback, no network calls.
- Supabase unreachable (simulate) → fallback, no thrown errors, app fully usable.

## Out of scope (v1)

- Group-wide upload status board for ordinary members.
- Any document type other than the TDAC.
- Real account auth (email/magic-link) — secret links are the identity for this trip.
