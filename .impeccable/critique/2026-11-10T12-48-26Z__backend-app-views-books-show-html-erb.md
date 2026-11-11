---
target: book detail page ui
total_score: 23
max_score: 40
na_heuristics: 
p0_count: 1
p1_count: 2
target_identity: "file:/home/netale/projects/personal/arif-nibaboch/backend/app/views/books/show.html.erb"
target_fingerprint: "sha256:1025d1ff3c4b43de44cf2e9722ad4c72cc0307fde2ce512b00f3b309bb2d0269"
target_path: /home/netale/projects/personal/arif-nibaboch/backend/app/views/books/show.html.erb
timestamp: 2026-11-10T12-48-26Z
slug: backend-app-views-books-show-html-erb
---
⚠️ DEGRADED: single-context (subagent spawn refused by harness — nested-subagent depth limit reached; Assessments A and B ran sequentially inline, A fully first)

# Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2 | "Not yet rated" is honest status but no action exists anywhere to change it; posting a review has no on-page confirmation |
| 2 | Match System / Real World | 3 | Catalogue language idiomatic; "AI-assisted" explained only on hover |
| 3 | User Control and Freedom | 2 | No edit/delete for one's own review; no undo path beyond like-toggle; "Sign In to Review" loses return context |
| 4 | Consistency and Standards | 3 | Token-disciplined, but tag pills use `rounded-full` against the 8/12/16/24 ladder; review count appears twice |
| 5 | Error Prevention | 2 | Review form has no length constraint/hints; no draft protection |
| 6 | Recognition Rather Than Recall | 2 | The rating action (per surface brief) is invisible because it doesn't exist; signed-out like numeral is unlabeled |
| 7 | Flexibility and Efficiency | 2 | Only accelerator is the `#reviews` anchor; no keyboard paths beyond those |
| 8 | Aesthetic and Minimalist Design | 3 | Clean and restrained; duplicated count and long header lines are the noise |
| 9 | Error Recovery | 2 | Review form has no visible error/refill path; rating controller fails to `console.error` only |
| 10 | Help and Documentation | 2 | Contextual help is a hover-only `title` tooltip on the AI-assisted chip — absent on touch/keyboard |
| **Total** | | **23/40** | **Acceptable — significant improvements needed before users are happy** |

# Design Specificity Verdict

**LLM assessment.** When it works, it is authored: hairline deckle rules between sections, Playfair Display headings over an Ethiopic-first sans, facts laid out as ruled catalogue records with honest "Not set" values, muted tag chips, and oxblood reserved for the star row and the AI-assisted stamp. The vellum/book-page tonal separation and the sign-in banner as a Book Page sheet match the "Circulating Library" world. But the page reads as a **print catalogue record**, not LitLoop's club-cycle product: a book that is currently being read (Dune has one live read) shows zero trace of it. A generic book-database product could ship this page unchanged — which is the definition of category-interchangeable. The AI-assisted provenance chip ("source-checked, see provenance") is the one truly product-charactered element.

**Deterministic scan.** CLI scan over `books/show.html.erb` + `shared/_collapsible_text.html.erb` + `shared/_avatar.html.erb`: **0 findings** (exit 0). CDP-attached detector on the rendered page (`http://localhost:3000/books/87`) returned **2 findings**:
1. `line-length` (quality, warning): the header description column renders ~93 chars/line on 6 of 7 lines (`div.line-clamp-6` p) — over the ~80-char readability limit.
2. `cream-palette` (slop, warning): vellum page background `rgb(246,241,231)`.
The detector caught the line-length issue, which the review had not; **the cream-palette finding is a false positive under this brief** — vellum is DESIGN.md's named "Vellum Ground Rule" (the committed palette), and "The brief wins" over generic slop warnings.

**Visual overlays.** No reliable user-visible overlay is available: the harness exposes no browser service, so the detect.js injection into a `[Human]` tab could not be performed; evidence was gathered via a CDP-attached headless Chromium instead (fallback signal).

# Overall Impression

A quiet, warm, well-typographed catalogue card — and that is the problem: it is a card on display, not a page you act on. The single biggest opportunity is the missing **"Currently being read"** section: the surface's own brief (and the product principle "the scheduled read is the unit of value") makes the route from book to live read + RSVP the core job of this page, and that content is entirely absent — the controller doesn't even query the book's reads. Second: the star summary is dead honestly ("Not yet rated") because the rating UI this product already has (`rating_controller.js`, POST `/books/:id/ratings`) is orphaned — no view mounts it.

# What's Working

1. **Cohesive catalogue grammar.** Deckle hairlines, serif-over-sans two-register discipline, muted tag chips, and strict oxblood restraint (stars + AI-assisted icon only). Every section matches the established world tokens.
2. **The facts ledger.** Label-over-value records with honest "Not set" fallbacks and a conditional ISBN row; the country cell even distinguishes "Unknown" (post-enrichment) from "Not set" — excellent catalogue restraint.
3. **Progressive disclosure with provenance.** The 6-line description clamp + "Show more", and the "Show previous description" `<details>` revealing the original description, model used, and a source link — honest, trust-building AI provenance, done with native elements.

# Priority Issues

1. **[P0] The read is missing — no "Currently being read" section at all.** Dune (id 84) has a book read; the page renders nothing about reads. `BooksController#show` loads only `@reviews`. The surface brief explicitly specifies reusing `shared/_book_read_card` (live oxblood idiom + RSVP) and a past-reads count. *Fix:* load reads in the controller; render upcoming reads via `shared/_book_read_card` and, when there are no upcoming ones, a past-reads count line with a link into the club — never let a read-bearing book render as pure catalogue. *Suggested command:* `/impeccable shape` (then `/impeccable layout`).
2. **[P1] Rating is a dead feature on this page.** `rating_controller.js` is registered and posts to `/books/:id/ratings`, but no view mounts `data-controller="rating"` — visitors cannot act on "Not yet rated", ever. *Fix:* mount the interactive star strip as the brief's book-page rating sheet near the header summary, signed-in only; add real UI feedback on save/failure. *Suggested command:* `/impeccable shape`.
3. **[P1] "Sign In to Review" is a context trap.** It links to `new_user_session_path` without a `redirect_to` param, so a first-timer or mobile user gets dumped on the post-auth landing page and never returns to this book; her typed intent is lost the moment she clicks. *Fix:* pass a return parameter to the sign-in link and honor it after auth. *Suggested command:* `/impeccable harden`.
4. **[P2] Rating/review semantics are conflated.** "Not yet rated" beside "1 review" implies reviews don't produce ratings — true here, but the page never says which is which; the review count also appears twice (header link + section header). *Fix:* label the count once, and if ratings are separate from reviews, say so ("Rate it · 0 ratings · 2 reviews"). *Suggested command:* `/impeccable clarify`.
5. **[P2] Header description runs ~93 chars/line** (detector `line-length`). *Fix:* cap the description column at 65–75ch (e.g. `max-w-[68ch]`) or narrow the flex column. *Suggested command:* `/impeccable layout`.

# Persona Red Flags

**Casey (distracted mobile user):** the like affordance is a 16px icon with ~26px tap area — under the 44×44 touch floor; the "AI-assisted" explanation is hover-only, invisible with a thumb; after "Sign In to Review" she never returns to this book (context trap, P1 issue 3).

**Riley (deliberate stress tester):** a refresh or interruption in the review textarea loses the draft — no autosave, no preserved state; no max-length hint, so a wall of text is posted unformatted; publisher values truncate silently mid-name ("Heinemann Educational Bo..."); test-quality reviews ("dfasdf") render unmoderated with no reporting or moderation affordance.

**Jordan (confused first-timer):** "Not yet rated" next to "1 review" is a semantic trap — she will review the book and expect the stars to update; they won't. "Back to Library" is ambiguous naming. The heart icon from a signed-out state shows a bare numeral with no label of what it counts.

**Organizer scouting a next pick (project persona, from PRODUCT.md):** the page fails her primary question — "is this book being read / can we pick it next?" — completely. She must leave the page and hunt clubs manually. For the operating system of book clubs, that is the load-bearing path not carried.

# Minor Observations

- Tag chips use `rounded-full`; the ladder reserves full pills for search/avatars/dots/status, and DESIGN.md's status badge spec is 8px.
- Review count text appears twice (`#reviews` count in the header, then the section header's "N reviews").
- Facts values at `font-bold` read heavier than "ruled record" (try `font-medium`).
- On mobile the fixed `w-40` cover sits left with dead space beside it; consider centering or letting it breathe wider.
- Signed-out visitors with a zero-review book get the sign-in banner but no empty-state invitation into the club cycle.
- The mobile bottom nav only exists on `home#index`; on this page navigation falls back to the top hamburger — a known cross-surface split (Thumb Zone rule) worth a separate conversation, not a page-local fix.

# Questions to Consider

- What would this page look like if the **read**, not the record, was the hero — header beside the live meet card rather than above a facts ledger?
- Is a star summary you can't act on better than no star summary? (An act-able rating strip changes the whole snapshot.)
- Could the AI-provenance chip become the product's signature trust element — "source-checked" as a visible badge system across catalog facts?
