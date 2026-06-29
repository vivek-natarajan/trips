# 🏝️ Koh Samui Trip

Single-file web app for our Thailand trip — **26 June → 5 July 2026**, 8 friends.
Phuket → Don Sak → Koh Samui → Koh Phangan (Black Moon Party) → Phuket.

## What's inside
- **Timeline** — pick a day, see that day's plan: a vertical timeline with check-ins (call / map / copy address), the party night, and the day's wardrobe.
- **Documents** — your arrival card (TDAC). Open your personal link to **upload** your card; you see your own, the organizer sees everyone's. No link → Generate / Share on WhatsApp as before.
- **Wardrobe** — the full ~50-piece packing list for 9 days.
- Pick your character on entry; it's remembered on your device.

It's one static `index.html` — no build step, no client dependencies (uploads talk to Supabase Storage over plain `fetch`).

## Self-serve arrival cards
Each person gets a private link (`…/?k=…`) that opens the app as them — no login. Upload your TDAC PDF and it's stored privately (Supabase Storage + row-level security): only you and the organizer can view it. The organizer's link shows everyone's status. Setup details and how links are minted: see `CLAUDE.md` and `docs/superpowers/`.

## Hosting (Vercel)
Push to GitHub → import the repo on [vercel.com](https://vercel.com) (Framework Preset: *Other*) → Deploy. Edits pushed to the repo redeploy automatically.

## Local
Open `index.html`, or run `python3 -m http.server` and open the printed URL.

## Notes
- Character choice is stored per device.
- All times are local Thailand time (ICT). Stays are booked under Ruthvika.
- See `CLAUDE.md` for full architecture and roadmap.
