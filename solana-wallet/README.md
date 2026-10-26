# Solana Wallet

A KDE Plasma 6 panel widget showing the USD value of one or more Solana wallets, with the
24h change in green or red. Click it for everything the wallets hold.

- **On the panel:** total value of all your wallets and its 24h change.
- **Click it** for each wallet: its label, address and value, then its holdings (SOL first,
  then by value) with logo, symbol, name, amount, USD value, 24h change and a ✓ for
  Jupiter-verified tokens. Buttons copy the address, open it on Solscan, or remove it.
- **Add a wallet** by pasting its address (and an optional label) into the popup.
- **Hide balances under $1** (on by default) hides dust, NFTs and the worthless tokens that
  get airdropped to wallets as spam; SOL always shows.
- **Solid or transparent** background behind the panel text.
- **Hide values** with the eye button in the popup, or by middle-clicking the widget: dollar
  values and amounts become `$•••`, while symbols and 24h changes stay visible. Handy when
  sharing your screen.
- **Open in a window** with the button at the top of the popup: the same view as a normal
  window you can move, resize and keep open.

Read-only: it only looks up public balances by address. It never sees a private key and
can't sign or send anything.

## Where the data comes from

Both public, no key or account needed:

- **Balances:** a Solana RPC node (`getBalance` and `getTokenAccountsByOwner` for both
  token programs). Refreshed every 60 seconds.
- **Symbol, name, logo, price, 24h change, verified:** [Jupiter's token
  API](https://dev.jup.ag/docs/token-api), all tokens in one request. Refreshed every
  30 seconds.

The default RPC is Solana's public `https://api.mainnet-beta.solana.com`, which is
rate-limited. If you see "RPC error", put a free endpoint from Helius, QuickNode or similar
in `~/.config/sol-wallet/rpc` (just the URL), or set `$SOL_RPC_URL`.

- **Currency:** show values in USD or PHP (Philippine peso), converted with a daily USD rate from
  open.er-api.com (free, no key).
- **SOL price** and its 24h change in the popup's header, in the chosen currency.
- **Zoom** the data in the popup or window (Ctrl+wheel, Ctrl+=/−/0, or the header buttons).

## Requirements

- KDE Plasma 6
- Python 3 (standard library only)

## Install

```bash
git clone https://github.com/jesperdote/plasma-widgets.git
kpackagetool6 -t Plasma/Applet -i plasma-widgets/solana-wallet/package
```

Then right-click the panel → **Add Widgets…** → search for **Solana Wallet**.

## Wallet list

Wallets are kept in `~/.config/sol-wallet/wallets`, which you can also edit by hand:

```
# One Solana wallet address per line, optional label after it.
vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg Docs example
```

## Command line

```bash
python3 package/contents/code/sol-wallet           # one-line summary, e.g. "👛 $1,234 ▲2.1%"
python3 package/contents/code/sol-wallet --json    # everything the widget shows
python3 package/contents/code/sol-wallet --add ADDRESS [LABEL]   # also --remove ADDRESS
```

## Notes

- The 24h change is value-weighted: what today's holdings would have been worth 24 hours
  ago at those prices, not including tokens bought or sold since.
- Token names, symbols and logos come straight from Jupiter; scam tokens can copy a real
  token's name (a fake "SOL" is common), so check the ✓ and the value.

## License

MIT
