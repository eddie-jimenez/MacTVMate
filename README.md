# MacTVMate
<img width="200" height="200" alt="MacTVMate icon" src="docs/icon.png" />

**Purpose**  
A native macOS IPTV player with a TV-style guide, built with SwiftUI and [libmpv](https://mpv.io).  
Bring your own playlist (Xtream Codes or M3U + XMLTV) and MacTVMate turns it into a rich, fast, keyboard- and remote-friendly TV experience on the Mac — live scores for games, IMDb ratings for movies and shows, recording, and an iPhone remote.

**Created by:** Eddie Jimenez  
**Created on:** 2026-10-19  
**Version:** 1.0.0

[![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white)](#-requirements)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

> ⚠️ MacTVMate does **not** provide, host or link to any channels or content. You need your own legal IPTV subscription or playlist.  
> It is an independent project and is not affiliated with or endorsed by TiviMate or any IPTV provider.

---

## 🧭 Overview

Most IPTV providers ship thin or broken guide data, so typical players show "No information" for half the channel list. MacTVMate fixes that by merging your provider's EPG with free public guides, recognising event channels from their names, and enriching what's on:

- 🏈 **Sports** get live scores, team logos, records, clock, down & distance, venue and network
- 🎬 **Movies** get IMDb ratings, runtime, genres, posters and cast
- 📺 **Shows** get IMDb ratings, season/episode numbers and artwork

---

## ✨ Features

**Live TV**
- TV-guide layout: sidebar, channel groups, programme details and a live preview above a scrolling grid
- Hover the preview for mini-player controls (pause, channel up/down, volume, tracks, record, full screen)
- Plays nearly anything via libmpv (MPEG-TS, HLS, AC-3…) with hardware decoding, tuned buffering, automatic retries and stall recovery
- Channel up/down, number entry, last channel, favourites, recently watched
- Hide channel groups (adult groups hidden by default)
- Search (⌘F or /) across channels and the guide
- **TV mode:** drag the window onto a TV and the whole interface scales up to a readable-from-the-couch size automatically; fine-tune it in Settings ▸ Appearance ▸ Interface size

**A richer guide**
- Merges your provider's EPG with **EPGtalk** (Gracenote data) and **epg.iptv.cat** by default — add or remove sources in Settings ▸ EPG
- Matches channels by guide id or name, with English-first language detection
- Event channels (e.g. `NFL 01: Team A @ Team B | 8:15 PM`) become real listings
- Posters, year, season/episode, cast, content ratings and "New" flags

**Movies & Shows (Xtream VOD)**
- Poster grid with categories, IMDb ratings and sorting (recently added, A–Z, IMDb rating, popular)
- Details, trailers, resume, next episode, continue watching, My list
- Draggable scrub bar, ←/→ 30 s, trackpad swipe 10 s

**Recording & reminders**
- Record what you're watching (**R**), or schedule from the guide with 2/5-minute padding
- Saved as `.ts` in `~/Movies/MacTVMate`
- Reminders pop up before a programme starts

**Control it your way**
- Keyboard, media keys, AirPods and Control Center (Now Playing)
- NVIDIA Shield and other Bluetooth remotes — Back / Home / Menu included
- **iPhone / iPad remote:** scan the QR code in Settings ▸ Remote & keyboard for a D-pad, channel and volume rockers, *On now*, and search with your phone keyboard

---

## 🚀 Installation

### Option 1 — One-line installer (recommended)
Paste in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/eddie-jimenez/MacTVMate/main/install.sh | bash
```

The installer:
1. Checks your macOS version
2. Installs **Homebrew** and **mpv** if needed (asks first)
3. Downloads the latest release (Apple silicon) or builds from source (Intel)
4. Installs to `/Applications` and opens MacTVMate

Run the same command again any time to update.

### Option 2 — Download from Releases
1. `brew install mpv`
2. Download the latest `MacTVMate-x.y.z-arm64.zip` from [Releases](https://github.com/eddie-jimenez/MacTVMate/releases)
3. Unzip, move **MacTVMate.app** to Applications, then **right-click ▸ Open** the first time (the app is ad-hoc signed, not notarized)

### Option 3 — Build from source
```bash
brew install mpv
git clone https://github.com/eddie-jimenez/MacTVMate.git
cd MacTVMate
./build-app.sh            # release build → build/MacTVMate.app
open build/MacTVMate.app
```
`./build-app.sh debug` builds a debug bundle; `./build-app.sh --zip` also packs a release zip.

---

## 🛠 Setup & Usage
1. Open **Settings ▸ Playlists ▸ Add playlist**
   - **Xtream Codes:** server URL, username, password
   - **M3U:** playlist URL or file, plus an optional XMLTV guide URL
2. The guide loads and fills in from the extra guide sources within a few seconds
3. Optional: **Settings ▸ Remote & keyboard** — scan the QR code with your iPhone, then *Share ▸ Add to Home Screen*

**Keyboard**

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

---

## 📋 Requirements
- macOS **14 (Sonoma)** or later
- Apple silicon for the prebuilt release (Intel builds from source)
- [Homebrew](https://brew.sh) with `mpv` (provides libmpv and FFmpeg)
- Xcode or the Command Line Tools — only when building from source
- Your own IPTV subscription / playlist

---

## 🔒 Security Notes
- Playlists, settings and caches live in `~/Library/Application Support/MacTVMate/`, readable by your user only
- Nothing is sent anywhere except your provider and the metadata sources listed below
- The iPhone remote only answers devices on your local network that open the private link / QR code; generate a new link in Settings to revoke old devices
- No analytics, no telemetry

---

## 📡 Metadata Sources

| Source | Used for | Notes |
|---|---|---|
| Your provider | Channels, EPG, movies & shows | |
| [EPGtalk](https://github.com/acidjesuz/EPGtalk) | Guide data (Gracenote) | Free public XMLTV |
| [epg.iptv.cat](https://epg.iptv.cat) | Guide data | Free public XMLTV |
| [IMDb datasets](https://developer.imdb.com/non-commercial-datasets/) | Ratings, genres, runtime | Personal and non-commercial use only |
| [TVmaze](https://www.tvmaze.com/api) | Show artwork and info | Free API, CC BY-SA |
| ESPN scoreboard | Live scores | Unofficial public endpoint; may change without notice |

Please respect each source's terms of use.

---

## ⚠️ Known Limitations
- Release builds are **ad-hoc signed, not notarized** — use the installer, or right-click ▸ Open the first time
- The prebuilt release is **Apple silicon only**; Intel Macs build from source (the installer does this automatically)
- Requires Homebrew's `mpv`; the app links it from Homebrew rather than bundling it
- Scheduled recordings only run while MacTVMate is open, and use a second connection to your provider
- Guide coverage depends on your provider's channel names; event and streaming placeholder channels often have no guide data
- Live scores use an unofficial ESPN endpoint and may stop working if it changes

---

## 🧪 Troubleshooting
- **"MacTVMate can't be opened"** — right-click the app ▸ Open, or run `xattr -dr com.apple.quarantine /Applications/MacTVMate.app`
- **App quits immediately / "libmpv not found"** — run `brew install mpv` (or `brew reinstall mpv`)
- **No guide for some channels** — check Settings ▸ EPG; each source shows ✓ or ⚠ with the reason
- **iPhone remote won't load** — make sure the iPhone is on the same Wi-Fi, allow incoming connections if macOS asks, and try the IP link shown in Settings
- **Text too small or too large on a TV** — Settings ▸ Appearance ▸ Interface size: *Auto* detects TVs by size and name, or pick 100–250%
- **Shield remote buttons do nothing** — pair it in System Settings ▸ Bluetooth (hold Back + Home), then use the button tester in Settings ▸ Remote & keyboard

---

## 🗑 Uninstall
Quit MacTVMate, then:

```bash
rm -rf /Applications/MacTVMate.app ~/Library/Application\ Support/MacTVMate
```

Recordings stay in `~/Movies/MacTVMate`.

---

## 📜 Modification History
- **v1.0.0** — Initial release: live TV guide with merged EPG sources, sports scores and IMDb enrichment, movies & shows, recording and reminders, Shield and iPhone remotes, one-line installer

---

## 🙏 Thanks & Inspiration

MacTVMate is inspired by the TV-guide-first experience of **TiviMate** on Android TV — it is an independent, from-scratch macOS app and is not affiliated with TiviMate.

Built on the shoulders of:

✅ **[mpv / libmpv](https://mpv.io)** and **[FFmpeg](https://ffmpeg.org)** for playback  
✅ **[EPGtalk](https://github.com/acidjesuz/EPGtalk)** and **[epg.iptv.cat](https://epg.iptv.cat)** for free guide data  
✅ **[IMDb](https://developer.imdb.com/non-commercial-datasets/)** and **[TVmaze](https://www.tvmaze.com)** for metadata  

---

## 🧾 License

This project is licensed under the **MIT License**.  
See the [LICENSE](./LICENSE) file for details. libmpv and FFmpeg are licensed separately (LGPL/GPL).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

---

## 👤 Author

**Eddie Jimenez**  
[![GitHub](https://img.shields.io/badge/GitHub-eddie--jimenez-black?logo=github&logoColor=white)](https://github.com/eddie-jimenez)  
[![LinkedIn](https://img.shields.io/badge/LinkedIn-eddie_p_jimenez-blue?logo=linkedin&logoColor=white)](https://www.linkedin.com/in/eddie-p-jimenez/)

## 💬 Contact
- Mac Admins Slack: [**@Eddie J**](https://macadmins.slack.com/team/U06SP52GZSM) *(requires Mac Admins Slack membership)*
- For bugs/requests: open a GitHub issue in this repo

---

<p align="center">
  <strong>⭐ If this project helps you, please give it a star! ⭐</strong>
</p>
