# Data Format

## data.json

Hierarchical structure: domain > path > URL > info.

```json
{
  "<domain>": {
    "<path>": {
      "<url>": {
        "rating": 3,
        "hidden": false,
        "tags": [
          { "code": "blo", "frame": 42 }
        ]
      }
    }
  }
}
```

### Fields

- **`<domain>`** — the website domain (e.g. `www.example.com`)
- **`<path>`** — the page path on that domain
- **`<url>`** — the full `https://k2s.cc/file/<id>/...` URL
- **`rating`** — integer 1-5 (1=Super/red, 2=Top/yellow, 3=Ok/green, 4=Uhm/blue, 5=Bad/grey)
- **`hidden`** — boolean, whether the link is hidden from the tree and recents
- **`tags`** — array of `{ "code": "<tag_code>", "frame": <frame_number> }`

## recent.json

Array of recently played videos.

```json
[
  {
    "k2sUrl": "https://k2s.cc/file/<id>/...",
    "downloadUrl": "https://...",
    "title": "filename",
    "position": 120.5,
    "maxPosition": 300.0,
    "totalFrames": 50,
    "lastPlayed": "2025-01-15T10:30:00Z",
    "createdAt": "2025-01-15T09:00:00Z"
  }
]
```

### Fields

- **`k2sUrl`** — the original k2s.cc file URL
- **`downloadUrl`** — the resolved download URL
- **`title`** — the filename portion after `file/<id>/`
- **`position`** — current playback position in seconds
- **`maxPosition`** — furthest position reached in seconds
- **`totalFrames`** — number of sprite preview frames
- **`lastPlayed`** — ISO 8601 timestamp of last playback
- **`createdAt`** — ISO 8601 timestamp of when first added
