# NBA Scores

A KDE Plasma 6 panel widget for live NBA scores.

- **On the panel:** the current score of the games you follow, e.g. `🏀 IND 88–72 BKN · Q3 5:45`
  (up to two; before tip-off the start time in your time zone, afterwards `Final`). With nothing
  followed it shows how many games are live.
- **Follow a game** three ways: star it (☆) in the popup's list of today's games, follow a whole
  **team** by typing its abbreviation (`LAL`, `GSW`, `BOS`…), or paste an **ESPN game link**
  (`https://www.espn.com/nba/game/_/gameId/401909862`) for any other game. Finished games drop off
  about a day and a half after tip-off; followed teams stay.
- **Click it** for every game of the day (live first, then upcoming in your time, then final), and
  for each followed game: win-probability bar, each team's points/rebounds/assists leaders and the
  last plays. Each game opens on ESPN.
- Zoom (Ctrl+wheel), a movable window, and a solid or transparent panel background, like the other
  widgets in this repo.

Refreshes every 15 seconds while a game is live and every 2 minutes otherwise.

## Data

ESPN's public scoreboard and game-summary feeds (`site.api.espn.com`): no key or account. They're
unofficial, so they could change; the official NBA feed refuses requests from outside its own site.
What you follow is kept in `~/.config/nba-scores/follow.json`.

## Requirements

- KDE Plasma 6
- Python 3 (standard library only)

## Install

```bash
git clone https://github.com/jesperdote/plasma-widgets.git
kpackagetool6 -t Plasma/Applet -i plasma-widgets/nba-scores/package
```

Then right-click the panel → **Add Widgets…** → search for **NBA Scores**.

## Command line

```bash
python3 package/contents/code/nba-scores              # one line, as on the panel
python3 package/contents/code/nba-scores --json       # everything the widget shows
python3 package/contents/code/nba-scores --follow LAL # or an ESPN game link / id; --unfollow too
```

## License

MIT
