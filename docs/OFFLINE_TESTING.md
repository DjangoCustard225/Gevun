# Offline playback checks

Run the core tests and release build before testing on an iOS 27 device. The native format picker probes generated local audio; codecs that fail native decoding remain unavailable.

For a disposable Navidrome integration check, install ffmpeg and ffprobe, then run:

```sh
python3 Scripts/TestDownloadServer.py /path/to/navidrome
```

This creates its own temporary library, generated audio, random credentials, and loopback server. It checks exact original bytes, Opus/MP3/AAC output codecs and duration, original streaming, disabled downloads, and an unavailable transcoder. It never reads saved Gevun servers.

On a device:

- Download an album in each available format. Test the lowest and highest bitrates. Confirm progress, cancellation, retry, and Wi-Fi-only behavior.
- Enable airplane mode, close and reopen Gevun, and use the Downloaded filters. Play songs, navigate a partially downloaded album, and check cached artwork and lyrics.
- Seek forward and backward repeatedly, tap synced lyrics, skip tracks, repeat, and use lock-screen controls. Check the timeline against audible playback.
- Lock the device during transfers. Reopen after background completion and verify the saved library. After explicitly force-quitting, reopen the app to recover pending transfers.
- Interrupt the network during a download, reconnect, and retry. Change the Wi-Fi-only setting during a transfer. Queue a large album and confirm only two transfers run concurrently.
- Replace a saved song with another format. Cancel or fail the replacement and confirm the old copy still plays. Complete it and confirm there is only one saved copy.
- Fill storage during a transfer. Free space, retry storage if needed, and retry the song. Confirm no incomplete file is marked downloaded.
- Switch between servers with overlapping song IDs. Change a password during a transfer, then change a server address or username. Check isolation and cancellation of obsolete requests.
- Remove a song, all downloads, and an instance. Confirm saved files disappear appropriately and a late transfer callback does not restore them.
- Export existing and newly downloaded AAC songs. Confirm the output is M4A with title, track artist, album artist, album, track/disc numbers, and available year, genre, artwork, and plain-text lyrics. Repeat offline after artwork and lyrics have cached. The saved AAC file must remain unchanged.
- Export multiple AAC songs with matching names, cancel sharing, and retry. Confirm unique filenames, complete playback, and no changes to the offline library. Original formats other than FLAC must remain byte-identical to their saved files.
- Export converted MP3 downloads with and without existing ID3v2.3/v2.4 tags. Check that existing tags, custom fields, and artwork remain intact and missing title, artist, album artist, album, year, genre, track/disc numbers, artwork, and lyrics are added. Verify timed lyrics in a player that supports ID3 SYLT, including songs with a lyric offset. The saved file and MPEG audio bytes must remain unchanged.
- Export FLAC downloads with existing tags, custom comments, ReplayGain, artwork, and application blocks. Existing values and metadata blocks must survive. Missing fields and lyrics can be added to the exported copy; timed lyrics use LRC text in the LYRICS field, with plain text in UNSYNCEDLYRICS. Verify the compressed frames, STREAMINFO MD5, and saved source file remain unchanged.
- In Downloads, search for songs, scroll through matches, then cancel search with the keyboard open and after dismissing it. Repeat with long titles, no matches, a swiped row, and active downloads. Check that row menus and trailing swipe controls do not flash or jump, and the native search transition stays smooth.

On macOS 26 or later, the core tests also repackage the AAC probe, read the resulting tags, and compare compressed audio packets. Native playback, seeking, locked-device access, and background relaunch behavior require these device checks; Linux integration tests cannot verify them.
