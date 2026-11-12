# Mini Deck setup guide

Mini Deck opens an interactive **Setup & Help** window on first launch. Reopen it from the menu bar at any time; it remembers your place, detects playback and account connection, and provides buttons for each action below.

## The easiest route

You do not need a Spotify developer app for playback controls or imported full-history totals. Live Spotify rankings and recent API plays are optional.

1. Install Mini Deck, open Spotify or Music, and play a song.
2. Allow macOS Automation access if you want Mini Deck to read and control that app.
3. For full Spotify history, request **Extended streaming history** in Spotify's [privacy account page](https://www.spotify.com/account/privacy/).
4. Download the export when Spotify makes it available, then unzip it.
5. In **Setup & Help > Full account history**, choose the extracted history files or enable an auto-import folder.

Spotify describes Extended Streaming History as account-lifetime data. The regular Account Data package only contains the past year's streaming history, so request the correct package ([Spotify data guide](https://support.spotify.com/us/article/understanding-your-data/)).

## What runs automatically

- **Playback:** Mini Deck follows the running music app and current track.
- **Setup checks:** The guide reports detected apps, active playback, connection state, import totals, and selected auto-import folder.
- **Saved account access:** An existing Spotify connection is reused and refreshed without pasting the Client ID again.
- **Live account stats:** Recent plays are refreshed while Mini Deck runs; top lists refresh on their own interval. These are account data, never combined with Mac-only counts.
- **Optional auto-import:** After you explicitly select an export folder, Mini Deck checks that folder every 30 seconds. Recognized JSON files must remain stable across two checks before import. Repeated and overlapping exports are deduplicated.
- **Privacy filtering:** Raw IP addresses, locations, platforms and usernames are discarded during import. No history files are uploaded.

Mini Deck does not silently create Spotify developer apps, accept terms, authorize OAuth access, request private exports, approve macOS security prompts, or access arbitrary download folders. Those actions require the owner's involvement. A shared Spotify registration is supported by the app, but this download does not invent or provision one.

## Full history import

While waiting for your export, mark **I've requested my full history** in **Setup & Help > Full account history**. The card then shows **Full history requested** and **Import when ready**. This reminder is stored on this Mac, is off by default, and can be unchecked at any time. It does not monitor Spotify or estimate delivery.

If Spotify is connected, select an approximate 4-week, 6-month or 12-month ranking period in **Your Spotify**. Artist and song positions are Spotify affinity rankings, not play counts. **Last recent play** means the latest returned timestamp for the current song, not a complete account-history search. A missing result does not mean you have never played it. The API supplies rankings and a limited recent list ([top items](https://developer.spotify.com/documentation/web-api/reference/get-users-top-artists-and-tracks), [recently played](https://developer.spotify.com/documentation/web-api/reference/get-recently-played)).

Use **Listening Stats > Import Full Spotify History…**, or the interactive guide's **Choose history files…** button.

- **Select all relevant audio files:** `Streaming_History_Audio*.json` or older `endsong*.json` extended-history files. A containing folder can also be selected.
- **Unzip first:** ZIP archives are not imported directly.
- **Check coverage:** Mini Deck shows the earliest and latest imported timestamps. Missing files mean partial history; it cannot prove that you selected the complete account export.
- **Understand totals:** Plays require at least 30 seconds. Actual listened time includes shorter listens. Podcasts/video records are not included in music totals.
- **Refresh later:** Import a newer export to extend historical totals. Live recent API plays stay separate because the API lacks actual listened milliseconds and does not provide a lifetime event archive.
- **Batch large exports:** Limit each file to 64 MB and each import batch to 256 MB. Import multiple batches when necessary.

Imported totals appear in the compact card, with additional details under **Show advanced**. The **Spotify import** tab in Listening History shows recent records and top songs/artists/albums; list displays are capped at 100 rows, but totals use all imported records.

### Saved Wrapped song lists

Use **Listening Stats > Import Wrapped Playlist Snapshot…** with a Mini Deck Wrapped-playlist JSON snapshot, then open **Listening History > Wrapped** and choose a saved year. This is separate from the full streaming-history importer and does not accept raw Spotify `Wrapped.json` files or screenshots. The app displays playlist order, not inferred play counts, artist ranks, listening minutes or fan percentages.

Imported playlists stay private on this Mac. They are not automatically associated with a newly connected Spotify account or uploaded, and no user's playlist data is bundled in public releases. Use **Remove Saved Wrapped Snapshot…** to remove Mini Deck's copy without changing Spotify or your original file.

### Automatic import folder

Choose **Setup & Help > Full account history > Choose auto-import folder…** and select a dedicated folder. Put extracted audio-history JSON files in that folder; Mini Deck imports new or changed files automatically while running and restores the selection on later launches.

The watcher does not request the export, retrieve email attachments, unzip downloads, or keep collecting history while the app is closed. If folder access expires or its bookmark becomes stale, choose the folder again. Use **Stop automatic imports** to disable it; removing imported history also disables its watcher so it is not immediately reimported.

## Optional live Spotify connection

If your build includes a distributor-configured registration, the guide offers **Connect Spotify** immediately. You still sign in and approve access in Spotify's own browser page.

Otherwise use the four interactive manual steps in **Setup & Help > Live Spotify (optional)**:

1. Open the [Developer Dashboard](https://developer.spotify.com/dashboard) and choose **Create app**. Use `Mini Deck` as the name and `Personal music statistics` as the description. Review and accept Spotify's terms yourself.
2. Add `http://127.0.0.1:8974/callback` as the Redirect URI, click **Add**, select **Web API**, and save. The guide has a **Copy redirect URI** button.
3. Open that app's settings and copy the **Client ID**, not the Client Secret. If using someone else's development registration, its owner must allowlist your Spotify account in User Management.
4. Click **Paste** in Mini Deck and then **Connect Spotify**. Complete Spotify's browser approval. The guide detects successful connection automatically.

The guide validates the Client ID format but cannot prove that it belongs to an eligible registration until Spotify accepts the connection. Mini Deck only reads the clipboard when you explicitly click Paste or use a normal paste shortcut.

Spotify documents developer-app registration through the dashboard ([app registration](https://developer.spotify.com/documentation/web-api/concepts/apps)). HTTP is permitted for an explicit loopback address such as `127.0.0.1`; do not substitute `localhost` ([redirect requirements](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri)).

### Why public one-click sign-in is not enabled by default

Development-mode registrations require a Premium app owner and support only five allowlisted users. Wider distribution requires Spotify's extended-quota approval, which has separate eligibility requirements ([quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes)).

For an appropriately approved distributor registration, set the GitHub Actions repository variable `MINIDECK_SPOTIFY_CLIENT_ID` before building a release. The build validates it and embeds that public identifier in the app, enabling one-click OAuth. A local build can use the environment variable of the same name. Never supply a Client Secret, token, or password. No shared registration has been configured automatically, and setting a Client ID does not remove Spotify's quota or allowlist restrictions.

## Troubleshooting

- **macOS cannot verify the developer:** Mini Deck is ad-hoc signed, not Apple-notarized. If you trust the release, Apple's documented path is to try opening it, then use **System Settings > Privacy & Security > Open Anyway**. A warning is not evidence that an app is safe; do not disable Gatekeeper globally ([Apple guidance](https://support.apple.com/en-us/102445)).
- **Playback is missing:** Play a track in the desktop music app, select **Follow > Automatic**, and review Mini Deck's Automation access in macOS Privacy & Security.
- **Spotify returns 403:** Verify the account is allowlisted for that developer registration and check the app owner's Premium status. Signing in alone does not guarantee API access ([Spotify quota rules](https://developer.spotify.com/documentation/web-api/concepts/quota-modes)).
- **Redirect mismatch:** Copy the exact URI from the guide, add it to Spotify's settings, and save before reconnecting.
- **No lifetime totals after connection:** The live API provides top items and recent tracks, not lifetime play totals. Import Extended Streaming History ([top items](https://developer.spotify.com/documentation/web-api/reference/get-users-top-artists-and-tracks), [recent plays](https://developer.spotify.com/documentation/web-api/reference/get-recently-played)).
- **Monthly listeners appears as a link:** Spotify's public page did not provide verifiable listener metadata. The link opens Spotify; no number is guessed. Neither Spotify's Web API nor Apple Music's public artist attributes expose monthly listeners ([Spotify](https://developer.spotify.com/documentation/web-api/reference/get-an-artist), [Apple](https://developer.apple.com/documentation/applemusicapi/artists/attributes)).
- **Import fails:** Check that files are extracted, are the extended audio-history JSON files, and fit the batch limits. The importer reports skipped non-music/invalid rows and never supplements missing records with guessed API data.
- **Apple Music history differs:** The displayed history comes from the Music library, not a guarantee of complete cloud-account lifetime history.

## Remove data or stop setup

Use **Use Mini Deck now** or close the setup window to skip optional steps. Your playback controls remain usable.

The **Listening Stats** menu contains controls to disconnect Spotify, stop automatic imports, remove the sanitized Spotify import, or clear Mac-only tracking separately. The original export files and the Spotify account are not modified by removing an import.
