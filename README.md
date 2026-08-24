# brb

When Claude works past a threshold, offer a break. When it finishes, call you back.

No AI, no polling, no terminal scraping — it hangs off Claude Code's own lifecycle
hooks. macOS only (it uses `osascript` for the UI).

## Install

```sh
git clone https://github.com/Sushanti99/brb.git
cd brb && ./install.sh
```

Then open a **new** Claude Code session — hooks load at session start.

Requires macOS and Claude Code. No other dependencies: it's plain bash plus the
`python3` and `osascript` that ship with the OS.

Registers three hooks in `~/.claude/settings.json` (backing it up first), copies a
default item list to `~/.claude/brb/items.txt`, and links `brb` into `~/.local/bin`.
Re-running is safe: it replaces its own entries and leaves other hooks alone.
`./uninstall.sh` removes them again.

Hooks load at session start, so open a new Claude session to pick them up.

## What fires, and when

Two independent things.

**The break panel** — a native list you pick from. Fires on one condition: a turn
passed the break timer (default 10s). It shows whether or not you're at the terminal,
because offering the break is its whole job.

**The alerts** — sound, banner, and a dialog with a *Back to work* button.

| Situation | Panel | Alert |
|---|---|---|
| Turn finishes faster than the timer | no | no |
| Long turn, panel shown, you ignored it | yes | no |
| Long turn, you clicked a note item | yes | no |
| Long turn, you clicked a site | yes | **done + Back to work** |
| Permission prompt, you're away | — | **"Claude needs you"** |
| Another Claude session still busy | stays up | your alert still fires |

Clicking a site is the whole condition — you're called back whether or not you
happen to be looking at the browser when the turn ends. Also requiring you to still
be away made it a coin flip: glance at the terminal for two seconds at the wrong
moment and the alert was silently dropped. Set `REQUIRE_AWAY=1` in `config.sh` for
the stricter behaviour.

The callback still requires you to have **actually left through the panel**. Seeing the panel
and dismissing it doesn't count, and neither does a `note:` item — those don't take you
anywhere, so there's nothing to call you back from.

A permission prompt is deliberately exempt from that rule: Claude is *blocked* on you,
so gating it would mean stalling in silence.

## Testing without a real turn

```sh
brb panel              # the real panel, right now
brb alert              # the real callback, right now
brb attention          # a "Claude needs you" ping
brb demo 20            # full flow: pick a site, then the callback 20s later
brb matrix             # every decision path, printed, NO UI drawn
```

`brb matrix` is the fast one — it runs each branch with `BRB_DRY=1` and prints what
each would have done, so you can check the logic without a single popup.

## Day to day

```sh
brb status             # config, live sessions, what's armed
brb log -f             # follow the decision log
brb timer 45s          # or set it from the panel's ⏱ row
brb items              # edit the panel list
brb off / brb on       # kill switch
brb doctor             # check the install
```

## How "away" is decided

The terminal that owns a session is found by walking the process tree
(`hook → claude → shell → Terminal.app`) and stored as a bundle id. That's a fact about
who owns the session, not a guess about what happened to be focused when the hook ran —
an earlier version used frontmost-app and would mis-record the terminal if you tabbed
away at the wrong instant.

Bundle ids are compared case-insensitively: System Events and LaunchServices disagree
on case for the same app.

## Adding your own places

Edit `~/.claude/brb/items.txt`, or pick **➕ Add your own…** at the bottom of the
panel — it opens [CONTRIBUTING.md](CONTRIBUTING.md), where the format is documented
and PRs against the default list are welcome.

Item icons are emoji or unicode glyphs. Color emoji render fine, but you can't
supply an image file, so real brand marks aren't available — and Unicode has no
X/Twitter glyph at all. A per-item logo would need a different UI surface.

## Configuration

- `~/.claude/brb/items.txt` — the panel list. `Label|target`, where target is a URL,
  an `app://` scheme, or `note:some text`.
- `~/.claude/brb/config.sh` — optional overrides (sounds, titles).
- `~/.claude/brb/state/` — runtime state and `brb.log`.

## Multiple monitors

AppleScript dialogs take no position and default to the **main** display — the one
with the menu bar — which is the wrong screen whenever you're working elsewhere.
`brb` positions every dialog on the **owning terminal's** window, so the panel, the
callback, and the terminal that "Back to work" raises all land on one screen.
Anchoring to the frontmost window instead proved unreliable during screen
recordings, where focus jumps between displays.

By default the browser is pulled onto that display too when you take a break, so
the whole flow stays on one monitor. Set `MOVE_BROWSER=0` in `config.sh` to leave
your windows where they are.

Notification *banners* can't be positioned at all — macOS always draws them on the
display holding the menu bar. Move the menu bar in System Settings → Displays if
they appear on the wrong screen.

That reposition needs Accessibility permission. Without it everything still works,
the dialogs just land on the main display. Grant it under System Settings →
Privacy & Security → Accessibility for your terminal app.

## Notes

Notification banners need permission for "Script Editor" under System Settings →
Notifications. A sound plays regardless, so you're never left with no signal.

Hooks are registered `async: true` and never block a turn. Their timeouts are generous
only because they cap how long the detached children — the break timer and the callback
dialog — are allowed to live.
