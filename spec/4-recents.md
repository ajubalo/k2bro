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
