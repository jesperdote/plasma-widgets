# plasma-widgets

KDE Plasma 6 widgets I've built for my own desktop and am sharing in case they're useful to
anyone else. Each widget lives in its own folder with its own README and install steps.

| Widget | What it does |
|---|---|
| [Solana Watchlist](solana-watchlist/) | Market cap and 5m/1h/6h/24h price change for Solana tokens you pick, from DexScreener |
| [Solana Wallet](solana-wallet/) | Value of your Solana wallets on the panel; SOL and every token held in the popup |
| [NBA Scores](nba-scores/) | Live scores of the NBA games and teams you follow on the panel; every game of the day in the popup |

## Installing any widget

```bash
git clone https://github.com/jesperdote/plasma-widgets.git
kpackagetool6 -t Plasma/Applet -i plasma-widgets/<widget>/package
```

Then right-click the panel → **Add Widgets…** and search for it by name.

## Layout

```
<widget>/
├── package/        the Plasma package (metadata.json + contents/), what kpackagetool6 installs
├── screenshots/
└── README.md
```

Issues and pull requests are welcome.

## License

MIT, see [LICENSE](LICENSE).
