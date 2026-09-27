-- Saman Pantry 1.2. Sharing a recipe is still anonymous product analytics:
-- same columns as 006 (install id, event name, app version). No recipe text
-- is stored. Inserts of recipe_shared fail until this constraint is applied.

alter table public.events drop constraint if exists events_event_check;

alter table public.events add constraint events_event_check check (event in (
  'app_open', 'signup', 'guest_start', 'item_added', 'list_item_bought',
  'pantry_restocked', 'recipe_saved', 'recipe_extracted', 'recipe_shared',
  'paywall_viewed', 'purchase_started'
));
