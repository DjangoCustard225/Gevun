#!/usr/bin/env python3
"""Exercise downloads against an isolated Navidrome binary using generated audio.

Usage: python3 Scripts/TestDownloadServer.py /path/to/navidrome
Requires ffmpeg and ffprobe. Never uses a configured Gevun instance or real music.
"""

import hashlib
import json
import os
from pathlib import Path
import secrets
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request


def run(binary):
    binary = str(Path(binary).resolve())
    password = secrets.token_hex(24)
    process = None
    environment = {key: value for key, value in os.environ.items() if not key.startswith("ND_")}
    with tempfile.TemporaryDirectory(prefix="gevun-download-test-") as directory:
        root = Path(directory)
        music = root / "music"
        music.mkdir()
        data = root / "data"
        data.mkdir()
        original = music / "fixture.flac"
        subprocess.run([
            "ffmpeg", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=8:sample_rate=48000",
            "-ac", "2", "-c:a", "flac", "-metadata", "title=Fixture", "-metadata", "album=Downloads",
            "-metadata", "artist=Gevun", str(original),
        ], check=True)
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        base = f"http://127.0.0.1:{port}/fixture"
        config = root / "navidrome.toml"

        def start(downloads=True):
            nonlocal process
            config.write_text(
                f'Address = "127.0.0.1"\nPort = {port}\nBaseURL = "/fixture"\n'
                f'MusicFolder = "{music}"\nDataFolder = "{data}"\n'
                f'EnableDownloads = {str(downloads).lower()}\n'
                'EnableInsightsCollector = false\nAgents = ""\nLogLevel = "error"\n'
            )
            process = subprocess.Popen(
                [binary, "--configfile", str(config), "--nobanner"], env=environment,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            for _ in range(100):
                if process.poll() is not None:
                    raise AssertionError("Fixture server exited during startup")
                try:
                    with urllib.request.urlopen(base + "/ping", timeout=1):
                        return
                except (urllib.error.URLError, TimeoutError):
                    time.sleep(0.1)
            raise AssertionError("Fixture server did not start")

        def stop():
            nonlocal process
            if process:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                process = None

        def request(endpoint, **parameters):
            salt = secrets.token_hex(8)
            parameters.update(u="fixture", t=hashlib.md5((password + salt).encode()).hexdigest(),
                              s=salt, v="1.16.1", c="Gevun", f="json")
            address = base + "/rest/" + endpoint + ".view?" + urllib.parse.urlencode(parameters)
            try:
                with urllib.request.urlopen(address, timeout=30) as response:
                    return response.status, response.read()
            except urllib.error.HTTPError as error:
                return error.code, error.read()

        def probe(payload, suffix):
            file = root / ("download." + suffix)
            file.write_bytes(payload)
            result = subprocess.run([
                "ffprobe", "-v", "error", "-show_entries", "stream=codec_name:format=duration",
                "-of", "json", str(file),
            ], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
            value = json.loads(result.stdout)
            assert float(value["format"]["duration"]) >= 7.8, "Truncated audio"
            return value["streams"][0]["codec_name"]

        try:
            start()
            setup = urllib.request.Request(base + "/auth/createAdmin",
                data=json.dumps({"username": "fixture", "password": password}).encode(),
                headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(setup, timeout=10) as response:
                assert response.status == 200
            song_id = None
            for _ in range(100):
                _, body = request("search3", query="", songCount=10, albumCount=0, artistCount=0)
                songs = json.loads(body)["subsonic-response"].get("searchResult3", {}).get("song", [])
                if songs:
                    song_id = songs[0]["id"]
                    break
                time.sleep(0.1)
            assert song_id, "Fixture song wasn't scanned"
            status, payload = request("download", id=song_id, format="raw", bitrate=0)
            assert status == 200 and payload == original.read_bytes(), "Original file was changed"
            print("PASS Original: exact source bytes")
            for format_name, bitrate in [("opus", 128), ("mp3", 320), ("aac", 256)]:
                status, payload = request("download", id=song_id, format=format_name, bitrate=bitrate)
                assert status == 200
                assert probe(payload, format_name) == format_name, "Unexpected codec"
                print(f"PASS {format_name.upper()} {bitrate} kbps: codec and complete duration")
            status, payload = request("stream", id=song_id, format="raw", maxBitRate=0)
            assert status == 200 and payload == original.read_bytes()
            print("PASS Online stream remains original")
            stop()
            start(downloads=False)
            for format_name in ["raw", "opus", "mp3", "aac"]:
                status, payload = request("download", id=song_id, format=format_name, bitrate=128)
                error = json.loads(payload)["subsonic-response"]
                assert error["status"] == "failed" and error["error"]["code"] == 50
            print("PASS Disabled downloads reject all four formats")
            stop()
            database = sqlite3.connect(data / "navidrome.db")
            # Navidrome recreates missing default profiles. Break the executable instead,
            # then request an uncached bitrate to exercise unavailable server conversion.
            database.execute("UPDATE transcoding SET command = 'gevun-missing-transcoder %s' WHERE target_format = 'opus'")
            database.commit()
            database.close()
            start()
            status, payload = request("download", id=song_id, format="opus", bitrate=96)
            assert status >= 400 or not payload or payload.lstrip().startswith((b"{", b"<")), "Broken transcoder must not return valid audio"
            print("PASS Unavailable Opus transcoder returns a download error")
        finally:
            stop()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    run(sys.argv[1])
