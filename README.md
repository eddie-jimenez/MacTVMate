<p align="center"><img src="docs/icon.png" width="128" alt="MacTVMate icon"></p>

# MacTVMate

A native macOS IPTV player with a TV-style guide, built with SwiftUI and [libmpv](https://mpv.io).
Bring your own playlist (Xtream Codes or M3U + XMLTV) — MacTVMate turns it into a rich, fast, keyboard- and remote-friendly TV experience on the Mac.

> MacTVMate does not provide, host or link to any channels or content. You need your own legal IPTV subscription or playlist.
> It is an independent project and is not affiliated with or endorsed by TiviMate or any IPTV provider.

## Features

**Live TV**
- TV-guide layout: sidebar, channel groups, programme details and a live preview above a scrolling grid.
- Plays nearly anything via libmpv (MPEG-TS, HLS, AC-3…), hardware decoding, tuned buffering, automatic retries and stall recovery.
- Channel up/down, number entry, last channel, favourites, recently watched, hide groups (adult groups hidden by default).
- Search (⌘F or /) across channels and the guide.

**A richer guide**
- Merges your provider's EPG with free public guides (EPGtalk/Gracenote and epg.iptv.cat by default — editable in Settings ▸ EPG), matched by guide id or channel name with English-first language detection.
- Posters, year, season/episode, cast, content ratings and "new" flags.
- Event channels (e.g. "NFL 01: Team A @ Team B | 8:15 PM") become real listings.
- Sports get **live scores**, team logos, records, clock, down & distance, venue and network.
- Movies and shows on live TV get **IMDb ratings**, and shows get artwork from TVmaze.

**Movies & Shows (Xtream VOD)**
- Poster grid with categories, IMDb ratings, sorting by recently added / A–Z / IMDb rating / popularity.
- Details, trailers, resume, next episode, continue watching, My list.

**Recording & reminders**
- Record what you're watching (R), or schedule from the guide with 2/5-minute padding; saved as `.ts` in `~/Movies/MacTVMate`.
- Reminders pop up before a programme starts.

**Control it your way**
- Keyboard, media keys, AirPods and Control Center (Now Playing).
- NVIDIA Shield (and other Bluetooth) remotes — Back/Home/Menu included.
- **iPhone/iPad remote:** scan the QR code in Settings ▸ Remote & keyboard for a D-pad, channel/volume rockers, "On now" and search with your phone keyboard.

## Requirements

- macOS 14 or later (Apple silicon or Intel)
- Xcode (for the Swift toolchain)
- [Homebrew](https://brew.sh): `brew install mpv` (provides libmpv and FFmpeg)

## Build & run

```bash
brew install mpv
./build-app.sh          # release build → build/MacTVMate.app
open build/MacTVMate.app
```

`./build-app.sh debug` builds a debug bundle. The script uses `/Applications/Xcode.app` without changing `xcode-select`.
The app links Homebrew's libmpv, so it runs on Macs with `mpv` installed via Homebrew.

Then add your playlist in **Settings ▸ Playlists** (Xtream Codes login, or an M3U URL/file with an optional XMLTV URL).

## Keyboard

| Key | Action |
|---|---|
| ↑ / ↓ | Channel up/down (player) · move (guide) |
| ← / → | Channel list / info (live) · seek 30 s (movies, catch-up) · move (guide) |
| Return | Channel list (player) · play / catch-up (guide) |
| 0–9 | Jump to channel number |
| Backspace / L | Previous channel |
| F · ⌘↩ | Full screen (player) · favourite (guide/list) · full screen anywhere |
| / · ⌘F | Search |
| R | Record current stream |
| Space · M | Pause · mute |
| Esc | Back |

## Data & privacy

- Settings, playlists and caches live in `~/Library/Application Support/MacTVMate/` (readable by your user only).
- The iPhone remote only answers devices on your local network that open the private link/QR code.
- MacTVMate talks only to your provider and to the metadata sources below.

## Metadata sources

| Source | Used for | Notes |
|---|---|---|
| Your provider | Channels, EPG, VOD | |
| [EPGtalk](https://github.com/acidjesuz/EPGtalk) | Guide data (Gracenote) | Free public XMLTV |
| [epg.iptv.cat](https://epg.iptv.cat) | Guide data | Free public XMLTV |
| [IMDb datasets](https://developer.imdb.com/non-commercial-datasets/) | Ratings, genres, runtime | Personal and non-commercial use only, per IMDb's terms |
| [TVmaze](https://www.tvmaze.com/api) | Show artwork and info | Free API, CC BY-SA |
| ESPN scoreboard | Live scores | Unofficial public endpoint; may change without notice |

Respect each source's terms of use.

## Development

Sources are in `Sources/MacTVMate` (Core = data, playback and services; Views = SwiftUI).
`MACTVMATE_SNAPSHOTS=/tmp/shots build/MacTVMate.app/Contents/MacOS/MacTVMate` walks the main screens and saves PNGs for quick visual checks.

## License

[MIT](LICENSE) © 2026 Eddie Jimenez. libmpv and FFmpeg are licensed separately (LGPL/GPL).
