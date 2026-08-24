# Contributing to brb

The panel list is meant to be personal. If you've added somewhere you go on a
break and think others would use it too, send it over.

## Adding a place to the default list

1. Fork this repo and clone your fork.
2. Edit [`share/items.txt`](share/items.txt) — one line per item:

   ```
   Label|target
   ```

   | target | what happens |
   |---|---|
   | `https://…` | opens in the default browser, **counts as leaving** |
   | `someapp://…` | opens in that app, **counts as leaving** |
   | `note:some text` | shows a short reminder, does *not* count as leaving |

   "Counts as leaving" matters: `brb` only calls you back when the panel actually
   sent you somewhere. A `note:` item doesn't take you anywhere, so there's
   nothing to return from.

3. Test it without touching your real config:

   ```sh
   BRB_CONF=/tmp/brb-test ./brb panel
   ```

   That runs the real panel against a throwaway config directory.

4. Open a PR describing what you added and why.

## What tends to get merged

Places a lot of people already go, or genuinely useful nudges. The default list
should stay short — it's a starting point people edit, not a directory. If your
addition is niche, it probably belongs in your own
`~/.claude/brb/items.txt` rather than the defaults, and that's fine.

## Changing behaviour

Run the decision matrix before and after any change to the alert rules:

```sh
./brb matrix
```

It exercises every branch with no UI drawn and prints what each would do. If a row
changes, say so in the PR — those rules are the whole product, and they've each
been argued for:

- The callback fires only if the panel sent you somewhere, so dismissing the panel
  earns silence.
- `idle_prompt` follows that same rule, because it fires at the same moment as
  `Stop` and would otherwise double-alert.
- `permission_prompt` deliberately does **not**, because Claude is blocked on you
  and staying quiet would mean stalling.

## Style

Plain bash, no dependencies beyond what macOS ships. Every script must pass
`bash -n`. Keep comments for the things that are surprising — why `setsid` is
avoided, why bundle ids are compared case-insensitively — not for what the code
plainly says.
