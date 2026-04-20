# Saman Pantry — Product Thesis v1
One page. Updated as the product evolves. When a design decision comes up, answer it against this doc first. If the doc doesn't resolve it, the doc gets updated.


## What it is
A native iOS app that helps one person keep track of what's in their desi kitchen and what they need to buy next.

"Saman" is Urdu for provisions. The product is shaped around how Pakistani and South Asian households actually stock, cook, and restock. Staples first, not generic groceries.


## Who it's for
Primary user (v1): The 25 to 35 year old diaspora adult running their own kitchen for the first time. Apartment or small household. Cooks desi food regularly, not occasionally. Buys atta, daal, masalas, ghee, and halal meat from Patel Brothers, Zabiha, or the local South Asian grocer. Has no system for tracking what's running low beyond opening the cabinet and guessing.

Explicitly not the primary user at launch:

- Multi-person households with shared responsibility (planned for v2, see below)
- Older parents and aunties who run the kitchen by memory
- Non-desi users (they can use it, but the product isn't shaped around them)


## The problem
Running a desi kitchen means staying stocked on a specific set of staples that turn over in a specific rhythm. Miss atta on Friday, no rotis this weekend. Run out of haldi mid-recipe, dinner stops. Existing pantry apps treat every item the same and don't understand the cultural rhythm. Whiteboards and mental lists work until they don't, which is usually right when you're standing at the store.


## The core loop
See what's low → add to shopping list → shop → mark as bought → pantry updates.

That is the entire product. Everything else either serves this loop or gets cut.


## What it is not
- A meal planner
- A recipe app
- A grocery delivery product
- A household management system (v1)
- A generic inventory tracker
- A sustainability or waste-reduction app

We do not compete with Paprika, Samsung Food, or Whisk. A user can live inside this app without ever planning a meal.


## Why this approach
- Native, not hybrid. This app gets opened weekly for years. It has to feel fast and quiet.
- Culturally specific by design. Starting broad and localizing later produces a generic app that impresses no one. Starting specific produces a product with a voice.
- Small surface area, deep loop. One thing done correctly beats five things done partially.


## Success criteria
What "this worked" looks like, for this project specifically:

- 500 weekly active users within 12 months of public launch
- Average user opens it twice a week or more
- At least 50 users who would be visibly upset if it shut down
- Portfolio credibility that makes the next Saman Technologies product easier to take seriously
- Small, honest revenue from a paid tier. Not a VC-scale outcome.

This is a product meant to be loved by a small audience, not scaled to millions.


## v2: household mode
Household sharing is designed into the data model from day one but is not shipped at launch. Conditions for turning it on:

- 500+ weekly active users on v1
- 30%+ of active users ask to share with a partner or roommate
- Bidirectional sync is stable in production

Until those conditions are met, household mode stays off the roadmap.


## Non-negotiables
- The Reorder tab must actually restock. No lying to the user.
- Pantry and shopping list are one loop, not two separate features.
- Sync must work bidirectionally before public launch.
- No feature ships unless it advances the core loop.
- The app never stops feeling like a desi product.


## What gets cut if we're honest
- Prices tab in its current form. Either it earns its place by doing price history or store comparison, or it goes away.
- Barcode scanning as a top-level tab. Scanning is a data-entry method, not a destination. It moves inside the Add Item flow.
- Settings as a tab. Becomes a button in the top bar.

This leaves three real tabs: Pantry, List, Reorder. Or two if Reorder folds into Pantry, which is worth considering.


---

_Version 1 — keep this doc under one page. When it grows, something is wrong._
