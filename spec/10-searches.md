# Searches

## Search Button

A **Search** button in the tree button bar opens a dialog asking for a search string (treated as a case-insensitive regular expression).

## Search Scope

The search runs over all visible link names under the currently selected node:
- **Domain selected** — searches all paths and links under that domain.
- **Group selected** — searches all paths and links under that group.
- **Path selected** — searches all links under that path.
- **No selection** — searches all domains, paths, and links.

## Search Results

A top-level **Search** node appears in the tree (alongside Fresh and Tagged). Each search creates a child collection node whose label is the search regexp. Under it, matching links are shown as leaf nodes (with their original domain/path for selection and preview).

Multiple searches accumulate under the Search node.

## Persistence

Searches are persisted to `k2bro_searches.json` in the app documents directory. The file is a JSON array where each entry has:
- `pattern` — the search regexp string
- `matches` — array of `[domain, path, link]` triples

Searches are saved after adding or removing a search, and restored on app startup.

