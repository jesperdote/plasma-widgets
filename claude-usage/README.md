# Claude Usage

A KDE Plasma 6 panel widget for your Claude subscription usage.

- **On the panel:** the Claude logo with two stacked rows, `5h` (current session) and `7d`
  (weekly), as percentages. Amber from 50 %, red from 80 %.
- **Hover** for the summary: both percentages, when each resets, and how old the data is.
- **Right-click → Open usage page** opens claude.ai's usage settings in your browser. A left
  click does nothing.

Refreshes every minute.

## Data

The widget doesn't fetch anything itself. Every minute it runs `~/bin/claude-usage --json` and
shows what that prints. **That helper isn't part of this repo**, so you have to provide it.
Without it the widget shows `–`. It has to print JSON like this:

```json
{
  "ok": true,
  "session": { "pct": 42.0, "resetsAt": "2026-10-30T17:00:00Z" },
  "weekly":  { "pct": 18.5, "resetsAt": "2026-11-03T09:00:00Z" },
  "ageMin": 3
}
```

With `"ok": false`, the tooltip says the data is unavailable. `ageMin` is shown in the tooltip once
it's over 10 minutes.

## Requirements

- KDE Plasma 6
- an executable `~/bin/claude-usage` as described above

## Install

```bash
git clone https://github.com/jesperdote/plasma-widgets.git
kpackagetool6 -t Plasma/Applet -i plasma-widgets/claude-usage/package
```

Then right-click the panel → **Add Widgets…** → search for **Claude Usage**.

## License

MIT
