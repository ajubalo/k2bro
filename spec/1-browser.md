# Browser (Right Pane — Top)

The top of the right pane contains a browser with a navigation bar, the **filename** of the currently previewed link, **rating buttons** (colored 1-5) for the currently previewed link, a **Play** button, a **Download** button, and a **Pick** button. The browser supports both HTTP and HTTPS URLs.

### Download Button

Enabled when a k2s link is available (same conditions as Play). Clicking it executes the following command and shows it with the result in the browser log page:
```
echo '/mnt/data/deobro/get.sh <url>' | ssh -i <sandbox>/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null onyx.n7s.co at now
```

After clicking a rating button, the next random link is automatically picked (same rules as Pick button). Right-clicking a rating button rates the currently selected tree node (link or path) without picking a random next link.

### Pick Button

The Pick button selects a random link from the currently selected subtree in the tree and opens its preview. Priority order:
1. Unrated links (no rating set)
2. **Uhm** (blue/4) rated links
3. Any other rated link

## Sprite Preview

When previewing a file `<id>`:

1. Fetch sprite images from `https://static-cache.k2s.cc/sprite/<id>/00.jpeg`, then `01.jpeg`, `02.jpeg`, etc., until a request fails.
2. Display all fetched images stacked vertically in an HTML page inside the browser.
3. If no sprite images are found, show the actual page instead.

Each sprite image is a **5x5 grid** of frames. Generate JavaScript so that clicking on the image calculates the frame number from the image index and the click position within the grid.

### Preview Toolbar

A fixed toolbar at the top of the preview page shows:

- **Filename** of the currently previewed video.
- **Rating dots** (colored 1–5) — clicking a dot rates the video.
- **Speed buttons** (1/s, 2/s, 4/s, 8/s) — start a sequential preview, showing frames centered at 80% width/height at the selected rate.
- **Scrubber** (horizontal slider) — manually navigate frames back and forth. Also works on the current frame in the overlay without zooming.
- **Stop button** — stops the sequential preview and closes the overlay.
- **Frame info** — displays current frame number and timestamp.

The toolbar is fixed at the top so it remains visible while scrolling the sprite grid.

## Playing a Video

When the user clicks on a frame:

1. Check connectivity to the K2S API before attempting to resolve. If the connection fails, show an error and abort.
2. Resolve the download URL using the token (see [9-util.py](9-util.py) — `getUrl` API). Do not perform the captcha challenge; if the token is missing, ask the user to generate it via `uv run util.py login`.
3. Play the video at the selected frame position.
4. Add the video to the recents list.

## Video Navigation from Preview

- If the currently playing video matches the preview, clicking a frame seeks to that position.
- Clicking the **lens** icon reopens the preview for the current video.
- Use the **dropdown** on top of each video player to switch videos; the player restores the last saved position.

## Saving Videos

When a video is added or changed, save to the recents list:
- The download URL
- The current position
- The title (the portion after `file/<id>/` in the k2s URL)

## Tagging

Clicking on a frame shows a popup near the mouse with tag and rating icons.

### Tag Icons

| Code | Emoji |
|------|-------|
| blo  | :kiss: |
| dog  | :dog: |
| fro  | :grinning: |
| bak  | :peach: |
| ass  | :dart: |
| cum  | :sweat_drops: |

### Rating Icons (round, colored)

| Rating | Color  |
|--------|--------|
| 1 Super | Red    |
| 2 Top   | Yellow |
| 3 Ok    | Green  |
| 4 Uhm   | Blue   |
| 5 Bad   | Grey   |

### Tagging Behavior

- **Left click** on a frame: show the tagging popup and navigate to that frame.
- **Right click** on a frame: show the tagging popup without navigating. If the video is not already in recents, resolve the download URL and add it to recents (without playing).
- Clicking a **tag icon** saves a tag at the current frame position. The tag appears on the tag bar at a position proportional to its location in the video. Clicking the tag on the bar seeks to that position.
- Clicking a **rating icon** assigns a rating to the video. The rating color appears as a background in the links list. Links are ordered by rating (rated first, then by rating value).
- **Right click** on a tag in the bar removes it.
- Tags and ratings are persisted in `data.json` (see [5-format.md](5-format.md)).

### Tag Indicators on Preview

When displaying the sprite preview, show existing tag emoji icons overlaid on the sprite grid at the corresponding frame positions. Each tag emoji is positioned in the top-left corner of its frame cell, with a dark text shadow for visibility against the sprite images.

### Popup Dismissal

The tagging popup disappears after:
- 3 seconds of inactivity, or
- Clicking on another frame, or
- Making a tag/rating selection.

### Double Click on Preview

Double-clicking a frame in the preview:
1. Adds a `blo` tag at that frame.
2. Opens the video in the player.
3. Waits for the video to load, then seeks to the tagged frame.
