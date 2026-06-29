# Self-serve TDAC Uploads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let each of 8 friends upload their own TDAC arrival-card PDF from the app, viewable by themselves and the organizer, with zero login and graceful fallback.

**Architecture:** Static single-file `index.html` keeps working untouched; a lazy `tdac` layer activates only when a `?k=<jwt>` secret link is present. Backend is one Supabase project with a private Storage bucket `tdac` + RLS. The client talks to the Storage REST API over plain `fetch` (no `supabase-js`). Per-person pre-minted JWTs are the identity; RLS enforces "own card + organizer sees all."

**Tech Stack:** Vanilla HTML/CSS/JS (single file, no build), Supabase Storage + RLS, Node built-in `crypto` (mint script), Playwright MCP + curl (tests).

## Global Constraints

- **Single file:** all app code stays in `index.html` — inline `<style>`/`<script>`, no framework, no bundler, no build step.
- **Zero runtime dependencies:** no `supabase-js`, no npm packages in the app or mint script. Mint script uses Node built-in `crypto` only.
- **Additive & non-breaking:** if `?k` is absent, the token is invalid/expired, config is unset, or any network call fails → silently fall back to today's static behavior. No Supabase call may block initial render or throw uncaught.
- **Secrets never in repo:** the Supabase JWT secret lives only in local env + the Supabase dashboard. Public values (`SUPABASE_URL`, anon key) may be embedded in `index.html`.
- **Copy style:** terse, informative, no explanatory/meta sentences. Reuse `:root` palette vars; introduce no new colors.
- **Person ids:** `vk, ruthu, xavi, nati, vroom, peeps, deepthy, adarshi`. Organizer = `ruthu`.
- **Storage object naming:** `<personId>.pdf` at bucket root (e.g. `ruthu.pdf`).
- **JWT claims (exact):** `sub`=personId, `role`="authenticated", `aud`="authenticated", `app_role`="member"|"organizer", `iat`, `exp`≈2026-07-10.

## Testing note (read before starting)

This is a buildless single-file app, so there is no unit-test runner for the inline script. The discipline adapts:
- **Mint script** → real Node TDD (`node --test`).
- **RLS / Storage contract** → integration test with `curl` against the live project (the security-critical 403 check), expected HTTP codes asserted.
- **UI states** → Playwright MCP against the served file end-to-end (inject token into `localStorage`, drive the real backend, assert DOM).

Several tasks therefore depend on the live Supabase project existing (Task 4). Tasks 1–3 do not.

## File Structure

| File | Create/Modify | Responsibility |
|---|---|---|
| `.gitignore` | Create | Keep `.env*`, minted token output, `.DS_Store`, `.playwright-mcp/` out of git |
| `.env.example` | Create | Document required env vars (no secrets) |
| `scripts/mint-tokens.mjs` | Create | Hand-rolled HS256 JWT minting + CLI that prints 9 links |
| `scripts/mint-tokens.test.mjs` | Create | Node test for `mintToken` |
| `supabase/setup.sql` | Create | Idempotent: create private bucket + RLS policies |
| `scripts/test-rls.sh` | Create | curl matrix proving RLS enforcement (own/other/organizer) |
| `index.html` | Modify | Config block, token init, `tdac` client module, Documents/arrival render for all states |
| `README.md` | Modify | Brief setup + usage note |
| `CLAUDE.md` | Modify | Move self-serve uploads from roadmap → current state |

---

### Task 1: Repo hygiene — gitignore + env example

**Files:**
- Create: `.gitignore`
- Create: `.env.example`

**Interfaces:**
- Produces: documented env var names `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_JWT_SECRET`, `SITE_URL` (consumed by Task 2 CLI and Task 4).

- [ ] **Step 1: Create `.gitignore`**

```
# secrets & local env
.env
.env.local
.env.*.local
# minted token output (contains live JWTs = capability links)
tokens.txt
tokens.tsv
# os / tooling noise
.DS_Store
.playwright-mcp/
```

- [ ] **Step 2: Create `.env.example`**

```
# Supabase project — fill from dashboard (Settings → API). Copy to .env.local; never commit .env.local.
SUPABASE_URL=https://YOURREF.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOi...           # public anon key (safe to embed in index.html)
SUPABASE_JWT_SECRET=super-secret-value     # Settings → API → JWT Settings. SECRET. mint script only.
SITE_URL=https://trips.vercel.app          # base for the per-person links
```

- [ ] **Step 3: Verify ignores work**

Run:
```bash
cd /Users/vivek.natarajan/Documents/Personal/Projects/trips
printf 'x' > .env.local && printf 'x' > tokens.txt
git check-ignore .env.local tokens.txt .DS_Store
rm -f .env.local tokens.txt
```
Expected output (all three echoed back as ignored):
```
.env.local
tokens.txt
.DS_Store
```

- [ ] **Step 4: Commit**

```bash
git add .gitignore .env.example
git commit -m "chore: gitignore secrets + env example for Supabase"
```

---

### Task 2: Token mint script (TDD)

**Files:**
- Create: `scripts/mint-tokens.mjs`
- Test: `scripts/mint-tokens.test.mjs`

**Interfaces:**
- Produces: `export function mintToken({ personId, appRole, secret, exp })` → `string` (a `header.payload.signature` HS256 JWT). CLI (run directly) reads env `SUPABASE_JWT_SECRET` + `SITE_URL`, prints `personId<TAB>appRole<TAB>link` for all 9 tokens.

- [ ] **Step 1: Write the failing test**

`scripts/mint-tokens.test.mjs`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { mintToken } from './mint-tokens.mjs';

test('mintToken signs an HS256 JWT with the expected claims', () => {
  const secret = 'test-secret';
  const tok = mintToken({ personId: 'ruthu', appRole: 'organizer', secret, exp: 9999999999 });
  const [h, p, s] = tok.split('.');

  // signature verifies against the secret
  const expectedSig = createHmac('sha256', secret).update(`${h}.${p}`).digest('base64url');
  assert.equal(s, expectedSig);

  // header
  const header = JSON.parse(Buffer.from(h, 'base64url').toString());
  assert.deepEqual(header, { alg: 'HS256', typ: 'JWT' });

  // claims
  const payload = JSON.parse(Buffer.from(p, 'base64url').toString());
  assert.equal(payload.sub, 'ruthu');
  assert.equal(payload.role, 'authenticated');
  assert.equal(payload.aud, 'authenticated');
  assert.equal(payload.app_role, 'organizer');
  assert.equal(payload.exp, 9999999999);
  assert.equal(typeof payload.iat, 'number');
});

test('a wrong secret does not verify (tamper check)', () => {
  const tok = mintToken({ personId: 'vk', appRole: 'member', secret: 'real', exp: 9999999999 });
  const [h, p, s] = tok.split('.');
  const wrong = createHmac('sha256', 'wrong').update(`${h}.${p}`).digest('base64url');
  assert.notEqual(s, wrong);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/vivek.natarajan/Documents/Personal/Projects/trips && node --test scripts/mint-tokens.test.mjs`
Expected: FAIL — `Cannot find module './mint-tokens.mjs'` (or `mintToken is not a function`). (Node 25 parses a bare `scripts/` dir arg as a module path, so pass the test file explicitly.)

- [ ] **Step 3: Write minimal implementation**

`scripts/mint-tokens.mjs`:
```js
import { createHmac } from 'node:crypto';

const b64url = (input) => Buffer.from(input).toString('base64url');

function sign(payload, secret) {
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = b64url(JSON.stringify(payload));
  const data = `${header}.${body}`;
  const sig = createHmac('sha256', secret).update(data).digest('base64url');
  return `${data}.${sig}`;
}

export function mintToken({ personId, appRole, secret, exp }) {
  if (!secret) throw new Error('secret required');
  const now = Math.floor(Date.now() / 1000);
  return sign(
    {
      sub: personId,
      role: 'authenticated',
      aud: 'authenticated',
      app_role: appRole,
      iat: now,
      exp: exp ?? now + 60 * 60 * 24 * 14,
    },
    secret,
  );
}

// ---- CLI: node scripts/mint-tokens.mjs ----
const PEOPLE = ['vk', 'ruthu', 'xavi', 'nati', 'vroom', 'peeps', 'deepthy', 'adarshi'];
const ORGANIZER = 'ruthu';

if (import.meta.url === `file://${process.argv[1]}`) {
  const secret = process.env.SUPABASE_JWT_SECRET;
  const base = (process.env.SITE_URL || '').replace(/\/$/, '');
  if (!secret) { console.error('Set SUPABASE_JWT_SECRET'); process.exit(1); }
  if (!base) { console.error('Set SITE_URL'); process.exit(1); }
  const exp = Math.floor(new Date('2026-07-10T00:00:00Z').getTime() / 1000);
  for (const id of PEOPLE) {
    const appRole = id === ORGANIZER ? 'organizer' : 'member';
    const tok = mintToken({ personId: id, appRole, secret, exp });
    console.log(`${id}\t${appRole}\t${base}/?k=${tok}`);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/vivek.natarajan/Documents/Personal/Projects/trips && node --test scripts/mint-tokens.test.mjs`
Expected: PASS — `tests 2`, `pass 2`, `fail 0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/mint-tokens.mjs scripts/mint-tokens.test.mjs
git commit -m "feat: HS256 token mint script (no npm deps) + tests"
```

---

### Task 3: Supabase setup SQL (bucket + RLS)

**Files:**
- Create: `supabase/setup.sql`

**Interfaces:**
- Produces: a private bucket `tdac` and 4 RLS policies on `storage.objects`. Verified in Task 4 (needs live project).

- [ ] **Step 1: Write `supabase/setup.sql`**

```sql
-- Self-serve TDAC uploads — private bucket + RLS.
-- Idempotent: safe to re-run. Apply in Supabase SQL editor or via CLI.

-- 1) Private bucket
insert into storage.buckets (id, name, public)
values ('tdac', 'tdac', false)
on conflict (id) do update set public = false;

-- 2) Policies on storage.objects for bucket 'tdac'.
-- NOTE: compare auth.jwt() ->> 'sub' (text). Do NOT use auth.uid() — it casts
-- sub to uuid and would error on string ids like 'ruthu'.

drop policy if exists "tdac read own or organizer" on storage.objects;
create policy "tdac read own or organizer"
on storage.objects for select to authenticated
using (
  bucket_id = 'tdac'
  and (
    (auth.jwt() ->> 'app_role') = 'organizer'
    or name = (auth.jwt() ->> 'sub') || '.pdf'
  )
);

drop policy if exists "tdac insert own or organizer" on storage.objects;
create policy "tdac insert own or organizer"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'tdac'
  and (
    (auth.jwt() ->> 'app_role') = 'organizer'
    or name = (auth.jwt() ->> 'sub') || '.pdf'
  )
);

drop policy if exists "tdac update own or organizer" on storage.objects;
create policy "tdac update own or organizer"
on storage.objects for update to authenticated
using (
  bucket_id = 'tdac'
  and (
    (auth.jwt() ->> 'app_role') = 'organizer'
    or name = (auth.jwt() ->> 'sub') || '.pdf'
  )
)
with check (
  bucket_id = 'tdac'
  and (
    (auth.jwt() ->> 'app_role') = 'organizer'
    or name = (auth.jwt() ->> 'sub') || '.pdf'
  )
);

drop policy if exists "tdac delete own or organizer" on storage.objects;
create policy "tdac delete own or organizer"
on storage.objects for delete to authenticated
using (
  bucket_id = 'tdac'
  and (
    (auth.jwt() ->> 'app_role') = 'organizer'
    or name = (auth.jwt() ->> 'sub') || '.pdf'
  )
);
```

- [ ] **Step 2: Lint the SQL (no live DB yet)**

Visual review only: confirm all four verbs (select/insert/update/delete) present, every predicate uses `auth.jwt() ->> 'sub'` (never `auth.uid()`), and bucket is `public=false`. No command to run.

- [ ] **Step 3: Commit**

```bash
git add supabase/setup.sql
git commit -m "feat: Supabase setup.sql — private tdac bucket + RLS policies"
```

---

### Task 4: Provision live project + wire config + mint real tokens

**Files:**
- Modify: `index.html` (config block only)
- Local only (gitignored): `.env.local`, `tokens.tsv`

**Interfaces:**
- Consumes: `supabase/setup.sql` (Task 3), `scripts/mint-tokens.mjs` (Task 2).
- Produces: a live Supabase project; `index.html` `TDAC` config populated with real `url` + `anon`; 9 capability links in `tokens.tsv` (gitignored).

> **VK interactive step inside this task:** create/log into a Supabase project. The agent cannot do this; pause and request it.

- [ ] **Step 1: VK creates the Supabase project**

Ask VK to create a project at supabase.com (or confirm an existing one) and share, from **Settings → API**: the Project URL, the `anon` public key, and the JWT Secret. Wait for these before continuing.

- [ ] **Step 2: Save secrets locally**

```bash
cd /Users/vivek.natarajan/Documents/Personal/Projects/trips
cp .env.example .env.local
# edit .env.local with the real values (SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_JWT_SECRET, SITE_URL)
```

- [ ] **Step 3: Apply `setup.sql`**

Either paste `supabase/setup.sql` into the Supabase SQL editor and run, or via CLI if linked:
```bash
supabase db execute --file supabase/setup.sql   # if project is linked; else use the SQL editor
```
Expected: success, no errors. Verify in dashboard: Storage shows a private `tdac` bucket; Authentication → Policies shows 4 `tdac …` policies.

- [ ] **Step 4: Add the config block to `index.html`**

In `index.html`, immediately after the opening `<script>` (currently line 267) and before `/* ===== CHARACTERS ===== */`, insert:
```js
  /* ===== TDAC BACKEND CONFIG (public values only) ===== */
  const TDAC = {
    url:    'https://YOURREF.supabase.co',   // <- real Project URL
    anon:   'PASTE_ANON_KEY',                // <- real anon public key
    bucket: 'tdac',
  };
```
Replace `YOURREF`/`PASTE_ANON_KEY` with the real values from `.env.local`. (Leaving placeholders keeps the backend disabled — see Task 5's `enabled` guard — so the app still works.)

- [ ] **Step 5: Mint the real tokens**

```bash
cd /Users/vivek.natarajan/Documents/Personal/Projects/trips
set -a && . ./.env.local && set +a
node scripts/mint-tokens.mjs | tee tokens.tsv
```
Expected: 9 tab-separated lines (`vk member https://…/?k=…`, `ruthu organizer …`, etc.). Confirm `tokens.tsv` is gitignored: `git check-ignore tokens.tsv` → echoes `tokens.tsv`.

- [ ] **Step 6: Commit (config only — no secrets)**

```bash
git add index.html
git commit -m "feat: embed Supabase project config (public url + anon key)"
```
Confirm `git status` shows `.env.local` and `tokens.tsv` as ignored (untracked, not staged).

---

### Task 5: Token init + decode + auto-character (index.html)

**Files:**
- Modify: `index.html` — add token helpers near the storage helpers (after `lsSet`, ~line 383); call init in the INIT block (~lines 531-537).

**Interfaces:**
- Consumes: `TDAC` config (Task 4), `lsGet`/`lsSet`, `CHARACTERS`, `applyCharacter`.
- Produces: `const APP_TOKEN` (string|null), `function decodeToken(t)` → `{sub, app_role, exp}|null`, `const APP_CLAIMS` (object|null). Consumed by Tasks 6.

- [ ] **Step 1: Add token helpers**

After the `lsSet` definition (currently line 383), insert:
```js
  /* ===== TOKEN (capability link) ===== */
  const TOKEN_KEY = 'kohsamui-token';
  function decodeToken(t){
    try {
      const part = t.split('.')[1].replace(/-/g,'+').replace(/_/g,'/');
      const claims = JSON.parse(decodeURIComponent(escape(atob(part))));
      if (!claims.sub) return null;
      if (claims.exp && claims.exp * 1000 < Date.now()) return null;   // expired
      return claims;
    } catch(e){ return null; }
  }
  function readToken(){
    let t = null;
    try {
      const u = new URL(location.href);
      t = u.searchParams.get('k');
      if (t){
        lsSet(TOKEN_KEY, t);
        u.searchParams.delete('k');
        history.replaceState(null, '', u.pathname + (u.search || '') + (u.hash || ''));   // strip ?k from the bar
      } else {
        t = lsGet(TOKEN_KEY);
      }
    } catch(e){ t = lsGet(TOKEN_KEY); }
    return t || null;
  }
  const APP_TOKEN  = readToken();
  const APP_CLAIMS = APP_TOKEN ? decodeToken(APP_TOKEN) : null;
```

- [ ] **Step 2: Auto-apply character from the token in INIT**

Replace the INIT character block (currently lines 532-533):
```js
  const saved = lsGet(CHAR_KEY);
  if (saved && CHARACTERS.find(c => c.id === saved)) applyCharacter(saved); else { applyCharacter(null); picker.classList.add('show'); }
```
with:
```js
  const tokenId = APP_CLAIMS && CHARACTERS.find(c => c.id === APP_CLAIMS.sub) ? APP_CLAIMS.sub : null;
  const saved = lsGet(CHAR_KEY);
  if (tokenId){ lsSet(CHAR_KEY, tokenId); applyCharacter(tokenId); }
  else if (saved && CHARACTERS.find(c => c.id === saved)) applyCharacter(saved);
  else { applyCharacter(null); picker.classList.add('show'); }
```

- [ ] **Step 3: Verify decode + auto-character + URL strip (Playwright MCP)**

Mint a throwaway token for `vk` against the real secret (or reuse `tokens.tsv`). With the local server running (`python3 -m http.server 8923` in repo) and the token's `?k=` value:
1. Navigate to `http://localhost:8923/index.html?k=<vk-token>`.
2. Assert page URL no longer contains `k=` (strip worked): evaluate `location.search`.
3. Assert the top-bar avatar nick shows `Vk` (auto-applied): the `#topAvaNick` text is `Vk`.
4. Assert `localStorage['kohsamui-token']` is set.

Expected: URL clean, `Vk` shown, token persisted. Re-navigating to plain `http://localhost:8923/index.html` (no `?k`) still shows `Vk` (persisted).

- [ ] **Step 4: Verify fallback (no token, placeholder config)**

Navigate to `http://localhost:8923/index.html` in a fresh context (clear localStorage first). Expected: picker shows, no console errors, app fully usable.

- [ ] **Step 5: Commit**

```bash
git add index.html
git commit -m "feat: parse ?k secret link, decode claims, auto-pick character, strip URL"
```

---

### Task 6: `tdac` client module + Documents/arrival rendering (index.html)

**Files:**
- Modify: `index.html` — add the `tdac` IIFE after the token helpers; add minimal roster CSS; rewrite `renderDocs()` (~lines 487-508) and the `buildItem` arrival branch (~lines 429-444); add upload file input + delegated handlers; add `loadTdacState()` and call it from INIT.

**Interfaces:**
- Consumes: `TDAC`, `APP_TOKEN`, `APP_CLAIMS`, `CHARACTERS`, `current`, `renderDay`, `curDay`, `showToast`, `ARRIVAL_DOCS`.
- Produces: `const tdac` with `enabled:boolean`, `async list()→string[]` (filenames visible to this token; `[]` on any failure), `async signedUrl(path)→string|null`, `async upload(path,file)→boolean`; module var `let tdacState = null` (string[]|null); `async function loadTdacState()`.

- [ ] **Step 1: Add the `tdac` client module**

After the token helpers (Task 5 Step 1 block), insert:
```js
  /* ===== TDAC CLIENT (plain fetch, no supabase-js) ===== */
  const tdac = (() => {
    const enabled = !!(TDAC.url && TDAC.anon && !TDAC.url.includes('YOURREF') && APP_TOKEN);
    const headers = () => ({ apikey: TDAC.anon, Authorization: `Bearer ${APP_TOKEN}` });
    async function list(){
      if (!enabled) return [];
      try {
        const r = await fetch(`${TDAC.url}/storage/v1/object/list/${TDAC.bucket}`, {
          method:'POST', headers:{ ...headers(), 'Content-Type':'application/json' },
          body: JSON.stringify({ prefix:'', limit:100, offset:0 })
        });
        if (!r.ok) return [];
        const rows = await r.json();
        return Array.isArray(rows) ? rows.map(o => o.name).filter(Boolean) : [];
      } catch(e){ return []; }
    }
    async function signedUrl(path){
      if (!enabled) return null;
      try {
        const r = await fetch(`${TDAC.url}/storage/v1/object/sign/${TDAC.bucket}/${path}`, {
          method:'POST', headers:{ ...headers(), 'Content-Type':'application/json' },
          body: JSON.stringify({ expiresIn: 3600 })
        });
        if (!r.ok) return null;
        const j = await r.json();
        const rel = j.signedURL || j.signedUrl;          // e.g. "/object/sign/tdac/vk.pdf?token=..."
        if (!rel) return null;
        const path = rel.startsWith('/storage/v1') ? rel
          : (rel.startsWith('/') ? '/storage/v1' + rel : '/storage/v1/' + rel);
        return TDAC.url + path;                           // -> https://REF.supabase.co/storage/v1/object/sign/...
      } catch(e){ return null; }
    }
    async function upload(path, file){
      if (!enabled) return false;
      try {
        const r = await fetch(`${TDAC.url}/storage/v1/object/${TDAC.bucket}/${path}`, {
          method:'POST',
          headers:{ ...headers(), 'x-upsert':'true', 'Content-Type': file.type || 'application/pdf' },
          body: file
        });
        return r.ok;
      } catch(e){ return false; }
    }
    return { enabled, list, signedUrl, upload };
  })();

  let tdacState = null;   // string[] of filenames visible to this token, or null = unknown/disabled
  async function loadTdacState(){
    if (!tdac.enabled) return;
    tdacState = await tdac.list();
    renderDocs();
    renderDay(curDay);
  }
```

- [ ] **Step 2: Add the hidden file input + roster CSS**

Just before the closing `</style>` (line 162), add:
```css
  .doc-row { display:flex; align-items:center; gap:11px; padding:9px 0; border-bottom:1px solid var(--sand-deep); }
  .doc-row:last-child { border-bottom:none; }
  .doc-row .dr-name { flex:1; font-size:14px; font-weight:600; }
  .doc-row .dr-state { font-size:12px; font-weight:600; }
  .doc-row .dr-state.ok { color:#1f7a4d; } .doc-row .dr-state.wait { color:var(--ink-soft); }
  .doc-row .dr-view { font-size:12.5px; font-weight:700; color:var(--sea); text-decoration:none; padding:6px 12px; border:1px solid var(--sand-deep); border-radius:9px; background:var(--white); cursor:pointer; }
```
Just before the `<div class="toast"` line (line 265), add:
```html
<input type="file" id="tdacFile" accept="application/pdf,image/*" style="display:none">
```

- [ ] **Step 3: Rewrite `renderDocs()` for all states**

Replace the whole `renderDocs()` function (lines 487-508) with:
```js
  const docsView = document.getElementById('docsView');
  function renderDocs(){
    if (!current){ docsView.innerHTML = `<div class="doc-empty">Tap your avatar to pick your character.</div>`; return; }

    // Organizer roster
    if (tdac.enabled && APP_CLAIMS && APP_CLAIMS.app_role === 'organizer'){
      const rows = CHARACTERS.map(c => {
        const has = tdacState ? tdacState.includes(`${c.id}.pdf`) : false;
        return `<div class="doc-row">
          <span class="dr-name">${c.nick} <span style="color:var(--ink-soft);font-weight:400">${c.full}</span></span>
          <span class="dr-state ${has?'ok':'wait'}">${has?'On file':'—'}</span>
          ${has?`<button class="dr-view tdac-view" data-id="${c.id}">View</button>`:''}
        </div>`;
      }).join('');
      docsView.innerHTML = `<div class="doc-card">
        <div class="doc-top"><div class="doc-ico">🪪</div><div><div class="doc-name">Arrival cards</div><div class="doc-state wait">${tdacState?`${tdacState.filter(n=>n.endsWith('.pdf')).length}/8 on file`:'Loading…'}</div></div></div>
        ${rows}
      </div>
      <div class="doc-card">${ownCardCardInner()}</div>`;
      return;
    }

    // Member (own card)
    docsView.innerHTML = `<div class="doc-card">${ownCardCardInner()}</div>`;
  }

  function ownCardCardInner(){
    const id = current.id;
    const hasBackend = tdac.enabled && tdacState !== null;
    const has = hasBackend ? tdacState.includes(`${id}.pdf`) : !!ARRIVAL_DOCS[id];
    const wa = `https://wa.me/?text=${encodeURIComponent(`Thailand arrival card (TDAC) — ${current.nick}. Sending the PDF.`)}`;
    let actions;
    if (tdac.enabled){
      actions = has
        ? `<button class="dact primary tdac-view" data-id="${id}">View arrival card</button>
           <button class="dact ghost tdac-upload" data-id="${id}">Replace</button>`
        : `<a class="dact primary" href="https://tdac.immigration.go.th" target="_blank" rel="noopener">Generate one</a>
           <button class="dact ghost tdac-upload" data-id="${id}">Upload your card</button>`;
    } else {
      actions = has
        ? `<a class="dact primary" href="${ARRIVAL_DOCS[id]}" target="_blank" rel="noopener">View arrival card</a>
           <a class="dact ghost" href="${wa}" target="_blank" rel="noopener">Share on WhatsApp</a>`
        : `<a class="dact primary" href="https://tdac.immigration.go.th" target="_blank" rel="noopener">Generate one</a>
           <a class="dact ghost" href="${wa}" target="_blank" rel="noopener">Share on WhatsApp</a>`;
    }
    return `<div class="doc-top">
        <div class="doc-ico">🪪</div>
        <div><div class="doc-name">Arrival card</div>
        <div class="doc-state ${has?'ok':'wait'}">${current.nick} · ${has?'On file':'Not added yet'}</div></div>
      </div>
      <div class="doc-actions">${actions}</div>
      <div class="doc-fine">File within 72h of landing. Save the QR.</div>`;
  }
```

- [ ] **Step 4: Rewrite the `buildItem` arrival branch**

Replace the `if (it.arrival){ ... }` block inside `buildItem` (lines 429-445) with:
```js
    if (it.arrival){
      const nick = current ? current.nick : '';
      const wa = `https://wa.me/?text=${encodeURIComponent('Thailand arrival card (TDAC) — ' + nick + '. Sending the PDF.')}`;
      const id = current ? current.id : null;
      const hasBackend = tdac.enabled && tdacState !== null;
      const has = current ? (hasBackend ? tdacState.includes(`${id}.pdf`) : !!ARRIVAL_DOCS[id]) : false;
      const detail = current ? (has ? 'On file — ready to show at the airport.' : 'Fill it before you fly. Save the QR.') : 'Tap your avatar to pick your character.';
      let acts = '';
      if (current && tdac.enabled){
        acts = `<div class="stay-actions">
          ${has ? `<button class="act act-call tdac-view" data-id="${id}">View card</button>`
                : `<a class="act act-call" href="https://tdac.immigration.go.th" target="_blank" rel="noopener">Generate</a>`}
          <button class="act tdac-upload" data-id="${id}">${has?'Replace':'Upload'}</button>
        </div>`;
      } else if (current){
        acts = `<div class="stay-actions">
          ${has ? `<a class="act act-call" href="${ARRIVAL_DOCS[id]}" target="_blank" rel="noopener">View card</a>`
                : `<a class="act act-call" href="https://tdac.immigration.go.th" target="_blank" rel="noopener">Generate</a>`}
          <a class="act" href="${wa}" target="_blank" rel="noopener">Share</a>
        </div>`;
      }
      return `<div class="tl-item">
        <div class="tl-rail"><div class="tl-node coral">🪪</div></div>
        <div class="tl-content">
          <div class="tl-time">${it.time}</div>
          <div class="tl-title">${it.title}</div>
          <div class="tl-detail">${detail}</div>
          ${acts}
        </div>
      </div>`;
    }
```

- [ ] **Step 5: Wire delegated view/upload handlers**

After the existing `.act-copy` delegated handler (ends line 527), add:
```js
  /* ===== TDAC view / upload (delegated) ===== */
  const tdacFile = document.getElementById('tdacFile');
  let pendingUploadId = null;
  document.body.addEventListener('click', async (e) => {
    const v = e.target.closest('.tdac-view');
    if (v){ const u = await tdac.signedUrl(`${v.dataset.id}.pdf`); if (u) window.open(u, '_blank', 'noopener'); else showToast('Could not open'); return; }
    const up = e.target.closest('.tdac-upload');
    if (up){ pendingUploadId = up.dataset.id; tdacFile.value = ''; tdacFile.click(); }
  });
  tdacFile.addEventListener('change', async () => {
    const file = tdacFile.files && tdacFile.files[0];
    if (!file || !pendingUploadId) return;
    showToast('Uploading…');
    const ok = await tdac.upload(`${pendingUploadId}.pdf`, file);
    pendingUploadId = null;
    showToast(ok ? 'Card uploaded ✓' : 'Upload failed');
    if (ok) await loadTdacState();
  });
```

- [ ] **Step 6: Kick off `loadTdacState()` in INIT**

At the very end of the INIT block (after `renderDay(start);`, line 537), add:
```js
  if (tdac.enabled) loadTdacState();
```

- [ ] **Step 7: Integration test — RLS matrix (curl)** — see Task 7. Run it now and confirm green before the UI E2E.

- [ ] **Step 8: End-to-end UI test (Playwright MCP, real backend)**

With server running and real config embedded:
1. **Member upload:** navigate with `vk`'s `?k=` link → Documents tab → click **Upload your card** is wired (set `#tdacFile` files via Playwright `browser_file_upload` to a sample PDF) → assert toast `Card uploaded ✓` and state flips to `On file` with a **View** button.
2. **Member view:** click **View arrival card** → assert a new tab/url opens (signed URL).
3. **Organizer:** navigate with `ruthu`'s link → Documents tab → assert roster lists 8 rows and shows `On file` for `vk` (uploaded in step 1).
4. **No token:** clear localStorage, plain URL → Documents shows Generate / Share on WhatsApp, no errors.

Expected: all four pass; no uncaught console errors (favicon 404 is fine).

- [ ] **Step 9: Commit**

```bash
git add index.html
git commit -m "feat: self-serve TDAC upload/view + organizer roster, with static fallback"
```

---

### Task 7: RLS enforcement integration test (curl)

**Files:**
- Create: `scripts/test-rls.sh`

**Interfaces:**
- Consumes: `.env.local` (URL, anon), real member/organizer tokens (from `tokens.tsv`).

- [ ] **Step 1: Write `scripts/test-rls.sh`**

```bash
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
```

- [ ] **Step 2: Run it**

```bash
cd /Users/vivek.natarajan/Documents/Personal/Projects/trips
set -a && . ./.env.local && set +a
export VK_TOKEN=$(grep '^vk' tokens.tsv | cut -f3 | sed 's/.*?k=//')
export NATI_TOKEN=$(grep '^nati' tokens.tsv | cut -f3 | sed 's/.*?k=//')
export RUTHU_TOKEN=$(grep '^ruthu' tokens.tsv | cut -f3 | sed 's/.*?k=//')
bash scripts/test-rls.sh
```
Expected: own upload/sign = `200`; organizer sign = `200`; cross-member sign/upload = `400` or `403`; anon = `400/401/403`. **If a cross-member call returns 200, RLS is broken — stop and fix `setup.sql` before shipping.**

- [ ] **Step 3: Commit**

```bash
git add scripts/test-rls.sh
git commit -m "test: curl RLS matrix proving per-person isolation + organizer access"
```

---

### Task 8: Docs — update CLAUDE.md + README

**Files:**
- Modify: `CLAUDE.md` (Open decisions / roadmap + Current state)
- Modify: `README.md`

- [ ] **Step 1: Update `CLAUDE.md`**

In the "Open decisions / roadmap" section, remove the "Self-serve uploads" bullet's "needs a backend / chosen option" framing and move the shipped capability into "Current state":
- Add to **Current state**: "Self-serve TDAC uploads: each person opens a personal `?k=` link → uploads their card to Supabase Storage (private bucket, RLS); they see their own, the organizer sees all. Falls back to Generate/WhatsApp when no link/offline."
- Add a short **Backend** subsection: bucket `tdac`, RLS by `auth.jwt()->>'sub'`, tokens minted by `scripts/mint-tokens.mjs`, config in the `TDAC` block; secret never in repo.

- [ ] **Step 2: Update `README.md`**

Add a "Self-serve arrival cards" note: open your personal link to upload/view your TDAC; organizer sees everyone's; no link → Generate/WhatsApp as before.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: record self-serve TDAC uploads in CLAUDE.md + README"
```

---

## Deploy (after all tasks green, with VK approval)

Not a task — explicit gate. Once Tasks 1–8 pass and VK approves the push:
```bash
git checkout main && git merge --no-ff feat/self-serve-tdac-uploads
git push origin main      # Vercel auto-deploys
```
Then the organizer distributes the 8 member links + keeps the organizer link, via WhatsApp. Re-run the Playwright member/organizer checks against the live Vercel URL as a smoke test.
