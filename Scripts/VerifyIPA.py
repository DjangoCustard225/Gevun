#!/usr/bin/env python3
"""Verify the unsigned native build before uploading it."""

import hashlib
import plistlib
import sys
import zipfile
from pathlib import Path

ipa = Path(sys.argv[1])
assert ipa.name == "Gevun.ipa", "Unexpected IPA filename"
expected = plistlib.loads(Path("Gevun/Info.plist").read_bytes())
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None, "Damaged IPA"
    names = set(archive.namelist())
    app = "Payload/Gevun.app/"
    info = plistlib.loads(archive.read(app + "Info.plist"))
    assert info["CFBundleIdentifier"] == "app.gevun.music"
    for key in ("CFBundleDisplayName", "CFBundleShortVersionString", "CFBundleVersion"):
        assert info[key] == expected[key], f"Unexpected {key}"
    assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"], "Not a device build"
    assert info["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconName"] == "GevunIcon", "Native icon not selected"
    assert app + "Assets.car" in names, "Compiled icon catalog missing"
    assert app + "DownloadProbes.plist" in names, "Native audio probes missing"
    assert not any("/_CodeSignature/" in name or name.endswith("embedded.mobileprovision") for name in names), "IPA must be unsigned"
    executable = archive.read(app + info["CFBundleExecutable"])
    assert executable[:4] == b"\xcf\xfa\xed\xfe", "Expected a 64-bit Mach-O executable"
    assert int.from_bytes(executable[4:8], "little") == 0x0100000C, "Expected arm64"
print(f"Verified {ipa.name}: version {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), native icon, arm64, unsigned")
print(f"SHA256 {hashlib.sha256(ipa.read_bytes()).hexdigest()}")
