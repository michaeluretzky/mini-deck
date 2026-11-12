A floating music controller for macOS that works with Spotify and Apple Music.

Version 1.4.1 separates song, artist and album into three icon-led rows, with more space before the controls and playback bar.

Drawer responsiveness: reduces the intentional cover-hover delay from 280 to 90 milliseconds, removes competing content/window resize animations, coalesces size updates, and avoids full-card hover invalidations for every mouse movement. A short exit grace period prevents transient resize events from immediately collapsing the drawer. These are implementation changes, not a measured end-to-end latency guarantee.

**Saved Wrapped playlists:** a private snapshot importer and year selector in Listening History. Playlist positions are labeled as positions, not inferred play counts or listening minutes, and stay separate from live rankings and full-history totals. The card links to saved years and shows exact song matches. Public downloads contain no personal playlist data; this importer accepts Mini Deck's snapshot format, not raw Spotify Wrapped summary files.

The compact **Your Spotify** section now shows Spotify artist/song rankings for one selected period and **Last recent play**, limited to returned recent history. **Show advanced** retains detailed lists. Live occurrence counts and synthetic album rankings have been removed; live API data is not presented as lifetime totals, actual listened minutes or first-ever listens. Spotify rankings describe affinity, not measured play counts ([Spotify top items](https://developer.spotify.com/documentation/web-api/reference/get-users-top-artists-and-tracks)).

A user-controlled **Full history requested** reminder provides **Import when ready**, without a guessed countdown. It is off by default and is not a Spotify processing-status check. Existing private imports, Apple Music library statistics and saved connections remain supported. Album release metadata and track count use Spotify when returned, with existing album-note fallbacks. Spotify attribution and an Open Spotify control are included.

First launch now includes an interactive Setup & Help guide with automatic playback/account checks, a developer-free full-history route, four-step optional live Spotify setup, copy/paste helpers, and troubleshooting. An opt-in export-folder watcher imports stable extracted JSON files automatically. [Read the setup guide](https://github.com/michaeluretzky/mini-deck/blob/main/SETUP.md).

Monthly listeners appear beside the artist heading only when Spotify's public page supplies verifiable metadata; otherwise the heading links to Spotify. Apple Music's public artist API does not provide that count. No followers or popularity scores are substituted.

For historical totals, request **Extended streaming history** in Spotify's Download your data tool, unzip the export, then choose **Listening Stats > Import Full Spotify History…**. Import all relevant audio JSON files. Totals cover the selected files, not later API plays; the date range is shown. [Spotify explains the export coverage here](https://support.spotify.com/us/article/understanding-your-data/).

**Download:** `Mini-Deck-<version>.zip` below. It runs on Apple silicon and Intel Macs with macOS 14 or later.

**First open:** This release is ad-hoc signed, not Apple-notarized, so macOS may block its first launch. If you trust the release, try opening it, then go to System Settings > Privacy & Security and click **Open Anyway**. Full steps are in the [README](https://github.com/michaeluretzky/mini-deck#download-and-install).

Free for personal use. See [LICENSE](https://github.com/michaeluretzky/mini-deck/blob/main/LICENSE).
