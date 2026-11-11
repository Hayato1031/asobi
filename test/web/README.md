# Player manual test

Open `test/web/fixture.html` directly in a browser (`file://` works; no server needed).

It mounts `lib/asobi/web/player.js` full-window and plays a hand-written 60-frame, 30 fps Reel
(a rotating ring of circles). Three buttons at the bottom left drive the checks.

What to look for:

- Idle: only the picture, centred, filling the window. No controls visible.
- Move the mouse: "record" and "code" appear top-right and fade after about 2.5 s. The picture does not move.
- Press `c` (or click "code"): a semi-transparent code overlay appears; press again to hide it.
- "swap reel": the ring changes (6 -> 3 circles) but the rotation continues from the same moment (no jump back to frame 0).
- "send error": a red panel appears at the bottom; the previous picture keeps animating behind it.
  Line breaks in the message are preserved.
- "clear error": the panel disappears.
- Press `r` (or click "record"): a red dot shows top-left. Press `r` again: `asobi.mp4` or `asobi.webm` downloads.
  Check that it plays and shows the animation on the background colour.

Query strings for forcing states (used for headless screenshots):
`?code=1`, `?error=1`, `?swap=1`, `?dark=1`, `?notools=1`.

Headless example:

    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
      --window-size=800,600 --virtual-time-budget=3000 --screenshot=out.png \
      "file://$PWD/test/web/fixture.html?error=1&notools=1"
