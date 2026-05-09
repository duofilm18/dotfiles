---
name: internal-link-optimizer
description: >
  Audit and improve internal links, anchor text, and target-page alignment for SEO. Use when a
  site has keyword cannibalization risk, the wrong page ranks for a query, hub/supporting-page
  connections are weak, pages are orphaned, or the user wants ranking gains from internal-link
  changes instead of rewriting everything.
---

# Internal Link Optimizer

## Overview

Use this skill to decide which page should rank for a keyword, inspect how the site currently links
to that topic, and produce a safe internal-link change plan. Focus on target-page alignment,
anchor-text distribution, crawl discoverability, and link equity flow.

## Workflow

### 1. Define the target map first

Do not start by editing links. First write down:

- primary keyword or topic
- target page that should rank
- supporting pages that should feed that target page
- pages that should stop competing for the same intent

If the site has no clear target page, stop and recommend creating or upgrading one before changing
links.

### 2. Audit the current internal-link pattern

Check:

- which pages already link to the target page
- which pages use the main keyword as anchor text
- whether the main keyword currently points to the wrong page
- whether important pages are too deep or weakly linked
- whether there are orphan or near-orphan pages

When working in a codebase, prefer `rg` to find:

- the target keyword
- the target URL slug
- existing anchor text variants

Useful searches:

```bash
rg -n "keyword|target-slug|anchor phrase" .
rg -n "<a .*target-slug|href=.*target-slug" .
```

### 3. Classify links before changing anything

Sort findings into:

- keep: already points to the correct page with a sensible anchor
- retarget: correct anchor concept, wrong destination
- rewrite: destination is fine, anchor text is weak or misleading
- add: supporting page should link but currently does not
- avoid: forced exact-match anchor that would look spammy

### 4. Choose anchor text conservatively

Prefer natural distribution. Mix:

- exact or close-match anchors on the strongest, most relevant pages
- partial-match anchors on most supporting pages
- generic navigational anchors only where UX requires them
- branded anchors when the page is a homepage or service hub

Do not make every supporting page use the exact same keyword anchor. Keep the pattern believable
and readable.

### 5. Use stronger pages to support weaker pages

Prioritize links from:

- homepage or key hubs
- major collection pages
- high-traffic evergreen articles
- pages already ranking or earning links

Do not spray links everywhere. Add links where topical relevance is obvious and user value is real.

### 6. Protect structure and crawlability

Do not improve anchor text while making navigation worse. Preserve:

- logical hierarchy
- breadcrumb consistency
- collection-to-detail relationships
- important utility links users rely on

If a page is orphaned, fix discoverability first, then fine-tune anchors.

### 7. Produce a change plan before editing

Before making changes, summarize:

- target page
- pages to update
- exact link action on each page
- anchor-text rationale
- expected SEO effect

When useful, format the plan as:

| Source page | Current link | Change | New anchor | Why |
|-------------|--------------|--------|------------|-----|

### 8. Validate after changes

Re-check:

- that the intended target page gained the strongest internal signals
- that competing pages are no longer over-optimized for the same query
- that no broken or redirected internal links were introduced
- that links still read naturally in context

## Do Not Do These

- Do not start changing links before deciding the target page
- Do not use exact-match anchors everywhere
- Do not add links where topical relevance is weak
- Do not treat archive dumps as sufficient topic hubs
- Do not ignore cannibalizing pages that should stop competing
