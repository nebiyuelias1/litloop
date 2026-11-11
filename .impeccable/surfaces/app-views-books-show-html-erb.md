---
version: 1
slug: "app-views-books-show-html-erb"
primary_target: "app/views/books/show.html.erb"
related_targets: []
---

# Surface brief — Book detail page (books#show)

**Mode:** Operate (catalog facts, rate/review, route to the next real read)
**Target:** `backend/app/views/books/show.html.erb` (+ BooksController#show data)

## Audience / job
A reader deciding on a book: confirm what it is, judge it (rate, review), and see where it is being read. An organizer scouting a possible next pick.

## Proof / content
Real catalog record: title/author + multilingual variants, tags, publisher/published/language/pages/country/ISBN/source, description with AI-enrichment provenance, average rating + reviews with likes, and the book's published club reads (upcoming, with RSVP; past as a count).

## Direction (established world: The Circulating Library)
"Catalogue entry" page — same flat-on-vellum grammar as book_reads#show: `max-w-4xl` reading column, sections separated by deckle-edge rules. Header row = cover + catalogue header (tags, serif title, romanized/secondary variants, byline, rating summary). Facts ledger as ruled records (labels over values, no icons). About + provenance under a hairline. "Currently being read" section reuses `shared/_book_read_card` (live oxblood idiom, RSVP). Rating strip as a book-page sheet echoing the RSVP card. Reviews as the marginalia section. Oxblood reserved for live reads, the rating star row, and hover emphasis.

## Commitments
- Keep Stimulus contracts: `rating` (star targets/values), `review-like`, `collapsible_text`; fix their off-theme drift (gray/yellow/red classes) to theme tokens.
- i18n: move hardcoded copy into locale keys for en, am, zh-CN, zh-TW.
- No new claims or data not in the product; cover proxy route (`cover_book_url`) reused for `<img> where appropriate.

## Unresolved
- Placeholder imagery, monetization, "want to read" list: out of scope, not fabricated.
