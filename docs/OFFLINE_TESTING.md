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

Native playback, seeking, locked-device access, and background relaunch behavior require these device checks; Linux integration tests cannot verify them.
