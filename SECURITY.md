# Security and privacy

## Reporting a problem

Please report security problems privately: open this repository's **Security** tab and click **Report a vulnerability**. Don't post security details in public.

## How Mini Deck handles data

- **No server.** Mini Deck has no backend. It talks only to the services listed below.
- **No secrets in the code.** The repository holds no keys, tokens or Client IDs. You enter your own Spotify Client ID in the app.
- **Spotify sign-in.** Uses Authorization Code with PKCE, so no client secret exists. A random `state` value is checked on return. The sign-in listener binds to `127.0.0.1` only and closes after one reply or 5 minutes.
- **Token storage.** The Spotify refresh token is stored in the macOS login keychain (this device only). The short-lived access token stays in memory. Disconnecting deletes the keychain item.
- **Read-only access.** The only Spotify scopes requested are `user-top-read` and `user-read-recently-played`. Mini Deck can't change your account.
- **Music library history.** Song names, artists, albums, play counts and last-played dates are read from the Music app on this Mac and kept in memory only. They are never saved or sent anywhere.
- **Play counts on this Mac.** Song, artist and album names with play counts and times, stored in `~/Library/Application Support/Mini Deck/listening.json`. The folder is `0700` and the file is `0600`, so only your user can read them. Turn counting off or clear it from the menu bar.
- **Imported Spotify history.** Only explicitly selected files/folders are read. Parsing/indexing happens off the UI thread, with file/batch size limits. Only music titles, artist/album names, Spotify track URIs, timestamps and listened milliseconds are retained in `~/Library/Application Support/Mini Deck/spotify-import.json` (`0600`). IP addresses, usernames, locations, platforms and private-session flags are discarded. No import contents are uploaded. Removal deletes only the sanitized copy, never the user's original files.
- **Ongoing Spotify history.** `spotify-live.json` (`0600`, private app-support folder) stores observed playback sessions and available recent account records, session IDs, timing/position, and last sync time. It contains no credentials, IP addresses, locations, or raw export files and is never uploaded. Derived totals reconcile this journal with the import without modifying the import. Clear Ongoing Spotify Records removes the journal separately; disconnecting stops account polling, and disabling Mac play counting pauses local collection. Recording resumes when enabled.
- **Public artist audience.** Artist IDs may be resolved through the signed-in Spotify API. Monthly-listener metadata is fetched separately from `https://open.spotify.com/artist/…` using an ephemeral session with no account tokens or existing browser cookies. Counts are cached only in memory, with timestamps and expiry. Missing counts remain unavailable; no private endpoints or third-party audience services are used.
- **Optional automatic imports.** Only an explicitly selected export folder is monitored. A security-scoped folder bookmark is saved in app preferences; stale access requires selecting the folder again. Symlinks and unrelated filenames are skipped. Stop Automatic Imports removes the saved bookmark. Removing the imported archive also stops the watcher.
- **Setup guide.** The guide never accepts third-party terms, changes macOS permissions, or provisions developer registrations silently. Clipboard contents are read only on explicit paste. A distributor may configure a public Client ID at build time; no Client Secret belongs in the app, source, build variable, or guide, and a configured ID does not bypass Spotify access limits.
- **Sound bars.** Read the music app's audio level in memory. No audio is recorded or saved.
- **Album and artist details.** Lookups send only the artist, album and song names to Apple's iTunes Search, MusicBrainz, Wikidata and Wikipedia, over HTTPS.
