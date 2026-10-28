---
target: book read detail page
total_score: 23
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
target_identity: "file:/home/netale/projects/personal/arif-nibaboch/backend/app/views/book_reads/show.html.erb"
target_fingerprint: "sha256:347526416d7fff4bc9ba29b90d476c6a0890395e1497d4000a26a7a3769ee7ac"
target_path: /home/netale/projects/personal/arif-nibaboch/backend/app/views/book_reads/show.html.erb
timestamp: 2026-10-28T07-25-00Z
slug: backend-app-views-book-reads-show-html-erb
---
# Critique: Book Read Detail Page (`book_reads/show.html.erb`)

Run method: degraded single-context (no sub-agent tool exposed); A finished before detector ran.

## Design Health Score (all 10 scored, max 40)

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Capacity bar, relative time hint, RSVP state labels good; vote-submit feedback relies on Turbo re-render |
| 2 | Match System / Real World | 2 | Amharic content under English chrome; raw strftime English dates on a 4-language product |
| 3 | User Control and Freedom | 3 | Cancel confirm, expandable results, native dialog Esc; dropdowns lack Esc |
| 4 | Consistency and Standards | 2 | Radius off-ladder, raw palette colors, inline onclick; gold accent fails at runtime |
| 5 | Error Prevention | 3 | turbo_confirm guards, disabled vote until selection, required textarea |
| 6 | Recognition Rather Than Recall | 2 | Attendee list behind unmarked clickable row; Edit/Back buried in More Actions |
| 7 | Flexibility and Efficiency | 2 | Single path; Web Share on poll is the only accelerator |
| 8 | Aesthetic and Minimalist Design | 3 | Calm reading column; capacity echoed 3x; flyer is a foreign visual world |
| 9 | Error Recovery | 2 | Generic red error box; no inline field errors |
| 10 | Help and Documentation | 1 | No contextual help for waitlist or Draft→Approved→Reveal Live workflow |
| **Total** | | **23/40** | **Acceptable** |

## Design Specificity Verdict

Partially authored. Stamped-well panel, hairline borders, 56rem reading column, privacy panels are genuinely LitLoop. But Bookplate Gold does not render anywhere at runtime: `<html data-theme="silk">` lets DaisyUI's silk theme override `--color-accent` (silk oklch(23.27% .0249 284.3) ≈ #1c1c29 wins over theme.css #d39a3e in the cascade). Every text-accent/bg-accent renders ink-dark. The share-flyer dialog embeds an unrelated slate-950/indigo-950 Instagram-story world.

Detector: clean, 13 advisories, all design-system-font-size (9px/10px/13px) in show.html.erb (140,154), _share_flyer_dialog (94,110,127,128,160,161), _rsvp_users (3), _vote_form (33), _vote_results (33), _discussion_question (43,56). 9px avatar initials borderline false positive; 13px/10px inside flyer artifact.

Browser: capacity bar fill pixel-sampled #1C1C29 at 1280px; served tailwind-33a1eed1.css contains both --color-accent definitions with silk last. Overlay injection skipped (no mutable-evaluate driver); fallback = pixel sampling + served-CSS cascade inspection.

## Priority Issues

1. [P1] Bookplate Gold dead at runtime — DaisyUI silk theme hijacks --color-accent app-wide. Fix theme.css load order / scope tokens to [data-theme=silk]; verify capacity bar pixel = #d39a3e. Suggested: colorize or audit.
2. [P1] Mobile sticky RSVP bar (sticky bottom-0 z-10) covered by fixed bottom nav (z-50 h-16) for signed-in users. Fix: bottom-16 sm:bottom-0 or move RSVP into nav layer. Suggested: adapt.
3. [P1] ~20 hardcoded English strings + raw strftime("%B %d, %Y at %I:%M %p") (show.html.erb 390,409; _meetup_details 22) instead of t()/l(); inconsistent with flyer. Suggested: clarify, then harden.
4. [P2] Host/attendee row is an invisible button opening rsvp_dialog (show.html.erb 126-148); no affordance; inline onclick. Suggested: onboard or polish.
5. [P2] Anonymous users see unusable Post Question form (public club, signed out); heading skip h1→h3→h2 (show.html.erb 116→170→304); View details link nested in checkbox label (_vote_form 33). Suggested: harden + audit.

## Persona Red Flags

Sam: heading skip; aria-expanded hardcoded false (_discussion_question 74); nested interactive in label; no Esc on dropdowns; 9px/10px text. Casey: RSVP action covered by bottom nav when signed in; capacity fact repeated 3x; QR via api.qrserver.com leaks URL, fails offline. Jordan: Reveal Live / waitlist unexplained; Back to club hidden in More Actions; host row affordance invisible.

## Minor Observations

Main sheet rounded-lg vs 24px reading panels; rounded-md vote button; ring-black ring-opacity-5 in dropdown; flyer gradient world; w-4.5 h-4.5 no-op classes; aspect-auto cover dead space; "No RSVPs yet" dead end.

## Questions to Consider

- What if RSVP lived in the bottom nav instead of two floating bars?
- If gold can't survive the cascade, should silk be promoted into DESIGN.md as the real world?
- Could the flyer wear navy/gold instead of a foreign midnight gradient?
