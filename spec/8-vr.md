# DeoVR Endpoint

The web server (port 9999) serves a DeoVR-compatible JSON API at `/deovr`.

## Index — `GET /deovr`

Returns the DeoVR scene list format with all recent in random order:

```json
{
  "authorized": "1",
  "scenes": [
    {
      "name": "Recents",
      "list": [
        {
          "title": "video title",
          "videoLength": 600,
          "thumbnailUrl": "https://static-cache.k2s.cc/sprite/<id>/00.jpeg",
          "video_url": "http://<host>/deovr/<index>"
        }
      ]
    }
  ]
}
```

Videos are listed in **random order**, with VR-tagged videos first, then non-VR videos. Both groups are independently shuffled. Bad-rated and expired entries are excluded. The order is cached for 60 seconds so that index and video detail endpoints stay consistent.

## Video Detail — `GET /deovr/<index>`

Returns the full DeoVR video object for the video at the given index:

- `screenType`: `"flat"` (or `"dome"` for VR videos)
- `stereoMode`: `"off"` (or `"sbs"` for VR videos)
- `is3d`: `false` (or `true` for VR videos)
- `encodings`: single source with the resolved download URL
- `timeStamps`: tag positions as chapters, with emoji + timestamp labels
- `thumbnailUrl`: first sprite image from K2S CDN

## VR Icon

Each video player toolbar has a VR icon (`vrpano`). Clicking it toggles the VR flag for the current video (stored as `vr: true` in `data.json`). When active, the icon has a green background.

- **Video display**: VR videos show only the left half (left eye) of the side-by-side 180° content, cropped and scaled to fill the player.
- **DeoVR endpoint**: VR videos return `is3d: true`, `screenType: "dome"`, `stereoMode: "sbs"`.
- **Tree view**: VR-tagged links show a sunglasses icon (🕶️) prefix before the filename.
- **Sprite preview**: For VR links, sprite images display only the left half stretched to full width (showing left-eye content). Frame click calculations and tag overlay positions are adjusted accordingly.

## VR Button (Tree)

The tree button bar has a **VR** button (`vrpano` icon). Clicking it toggles the VR flag on all links under the selected node (link, path, group, or domain). If any link is not VR, all are set to VR; otherwise all are cleared.

## VR Tree Categories

The tree has six top-level categories. The original three (Fresh, Tagged, Search) show only **non-VR** links. Three VR counterparts show only **VR-flagged** links:

| Category | Icon | Contents |
|---|---|---|
| Fresh | `fiber_new` | Untagged, non-VR links |
| Fresh VR | `vrpano` | Untagged, VR-flagged links |
| Tagged | `label` | Tagged, non-VR links (sub-grouped by rating) |
| Tagged VR | `vrpano` | Tagged, VR-flagged links (sub-grouped by rating) |
| Search | `search` | Search results, non-VR links only |
| Search VR | `vrpano` | Search results, VR-flagged links only |

VR categories are only shown when they contain at least one link. Tagged VR has the same rating sub-grouping as Tagged (Super, Top, Ok, Uhm, unrated).

## File Size

During the extraction and dedup phases, file size is fetched from the K2S `getFilesInfo` API and stored as `file_size` (bytes) per link in `data.json`.

When available, size is displayed as a prefix before the filename:
- `xM` if less than 1 GB (e.g. `150M`)
- `x.xG` if 1 GB or more (e.g. `1.2G`)

Shown in both the tree view and the browser source page preview.

## Recents as DeoVR Menu

The recents page served at `http://localhost:9999/` doubles as a DeoVR-compatible menu:

- Clicking a video title navigates to `/deovr/<index>` (the DeoVR video detail JSON), so DeoVR can open it directly.
- Each card has a **remove button** (×) that calls `POST /remove/<index>` to remove the video from recents and refreshes the page.

### `/deovr` Link

A link to `/deovr` is shown at the top of the recents page, providing quick access to the DeoVR JSON index (random order).

### Rating Buttons

Each card shows 5 colored rating dots (red, yellow, green, blue, grey) in the title bar. The active rating has a white border. Clicking a dot calls `POST /rate/<index>/<rating>` and refreshes the page.

### VR Toggle

Each card shows a **VR** button in the title bar. When the video is marked as VR, the button has a green background. Clicking it calls `POST /vr/<index>` to toggle the VR flag and refreshes the page.

### Server Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/remove/<index>` | Remove video from recents |
| `POST` | `/rate/<index>/<rating>` | Set rating (1–5) for video |
| `POST` | `/vr/<index>` | Toggle VR flag for video |

## Tree Browser

The recents page (web server mode) includes a tree browser bar at the top for browsing "fresh" (unrated, untagged) links:

1. **Site dropdown** — lists all domains that have fresh links. Selecting one loads the paths dropdown.
2. **Collection dropdown** — lists paths of the first level under the selected domain (do not show grouped paths) Selecting one loads a random preview.
3. **Preview area** — shows the link title, file size, and first sprite image (`sprite/<id>/00.jpeg`).
4. **Buttons**:
   - **Add** — resolves the download URL and adds the previewed link to recents (probes sprites for `totalFrames`).
   - **Next** — picks another random fresh link from the same collection.
   - **End** — resets both dropdowns and hides the preview.

### Tree API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/tree/domains` | List fresh domains (JSON array) |
| `GET` | `/tree/paths/<domain>` | List fresh paths for domain (JSON array) |
| `GET` | `/tree/preview/<domain>/<path>` | Random fresh link preview (JSON: link, title, previewImage, fileSize, totalFresh) |
| `POST` | `/tree/add/...?link=<url>` | Resolve download URL, add to recents |


