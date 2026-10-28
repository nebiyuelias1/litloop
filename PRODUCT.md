# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Primary users are volunteer book club organizers. They run a club with a small budget and no dedicated tools: they choose the next book, schedule a meetup, collect RSVPs, prepare discussion questions, and keep members informed. Readers are the secondary audience: they browse the catalog, join or request access to clubs, RSVP to reads, rate and review books, and take part in discussions.

## Product Purpose

LitLoop is an operating system for book clubs. It exists so a club can move through a complete read cycle — pick a book, announce a meetup, gather RSVPs, prepare discussion, and close out the read — without stitching together chat threads, spreadsheets, and forms. Success means clubs actually schedule reads, members RSVP, and discussions happen around the meetup.

## Positioning

LitLoop organizes the live club read as its central object. A neighboring catalog, review site, or chat group can copy book records and star ratings, but not the end-to-end club cycle: polls to choose a book, a scheduled meet with capacity and RSVPs, translated discussion questions, and a finalized read history. Book discovery exists to start the next read, not to become an endless shelf.

## Operating Context

- Clubs operate across web and a Turbo Native mobile app that wraps the same Rails web surface; there is no separate native design language.
- Members sign in with email, Telegram (including Telegram Mini App), or LINE.
- The interface is multilingual: English, Amharic, Simplified Chinese, and Traditional Chinese are supported, and users choose their language explicitly.
- Read logistics are real-world: meetup time and place, host, maximum capacity, RSVP status, reminders, and invitation emails.
- Private clubs vet new members through an external application form and in-app membership requests.
- Admins use an in-app admin area to manage books, clubs, reads, polls, questions, reviews, ratings, tags, and users.

## Capabilities and Constraints

- Crowd-sourced book catalog with title, author, description, publisher, year, language, ISBN, page count, cover, source metadata, and multilingual title/author variants.
- SQLite FTS5 full-text search across the catalog.
- Ratings, text reviews, threaded replies, and review likes.
- Book clubs, public and private, with owners, admins, members, and pending membership requests.
- Book reads with host, meetup time and location, capacity, RSVPs, reminders, and iCal-style calendar sequencing.
- Polls for selecting a book, including options suggested by members, with finalization and vote tracking.
- Discussion questions attached to a read, with translations and edit tracking.
- Theme tokens in `theme.toml` are the single source of truth for web (Tailwind), Android, and iOS colors and icons.
- Stack: Rails 8, SQLite, Hotwire/Turbo, Stimulus, Tailwind CSS with DaisyUI, Propshaft, Devise, Solid Queue/Cache/Cable, Kamal.
- Undecided at this stage: monetization, target geography, a formal accessibility standard, and whether the PRD's "want to read" list is a committed surface. Do not present these as settled.

## Brand Commitments

- The product name "LitLoop" is durable and binding.
- Visual identity is open to reconsideration; the prior navy/gold palette and existing logo are evidence of the previous look, not permanent constraints. The current palette is warm vellum/deep-spruce with a single oxblood accent.
- Voice and tone guidelines are not established.

## Evidence on Hand

- A working Rails application with the surfaces above, plus a Turbo Native mobile shell in `mobileApp/`, `android/`, and `ios/`.
- Existing brand assets: `backend/app/views/shared/_logo.html.erb` and icons under `icons/`.
- Translation files: `backend/config/locales/{en,am,zh-CN,zh-TW}.yml`.
- Demo seed data with Ethiopian names, Amharic tags, and sample clubs/reads in `backend/db/seeds.rb`; this is fixture content, not real customers.
- No real customer testimonials, usage metrics, press coverage, benchmarks, or production catalog data are available. Future work must not fabricate them.

## Product Principles

1. The scheduled read is the unit of value. Design around the read cycle, not around browsing.
2. Organizer effort is the load-bearing path. Every feature should reduce the work of running a club, not add admin overhead.
3. Discovery must lead to a real read. Catalog and search earn their place by starting or supporting a club's next book.
4. Multilingual is a user choice, not an assumption. Language switching and translated content are product-level concerns.
5. Preserve the name, leave room for the visual world. Identity can evolve; the club-centered promise cannot.
