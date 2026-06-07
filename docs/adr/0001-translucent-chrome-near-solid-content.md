# Translucent chrome, near-solid content

The panel floats over arbitrary wallpapers and is where users read streamed
responses, so legibility can't depend on what's behind the window. We use genuine
translucent materials only on **chrome** (header, input bar, status pill, chips)
and keep **content** (message bubbles, transcript) near-solid. This deliberately
diverges from a fully translucent "soft & tactile" look — a future reader will
wonder why bubbles aren't translucent like the rest of the panel; the answer is
readable text over any background.

See `CONTEXT.md` for the chrome/content vocabulary and
`tasks/ui-polish-plan.md` for the surrounding refinement work.
