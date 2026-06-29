# 🏝️ Koh Samui Trip

Single-file web app for our Thailand trip — **26 June → 5 July 2026**, 8 friends.
Phuket → Don Sak → Koh Samui → Koh Phangan (Black Moon Party) → Phuket.

## What's inside
- **Timeline** — pick a day, see that day's plan: a vertical timeline with check-ins (call / map / copy address), the party night, and the day's wardrobe.
- **Documents** — per person; the arrival card (TDAC): Generate, View, or Share on WhatsApp.
- **Wardrobe** — the full ~50-piece packing list for 9 days.
- Pick your character on entry; it's remembered on your device.

It's one static `index.html` — no build step, no dependencies.

## Hosting (Vercel)
Push to GitHub → import the repo on [vercel.com](https://vercel.com) (Framework Preset: *Other*) → Deploy. Edits pushed to the repo redeploy automatically.

## Local
Open `index.html`, or run `python3 -m http.server` and open the printed URL.

## Notes
- Character choice is stored per device.
- All times are local Thailand time (ICT). Stays are booked under Ruthvika.
- See `CLAUDE.md` for full architecture and roadmap.
