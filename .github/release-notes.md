A floating music controller for macOS that works with Spotify and Apple Music.

Version 1.4.0 separates account-wide Spotify stats from Mac-only tracking and adds a private Extended Streaming History importer for song, artist and album totals across devices. Repeated imports are deduplicated. The compact summary and Show advanced option remain.

First launch now includes an interactive Setup & Help guide with automatic playback/account checks, a developer-free full-history route, four-step optional live Spotify setup, copy/paste helpers, and troubleshooting. An opt-in export-folder watcher imports stable extracted JSON files automatically. [Read the setup guide](https://github.com/michaeluretzky/mini-deck/blob/main/SETUP.md).

Monthly listeners appear beside the artist heading only when Spotify's public page supplies verifiable metadata; otherwise the heading links to Spotify. Apple Music's public artist API does not provide that count. No followers or popularity scores are substituted.

For historical totals, request **Extended streaming history** in Spotify's Download your data tool, unzip the export, then choose **Listening Stats > Import Full Spotify History…**. Import all relevant audio JSON files. Totals cover the selected files, not later API plays; the date range is shown. [Spotify explains the export coverage here](https://support.spotify.com/us/article/understanding-your-data/).

**Download:** `Mini-Deck-<version>.zip` below. It runs on Apple silicon and Intel Macs with macOS 14 or later.

**First open:** macOS blocks apps from outside the App Store the first time. Open the app once, then go to System Settings > Privacy & Security and click **Open Anyway**. Full steps are in the [README](https://github.com/michaeluretzky/mini-deck#download-and-install).

Free for personal use. See [LICENSE](https://github.com/michaeluretzky/mini-deck/blob/main/LICENSE).
