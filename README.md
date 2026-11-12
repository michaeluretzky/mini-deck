# Mini Deck

Mini Deck is a floating music controller for macOS. It works with Spotify and Apple Music.

**[Download the latest version](https://github.com/michaeluretzky/mini-deck/releases/latest)**: free for personal use. Runs on Apple silicon and Intel Macs with macOS 14 or later.

## Download and install

1. Open the [latest release](https://github.com/michaeluretzky/mini-deck/releases/latest) and download `Mini-Deck-<version>.zip`.
2. Double-click the zip, then drag **Mini Deck** into your **Applications** folder.
3. Open Mini Deck. macOS blocks it the first time because it isn't from the App Store. Click **Done**.
4. Go to **System Settings > Privacy & Security**, scroll down, and click **Open Anyway** next to Mini Deck. Confirm with your password.
5. Mini Deck appears in the menu bar and as a floating card. Allow access to Spotify or Music when asked.

If you're comfortable with Terminal, this also clears the block:

```sh
xattr -dr com.apple.quarantine "/Applications/Mini Deck.app"
```

To check the download, compare `shasum -a 256 Mini-Deck-<version>.zip` with the `.sha256` file on the release page.

To update, quit Mini Deck, replace the app in Applications, and open it again. macOS may ask for permissions again.

## Getting started

- **Apple Music:** nothing to set up. Play something in the Music app.
- **Spotify:** controls work right away with the Spotify desktop app. Your Spotify account stats are optional and need a one-time setup (see [Connect Spotify](#connect-spotify)).
- Choose which app to follow from menu bar > Follow.

## Features

- Play, pause, skip, shuffle, repeat and seek from a small card that floats over your windows.
- Scroll over the card to change the volume.
- The card's colors come from the album cover.
- Rest the pointer on the cover to see:
  1. **About this song & album:** short summaries, release year, song count, length, genre.
  2. **About the artist or band:** origin, years active or born, genres, short bio.
  3. **Your listening:** your own stats for the song and artist (see below).
- Follows whichever app is playing, or one app you choose (menu bar > Follow).

## Your listening stats

| Source | What you see | Setup |
| --- | --- | --- |
| Spotify account | Top-artist and top-song rank (4 weeks, 6 months, 12 months), plays in your last 50 | Connect once (below) |
| Apple Music library | Song play count, last played, favorite, date added, artist plays, artist rank, songs in library | None |
| This Mac | Plays and listening time Mini Deck counted for the song and artist | None. Can be turned off |

### Connect Spotify

Spotify requires each user to bring their own developer app. This takes about two minutes:

1. Sign in to the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and create an app (any name and description).
2. Under **Redirect URIs**, add `http://127.0.0.1:8974/callback`.
3. Under **APIs used**, select **Web API**, then save.
4. Copy the **Client ID**.
5. In Mini Deck, choose menu bar > Listening Stats > Connect Spotify Account, paste the Client ID, and sign in.

Spotify's rules for developer apps: the app owner needs Spotify Premium, and sign-ins expire after 6 months. Mini Deck asks you to reconnect when that happens.

## Build from source

Needs macOS 14 or later and Apple's Command Line Tools (`xcode-select --install`). Xcode isn't needed.

```sh
git clone https://github.com/michaeluretzky/mini-deck.git
cd mini-deck
zsh make-app.zsh
open ~/Applications/"Mini Deck.app"
```

Run the script again after any code change. Because the app is signed only for this Mac, macOS may ask for permissions again after a rebuild. `zsh make-release.zsh` builds the same universal zip that's on the Releases page.

## Permissions

- **Automation (Spotify, Music):** to read the current track and send commands.
- **Screen & System Audio Recording:** only for the sound bars. Without it, the bars use a placeholder animation.

See [SECURITY.md](SECURITY.md) for how data is handled.

## License

Free for personal, non-commercial use. You may download, build and use Mini Deck on your own Macs. You may not redistribute, sell or publish it or changed versions; please link to this page instead. See [LICENSE](LICENSE) for the full terms.

---

Spotify is a trademark of Spotify AB. Apple Music is a trademark of Apple Inc. Mini Deck isn't affiliated with or endorsed by either company.
