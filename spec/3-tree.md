# File Tree (Right Pane — Bottom)

The bottom of the right pane contains a collapsible tree view with +/- expand/collapse controls.

## Tree Structure

Reading and writing from `data.json` (see [5-format.md](5-format.md)). The tree has three top-level category nodes:

- **Fresh** — all links that have no rating and no tags
  - **Domain**
    - **Path**
      - **Link**
- **Rated** — links that have a rating but no tags
  - **Rating groups** (Super, Top, Ok, Uhm) — collapsible nodes
    - **Domain**
      - **Path**
        - **Link**
- **Tagged** — links that have at least one tag (regardless of rating)
  - **Rating groups** (Super, Top, Ok, Uhm) — collapsible nodes
    - **Domain**
      - **Path**
        - **Link**
  - Unrated tagged links appear after the rating groups, grouped by domain > path

Each top-level node shows a count of total links it contains. Rating group nodes also show a count.

**Link** shows the portion after `https://k2s.cc/file/<id>/`; if empty, shows the `<id>`. Nodes at the same level are sorted alphabetically. Empty domains/paths (with no matching links) are omitted.

Paths (collections) can also be rated using the rating buttons. Rated paths are sorted by rating (best first), then alphabetically within the same rating. Unrated paths appear after rated ones. The path node shows its rating color.

For each link, tags are displayed inline. Clicking a tag jumps to that position in the video on the currently selected player.


## Button Bar

Below the tree, a button bar with: **Add**, **Extract**, **Remove**, **Recents**, **Play**, **View**, **Unrate**.

### Unrate

Removes the rating from all links under the selected node (domain, path, or single link), making them unrated (fresh).

### Add

Adds the current browser URL to the tree:
- Adds the domain if not already present, save also the protocol (http) if it nos https:
- Adds the path (unless it is the home page) including the query string

### Remove

- On a **link**: removes it immediately.
- On a **path** or **domain**: asks for confirmation before removal.

### Extract

1. Scans the current browser page text for all links matching `https://k2s.cc/file/...`.
2. For each found link, calls the `getFilesInfo` API (see [9-util.py](9-util.py)) to check availability.
3. If `is_available` is true, adds the link to the tree.
4. If a link already exists in the tree but is no longer available, removes it (allows re-extraction to update status).
5. Does not change the hidden state of existing links.

### Play

Enabled when the browser is on a `https://k2s.cc/file/...` URL or when a k2s link is selected in the tree. Clicking it plays the video in the currently selected player (resolves the download URL, adds to recents, and starts playback at frame 0).


### View

Open Directly the page `https://k2s.cc/file/<id>`

## Navigation

- Clicking a **domain** or **path** opens that page in the browser.
- Clicking a **link** activates the sprite preview for that file's `<id>`.

## Preview

When clicking a link in format `https://k2s.cc/file/<id>/...`, activate the sprite preview in the browser with the `<id>` (see [1-browser.md](1-browser.md)).

## Hiding

- **Right click** on a link marks it as hidden: it is no longer shown in the tree or the recents list.
- Files with `.rar` extension are automatically hidden.

## Position Tracking

- Track the latest position reached in each video.
- Show the most advanced frame in the recents view.
- Display a percentage of the video seen on the button bar.
- When a video reaches **90% completion**, remove it from recents.
- Remove from recents after **24 hours** since last played.

## Tag Hover Preview

Hovering on a tag in the tree shows the closest sprite frame for that tag position:
- Display a clipped portion of the corresponding sprite image.
- Close the hover preview after 3 seconds in any case.
