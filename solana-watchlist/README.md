# Solana Watchlist

A KDE Plasma 6 panel widget that tracks the market cap of Solana tokens you choose, with
colour-coded price change over 5 minutes, 1 hour, 6 hours and 24 hours.

![Solana Watchlist on the panel](screenshots/panel.png)

- **On the panel:** symbol, market cap and the price change for each time frame, each in its
  own colour. Up to 3 tokens are shown, then `+N`.
- **Click it** for the full list. Each token shows its name, market cap, price, all four
  changes and its address, with buttons to hide it from the panel, open it on DexScreener,
  copy the address, or remove it.
- **Add a token** by pasting its address into the popup. It is checked against DexScreener
  before it's added.
- **Choose the time frames** shown on the panel with the checkboxes at the top of the popup.
- **Refreshes every 5 seconds.** All tokens are fetched in one request, well inside
  DexScreener's limit of 300 requests a minute.

Market data comes from the public [DexScreener API](https://docs.dexscreener.com/): for
each token, the trading pair with the most liquidity. No API key or account is needed.

## Requirements

- KDE Plasma 6
- Python 3 (standard library only)

## Install

```bash
git clone https://github.com/jesperdote/plasma-widgets.git
kpackagetool6 -t Plasma/Applet -i plasma-widgets/solana-watchlist/package
```

Then right-click the panel → **Add Widgets…** → search for **Solana Watchlist**.

To update after a `git pull`:

```bash
kpackagetool6 -t Plasma/Applet -u plasma-widgets/solana-watchlist/package
```

For development, symlink the package instead, then restart Plasma to pick up changes
(`systemctl --user restart plasma-plasmashell.service`):

```bash
ln -s "$PWD/plasma-widgets/solana-watchlist/package" \
  ~/.local/share/plasma/plasmoids/com.github.jesperdote.solanawatchlist
```

## Watchlist file

Tokens are kept in `~/.config/sol-mc/watchlist`, which you can also edit by hand:

```
# One Solana token address per line, optional label after it.
DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263 BONK
-EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm WIF
```

A leading `-` hides that token from the panel; it stays in the popup.

## Command line

The widget's backend also works on its own:

```bash
python3 package/contents/code/sol-mc             # one-line summary
python3 package/contents/code/sol-mc --tooltip   # one line per token
python3 package/contents/code/sol-mc --json      # what the widget reads
python3 package/contents/code/sol-mc --add ADDRESS   # also --remove, --hide, --show
```

## Notes

- If you use [Panel Colorizer](https://github.com/luisbocanegra/plasma-panel-colorizer), its
  foreground colour would normally override the time-frame colours; the widget puts them back.
- Token names come straight from DexScreener, so some meme tokens show odd symbols.
- Not financial advice; prices can lag or be missing for tokens with little trading.

## License

MIT
