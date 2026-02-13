# Video Players (Left Pane)

The left pane contains two video players stacked vertically.

## Player Layout

Each video player has, from top to bottom:

1. **Toolbar** — contains, left to right:
   - Icon flip flop % / :thumbup:
   - **Dropdown** — list of recent videos (initially empty), ordered by completion percentage if % (least complete first) then by rating, and by rating  then by completion if thumbs showing the percentage next to each title. Each entry shows a sprite screenshot thumbnail from the video's current position. Clicking the thumbnail plays the video; clicking the filename opens its preview.
   - **Radio button** — select this player as the active one
   - **Rating buttons** — small colored squares (1-5) to rate the current video; the active rating has a white border
   - **Tag icons** — emoji icons for each tag occurrence on the current video, sorted by timeline position
   - **Percentage** — watched percentage of the current video
   - **Lens** — open preview for the current video
   - **Next arrow** — go to the next video in recents (right-click: previous)
   - **Clock** — open the recents page (see [4-recents.md](4-recents.md))
   - **X** — remove current video from recents
2. **Video area** — the video itself
3. **Seek bar** — standard video navigation bar
4. **Tag bar** — shows tags as emoji icons at positions proportional to their location in the video

## Player Controls

- **Radio button**: select this player as the active one.
- **Lens icon**: open the preview for the current video in the browser.
- **Next arrow**: left click goes to the next video in recents; right click goes to the previous. Resumes at the latest saved position or the most advanced tag position.
- **Clock icon**: open the recents page in the browser.
- **X icon**: remove the current video from recents, then move to the next video.
- **Tag/rating icons**: click to set tags and ratings for the current video.

## Playing a Video at a Given URL and Frame

1. Load the video URL if not already playing.
2. If the video changed, wait until it is loaded before seeking.
3. Seek to the position: `frame * 10 seconds`.

## Error Handling

When a video playback error occurs within less than 1 second:
- First check connectivity. If the connection is bad, warn the user but do **not** remove the video from recents.
- If connectivity is good, the download URL is expired: remove the link from recents, warn the user, and move to the next video in the recents list (do not restart from the beginning).

## Focus and Ordering

- The recents dropdown is ordered by: completion percentage (least complete first).
- Show the priority as the background color of each entry.
- Selecting a video or preview from the player bar automatically makes that player the active one.

### Auto-Rating

- Tagging a previously unrated video or **blue** or **grey** gives it a **green** (Ok) priority.
- Playing a **blue** (Uhm) rated video promotes it to **green** (Ok).
- Rating a video as **Bad** (grey) hides it from the recents list and the tree. If currently playing, it is removed from recents and the next video plays automatically.

## Local Tagging

Right-clicking on the **tag bar** shows the tagging popup and adds the selected tag at the current playback position.

## Click Navigation

- **Single click** on the video: seek forward 2 seconds.
- **Double click** on the video: seek forward 10 seconds.
- **Right click** on the video: seek back 10 seconds.
- Clicking on a video automatically selects that player.
