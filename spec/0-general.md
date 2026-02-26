# General Layout

The application is a custom browser with two video players.

## Window

On startup, the window occupies 90% of the screen, leaving a band on the right.

## Panes

The window is split **vertically** into two panes:

- **Left pane** — two video players (see [2-video.md](2-video.md))
- **Right pane** — split horizontally:
  - **Top** — browser with navigation bar (see [1-browser.md](1-browser.md))
  - **Bottom** — file tree (see [3-tree.md](3-tree.md))

## Separators

Both the vertical separator (left/right) and the horizontal separator (top/bottom in the right pane) can be dragged to resize.


## Server Mode Layout

When the web server is active (see [8-vr.md](8-vr.md)), the layout changes:

- **Left pane** — file tree with 2× font size (no video players)
- **Right pane** — browser/preview only (no tree, no horizontal split)

The layout reverts to normal when the server is stopped.

## Home page

A home button (house icon) in the browser navigation bar, after the refresh button. Clicking it navigates to `https://k2s.cc`.
