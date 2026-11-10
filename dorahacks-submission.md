# DoraHacks submission copy — Litloop × Otari
# (paste-ready blocks; trim to whatever the form asks)
# Deadline: Thursday Nov 12, 2026 12:59 PM Taiwan time

---

## Project name

Litloop — AI book-metadata enrichment & club Literature DNA

## One-liner

A book-club app that researches, judges and upgrades its own book metadata
(covers, descriptions, tags, country of origin) with open-weight AI models —
every AI action cited, sandbox-verified and reversible — then reads the whole
club's history back: the Literature DNA tab turns reads-into-story with
countries-read world map and stat cards whose every number was verified in
Otari's code-execution sandbox.

## Repo & submission branch

- Repo: https://github.com/nebiyuelias1/litloop
- Feature stack: `feat/ai-metadata-enrichment` + `feat/ai-cover-image`
  (submitted branch) stacked over `feat/book-metadata-fields`
  + `feat/otari-client`, base `otari-hackthon`
- Literature DNA: `feat/club-literature-dna` (PR #137)
- First Otari commit: `c197ee1` — "add Otari AI gateway client service"

---

## Otari features used (checklist for the form)

1. **One endpoint, many models** — `openai/gpt-oss-120b` (primary, open
   weights), `mistral/mistral-large-latest` (frontier escalation),
   `deepseek/deepseek-v4.1-flash-1017` (cover vision, open weights).
2. **Gateway-run built-in tools** — `otari_web_search` (per-request
   `max_uses`) for book fact grounding; `otari_code_execution` for the club
   DNA: the model computes the stats it quotes in the gateway's Python
   sandbox instead of hallucinating numbers.
3. **Structured outputs** (strict json_schema) — per-field judge verdicts in
   enrichment (keep_existing | update + source_url + verbatim quote).
4. **Files API + file content blocks** — stored-cover bytes uploaded for
   vision review; "is this really the cover of this (possibly Amharic) book?"
5. **Usage dashboard** — per-call, per-model cost; routed budgets/virtual key.

## How it works (for judges in 45 seconds)

- Every enrichment = GROUND (web search, facts with source URLs) → JUDGE
  (structured verdicts vs stored metadata, only update when it cites) →
  SEE (vision judge on cover bytes) → VALIDATE (deterministic Ruby: citation
  whitelists, ISO-3166 code gate, image probes, vision budget) → APPLY
  (persist + full audit JSON, originals kept).
- The club Literature DNA is the same philosophy applied to a club:
  Rust-side/deterministic stats, LLM narrative, and a mechanical
  dot-path gate — a stat printed by the model only survives if the dataset
  actually resolves to that value at the path it cites.

## Results we can show (live)

- ኦሮማይ (Oromay): unsplash placeholder → **real Goodreads cover found via the
  judge's cited URL**, vision-gated.
- የተቆለፈበት ቁልፍ: real Amharic cover sourced & verified.
- The Alchemist: publisher-CDN 25th-anniversary cover.
- Death of Vivek Oji: an Italian edition cover nearly tricked the gate —
  vision check rejected it; exact publisher-cover installed (1538×2400).
- Club DNA: e.g. "አዲስ አበባ መፅሐፍ ክለብ" — 3 books, all from Ethiopia, map
  paints ET, tags like ታሪክ/ፍቅር surfaced, sandbox-verified stats cards.

---

## Written feedback blocks (honest, specific)

### Where the friction was — and where I was tempted to skip Otari

- **The hosted key died mid-project.** A key that had worked the previous
  day started returning `401 Invalid API key` between runs, with no visible
  expiry or reason on the dashboard; all my tool-traffic froze while I
  re-issued a key. Higher-stakes than a normal API blip because status pages
  and key-health UNTIL I built my own probe didn't exist — I only found
  `GET /api/v1/key/budget` by reading the API reference. A tiny "test key
  now" button or key-status row in the dashboard's key list would have saved
  an hour of doubt. (And an `otk_v1…` format — listing key health instead of
  guessing whether it is expired vs revoked vs mistyped — is genuinely hard
  to self-diagnose.)
- **Empty-content quirk** in long tool loops with `gpt-oss-120b` + web
  search: the model would burn tokens tool-calling, then hand back an empty
  final content. Mitigated by degrading to the frontier model, escalation
  logic — but it caught me off-guard twice.
- **Files-API auth header** (`Otari-Key`) is documented only in one place;
  inline `image_url` parts were silently dropped for open-weight vision
  models (no error, just no image understanding). A 400 with a hint would be
  kinder than silence.
- **One design smell I'd change:** per-tool `max_uses` web search with a
  60-second request timeout produced many slow runs; a `tool_budget_s`
  request-side timeout default would make deterministic cost/latency per run
  achievable without my own stopwatch.

### What I built with Otari (short)

(see checklist above) — one-model, one-gateway architecture with open-weight
models everywhere, gateway-run search as "the app researches before it
judges", sandboxed code execution as "AI math is verifiable math".

### What I'd change / want next

1. Key health/last-used/expiry on the dashboard key list + "test this key"
   button.
2. A documented, stable **Files API + image understanding path** for
   open-weight VL models (and gallery-style doc example with `Otari-Key`).
3. Tool-loop stream events after the final content (or stderr for external
   tool failures) surfaced in `otari_tool_calls`.
4. A timeout/slow-run Mode switch on per-request tool budgets (so gate apps
   can trade depth for latency deterministically).

### What I loved

- One virtual key and one endpoint — I never once created an upstream
  account or read a second SDK's errors.
- `otari_code_execution` is the single best idea in the feature set:
  "verify the numbers in a sandbox before you say them" upgraded my club-DNA
  gate from "trust the narrative" to "trust only the printed numbers",
  which is a real shift in how you prompt/wrap LLMs.
- Usage dashboard's per-call cost trace made my feedback-rail architecture
  (escalate only when underconfident) provable in numbers — $0.0243 total
  across ~38 calls.
- Open-weight models were first-class, not a checkbox: gpt-oss-120b did all
  search-tool work; deepseek's vision model verified Ethiopian-script covers.

---

# Demo video shotlist (3–5 min, non-AI — record in one sitting)

1. [0:00] Otari dashboard: Activity page (mesmerizing top-down: web search
   + call + cost per row), then keys page briefly.
2. [0:30] Litloop book detail — death of Vivek Oji: show ✨ AI-assisted
   badge, "show previous description" toggle, country flag 🇳🇬, tags.
3. [1:00] Admin book page: audit JSON panel (sources, verdicts, old→new
   cover bytes). Click "AI enrich" on a fresh book; cut to log tail
   (`[enrich #…]` lines streaming).
4. [2:00] Back to the book: new cover in place; map/description updated.
5. [2:30] Club page ("አዲስ አበባ መፅሐፍ ክለብ"): Literature DNA tab → world map
   with ET shaded, verified stat cards ("At a glance"), signature traits,
   "Untapped territory", footer crediting model + Otari sandbox.
6. [3:30] To record an owner-only view: click "✨ Generate Literature DNA"
   on a member-only club; show queued flash; open the sandbox audit trail.
7. [4:00] Outro: repo + branches (submission checklist from the deck).
