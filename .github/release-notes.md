A floating music controller for macOS that works with Spotify and Apple Music.

Version 1.4.7 fixes the player going off the side of the screen after a double-click size switch. A double-click could also start a tiny drag; the size switch then rebuilt the card before that drag ended, so edge correction stopped. Size switches now finish any unfinished drag, and every resize stays inside the screen even mid-drag.

Version 1.4.6 fixes screen-edge alignment. The complete glow stays inside the usable display with a 10-point outer margin at parked edges. Normal and compact sizes preserve the selected side or center anchor even away from an exact snap point. Drawer expansion no longer replaces the saved resting position, and display/Dock changes preserve edge distances. Saved placement now includes the resting size, display and anchor.

Version 1.4.5 removes the extra “total songs/artists/albums” words beside play counts. Summary and advanced cards show only a smaller `/ N`, while retaining the large play count, card heading, and “overall plays” caption.

Ongoing Spotify history now begins on first launch. Mini Deck privately saves observed Spotify playback and available recent account records, polls at startup and about every two minutes, attempts bounded catch-up, and reconciles local/API duplicates. The combined song, artist, album, and history totals include forward records after the imported export cutoff. A newer export takes precedence through its cutoff. Closed/offline gaps and missing export files can still leave incomplete coverage; this is not a claim of guaranteed full synchronization ([Spotify recent history API](https://developer.spotify.com/documentation/web-api/reference/get-recently-played)).

All valid music records now count as **overall plays**, including short listens, with no minimum-duration threshold. Listening time uses only known measured duration; API-only records do not invent it. The private ongoing journal survives restarts and has a separate clear control. Existing imports are not modified by this change.

Compact mode is a mini version of the normal player: left-aligned song, artist and album rows with their icons and the same five playback controls. Shared components use tighter spacing, while text stays readable at 12.5-point title, 10.5-point artist and 10-point album sizes. Both layouts put a full-width seekable playback strip at the bottom of the player, with time labels beside the bar to save height. The small service icon remains at the top-right; hover details stay limited to song and artist.

Repeated Spotify IDs with identical title, artist and album metadata now share one displayed song row with summed plays. Original records and IDs remain intact; explicitly different live/remix/version labels remain separate. This applies to song details, artist/album lists, unique-song counts and combined history.

The outer glow now uses a rounded falloff that reaches transparent pixels before the window edge, removing the rectangular blur cutoff.

Song, artist and album play tiles retain their large play count and add a smaller `/ N` suffix. The respective values are unique saved-history song, artist and album collection sizes, not play-count denominators; both summary and advanced tiles use the same caption-size styling.

Version 1.4.4 displays song/album release dates as **September 2, 2020**. Spotify dates and Apple/MusicBrainz album-note fallbacks share the same format. Dates with only month or year precision remain **September 2020** or **2020**, without invented dates or timezone shifts. Artist birth and formation years are unchanged. Existing private listening data is preserved.

The Spotify or Apple Music service icon now sits at the top-right of the player in a compact 22-point badge. It remains clickable, without a visible “Open…” caption. Removing the old attribution footer reduces the card's bottom space while preserving the track/control spacing.

Double-click the player to toggle a smaller 300-point-wide compact view, then double-click again to restore the normal 448-point player. Compact mode keeps basic playback controls and a cover-hover panel limited to brief song and artist details. The mode is remembered and is also available through the **Compact View** menu option. Listening statistics remain in normal view and Listening History.

Monitor positioning now uses the current display's visible bounds and pixel scale, preserves right/center alignment through width changes, restores the resting position after hover expansion, and selects the nearest remaining display when a saved position is offscreen. Automatic repositioning is immediate rather than animated. Imported song lookups, artist ranks and top-100 lists are indexed once off the UI thread instead of repeatedly scanning the full history while rendering.

Expanded details are height-limited to the current monitor and scroll only when needed, keeping the player controls visible on smaller screens. Scrolling over details scrolls the panel rather than adjusting playback volume.

Drawer responsiveness: reduces the intentional cover-hover delay from 280 to 90 milliseconds, removes competing content/window resize animations, coalesces size updates, and avoids full-card hover invalidations for every mouse movement. A short exit grace period prevents transient resize events from immediately collapsing the drawer. These are implementation changes, not a measured end-to-end latency guarantee.

**Integrated history:** song details show known historical years, including when a song is absent from current API results. **Listening History > Spotify > History** combines recent account records, imported streaming history and historical song records, deduplicating exact song IDs. Year-only data never becomes play counts, listening minutes, synthetic playback dates or rankings. Public downloads contain no personal data; existing Mini Deck historical-song snapshots remain compatible.

The compact **Your Spotify** section now shows Spotify artist/song rankings for one selected period and **Last recent play**, limited to returned recent history. **Show advanced** retains detailed lists. Live occurrence counts and synthetic album rankings have been removed; live API data is not presented as lifetime totals, actual listened minutes or first-ever listens. Spotify rankings describe affinity, not measured play counts ([Spotify top items](https://developer.spotify.com/documentation/web-api/reference/get-users-top-artists-and-tracks)).

A user-controlled **Full history requested** reminder provides **Import when ready**, without a guessed countdown. It is off by default and is not a Spotify processing-status check. Existing private imports, Apple Music library statistics and saved connections remain supported. Album release metadata and track count use Spotify when returned, with existing album-note fallbacks. Spotify attribution and an Open Spotify control are included.

First launch now includes an interactive Setup & Help guide with automatic playback/account checks, a developer-free full-history route, four-step optional live Spotify setup, copy/paste helpers, and troubleshooting. An opt-in export-folder watcher imports stable extracted JSON files automatically. [Read the setup guide](https://github.com/michaeluretzky/mini-deck/blob/main/SETUP.md).

Monthly listeners appear beside the artist heading only when Spotify's public page supplies verifiable metadata; otherwise the heading links to Spotify. Apple Music's public artist API does not provide that count. No followers or popularity scores are substituted.

For historical totals, request **Extended streaming history** in Spotify's Download your data tool, unzip the export, then choose **Listening Stats > Import Full Spotify History…**. Import all relevant music-history files. Totals combine the selected files with saved forward records after the export cutoff; the date range is shown. [Spotify explains the export coverage here](https://support.spotify.com/us/article/understanding-your-data/).

**Download:** `Mini-Deck-<version>.zip` below. It runs on Apple silicon and Intel Macs with macOS 14 or later.

**First open:** This release is ad-hoc signed, not Apple-notarized, so macOS may block its first launch. If you trust the release, try opening it, then go to System Settings > Privacy & Security and click **Open Anyway**. Full steps are in the [README](https://github.com/michaeluretzky/mini-deck#download-and-install).

Free for personal use. See [LICENSE](https://github.com/michaeluretzky/mini-deck/blob/main/LICENSE).
