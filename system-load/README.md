# CPU & RAM

A small KDE Plasma 6 panel widget for CPU and RAM usage.

- **On the panel:** a CPU icon over a RAM icon, each with its usage percentage (CPU is the
  average of all cores). Amber from 70 %, red from 90 %. The numbers have a fixed width, so the
  panel doesn't shift as they change.
- **Hover** for CPU %, RAM % and RAM used of total.
- **Click** to open System Monitor.

## Data

Uses the same sensors as KDE's own System Monitor widgets (`ksystemstats`): `cpu/all/usage`
and `memory/physical/*`. Nothing leaves your machine.

## Requirements

- KDE Plasma 6 with `ksystemstats` (installed with Plasma)
- `plasma-systemmonitor` for the click

## Install

```bash
git clone https://github.com/jesperdote/plasma-widgets.git
kpackagetool6 -t Plasma/Applet -i plasma-widgets/system-load/package
```

Then right-click the panel → **Add Widgets…** → search for **CPU & RAM**.

## License

MIT
