# Gevun

A music player for your Navidrome library on iPhone and iPad.

## Screenshots

<p align="center">
  <a href="docs/screenshots/albums.webp"><img src="docs/screenshots/albums.webp" width="220" alt="Albums library with cover artwork"></a>
  <a href="docs/screenshots/album.webp"><img src="docs/screenshots/album.webp" width="220" alt="Album details and track list"></a>
  <a href="docs/screenshots/player.webp"><img src="docs/screenshots/player.webp" width="220" alt="Music player with colors drawn from the album artwork"></a>
  <a href="docs/screenshots/artist.webp"><img src="docs/screenshots/artist.webp" width="220" alt="Artist biography and albums"></a>
  <a href="docs/screenshots/songs.webp"><img src="docs/screenshots/songs.webp" width="220" alt="Songs library and mini player"></a>
</p>

## Features

- Browse albums, artists, and songs, or search your library.
- Listen in original quality with background playback and lock-screen controls.
- Follow synced lyrics and tap a line to jump to it.
- Download songs and albums for offline listening, in original quality or a smaller supported format.
- Export downloaded songs to Files or share them with other apps.
- Add songs to your queue, play next, and repeat tracks or albums.
- Automatically save your queue and restore it paused, with offline recovery and Navidrome sync.
- Share listening links for songs and albums when enabled on your server.
- Read artist biographies and discover similar artists.
- Switch between multiple Navidrome servers.
- A dark interface with colors drawn from your album artwork.

## Install

Requires **iOS 27 or later** and a Navidrome server.

Download **Gevun.ipa** from a [release with an IPA attached](https://github.com/DjangoCustard225/Gevun/releases). The IPA is unsigned; sign it with your sideloading tool before installing.

Open Gevun and sign in with your server address, username, and password. You can add more servers in Settings.

Music streams from your server in its original format. Download songs or albums from their menus, then use the Downloaded filter to listen offline. Converted downloads depend on your server's transcoders and native format support on your device.

Export saved songs from their menus, or export everything from Settings → Downloads. FLAC, AAC, and MP3 exports include available song details, cover artwork, and lyrics without encoding the audio again. FLAC and MP3 keep their existing tags. AAC uses M4A; MP3 and FLAC can also include timed lyrics.

Manage automatic queue sync or manually transfer a queue from Settings → Listening queue.

## Privacy

No ads or analytics. Passwords stay in Keychain. Listening history sharing is optional and off by default.

Licensed under the [MIT License](LICENSE).
