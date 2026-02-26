# Recents Page

A toolbar button in the tree opens the recents page, which renders an HTML page in the browser showing recent videos ordered by rating.

## Video Entries

For each video, show:

1. **Title** — with the rating color as background, and a progress bar behind it showing the percentage of completion.
2. **Frame strip** — a horizontal strip of the closest sprite frames to each tagged position:
   - The tag emoji is shown in the top-left corner of each frame.
   - The current position frame has a **red border**.
3. Clicking on a frame in the strip plays the video at that frame's position.

## Latest Position

- When opening a video, wait for it to load, then seek to the latest saved position.
- For a new video, the latest position is the position where the user clicked on the preview.


## Web Server Mode

The recents button supports right-click to toggle a built-in HTTP web server:

- **Right-click** the recents button to start an HTTP server on **port 9999** that serves the recents page to an external browser.
- When the server is active, the recents button shows an **active/highlighted state** (green background).
- **Right-click again** to stop the server and restore the button to its normal state.
- The served page is self-contained with an embedded `<video>` player inside each video card:
  - The player is hidden by default and appears when the user clicks a video title or frame strip entry.
  - Clicking a frame strip entry also seeks the player to that frame's position.
  - The player shows standard HTML5 video controls (play, pause, seek, volume).
- In the embedded WebView (left click), the recents page uses the Flutter media_kit player instead — clicking a title or frame plays through the app's built-in player.

