# Security and privacy

## Reporting a problem

Please report security problems privately: open this repository's **Security** tab and click **Report a vulnerability**. Don't post security details in public.

## How Mini Deck handles data

- **No server.** Mini Deck has no backend. It talks only to the services listed below.
- **No secrets in the code.** The repository holds no keys, tokens or Client IDs. You enter your own Spotify Client ID in the app.
- **Spotify sign-in.** Uses Authorization Code with PKCE, so no client secret exists. A random `state` value is checked on return. The sign-in listener binds to `127.0.0.1` only and closes after one reply or 5 minutes.
- **Token storage.** The Spotify refresh token is stored in the macOS login keychain (this device only). The short-lived access token stays in memory. Disconnecting deletes the keychain item.
- **Read-only access.** The only Spotify scopes requested are `user-top-read` and `user-read-recently-played`. Mini Deck can't change your account.
- **Play counts on this Mac.** Stored in `~/Library/Application Support/Mini Deck/listening.json`. The folder is `0700` and the file is `0600`, so only your user can read them. Turn counting off or clear it from the menu bar.
- **Sound bars.** Read the music app's audio level in memory. No audio is recorded or saved.
- **Album and artist details.** Lookups send only the artist, album and song names to Apple's iTunes Search, MusicBrainz, Wikidata and Wikipedia, over HTTPS.
