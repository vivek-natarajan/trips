#!/usr/bin/env bash
# Proves RLS: a member can only touch their own object; organizer can read all.
# Usage: set VK_TOKEN, NATI_TOKEN, RUTHU_TOKEN env (from tokens.tsv) then run.
set -euo pipefail
: "${SUPABASE_URL:?}" "${SUPABASE_ANON_KEY:?}" "${VK_TOKEN:?}" "${NATI_TOKEN:?}" "${RUTHU_TOKEN:?}"
B="$SUPABASE_URL/storage/v1"; AK="apikey: $SUPABASE_ANON_KEY"

code(){ curl -s -o /dev/null -w '%{http_code}' "$@"; }

echo -n "vk uploads vk.pdf (expect 200): "
printf '%%PDF-1.4 test' > /tmp/vk.pdf
code -X POST "$B/object/tdac/vk.pdf" -H "$AK" -H "Authorization: Bearer $VK_TOKEN" -H "x-upsert: true" -H "Content-Type: application/pdf" --data-binary @/tmp/vk.pdf; echo

echo -n "vk signs OWN vk.pdf (expect 200): "
code -X POST "$B/object/sign/tdac/vk.pdf" -H "$AK" -H "Authorization: Bearer $VK_TOKEN" -H "Content-Type: application/json" -d '{"expiresIn":60}'; echo

echo -n "nati signs vk.pdf — NOT allowed (expect 400/403): "
code -X POST "$B/object/sign/tdac/vk.pdf" -H "$AK" -H "Authorization: Bearer $NATI_TOKEN" -H "Content-Type: application/json" -d '{"expiresIn":60}'; echo

echo -n "nati uploads vk.pdf — NOT allowed (expect 400/403): "
code -X POST "$B/object/tdac/vk.pdf" -H "$AK" -H "Authorization: Bearer $NATI_TOKEN" -H "x-upsert: true" -H "Content-Type: application/pdf" --data-binary @/tmp/vk.pdf; echo

echo -n "organizer signs vk.pdf (expect 200): "
code -X POST "$B/object/sign/tdac/vk.pdf" -H "$AK" -H "Authorization: Bearer $RUTHU_TOKEN" -H "Content-Type: application/json" -d '{"expiresIn":60}'; echo

echo -n "anon (no bearer) signs vk.pdf — NOT allowed (expect 400/401/403): "
code -X POST "$B/object/sign/tdac/vk.pdf" -H "$AK" -H "Content-Type: application/json" -d '{"expiresIn":60}'; echo

# cleanup the test object so the bucket starts empty for the trip
curl -s -o /dev/null -X DELETE "$B/object/tdac/vk.pdf" -H "$AK" -H "Authorization: Bearer $VK_TOKEN"
rm -f /tmp/vk.pdf
echo "(cleaned up test vk.pdf)"
