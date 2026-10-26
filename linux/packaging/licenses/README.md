# Vendored license texts

Verbatim upstream files for components that no Ubuntu package on the build
host owns, so `Scripts/appimage-notices.py` cannot read their notices from
dpkg. `../appimage-notices.json` lists them. Fetched 2026-10-25.

The AppImage runtime is the ELF header in front of the AppImage's squashfs.
appimagetool downloads it from the type2-runtime `continuous` release, and it
statically links libfuse, squashfuse, musl, zstd and zlib. The set below
matches runtime commits `75849dc` and `fedfad5` (libfuse 3.15.0, squashfuse
0.5.2, zstd 1.5.6, zlib 1.3.2, musl 1.2.5 from Alpine 3.21).
`python3 Scripts/appimage-notices.py runtime-info <file>.AppImage` shows what
a given AppImage embeds; refresh these texts if those versions change.

| File | Upstream ref | SHA-256 |
| --- | --- | --- |
| `appimage-type2-runtime/type2-runtime-LICENSE.txt` | AppImage/type2-runtime `LICENSE` at `75849dce7cc37e4319b633df1f116ca895c71a12` (unchanged at `fedfad5`) | `aa154fc9070614bbe7921f89db11efd1dba7a1f3a41685958110e2230f9c0ca1` |
| `appimage-type2-runtime/libfuse-LGPL2.txt` | libfuse `LGPL2.txt` at `fuse-3.15.0` | `dc626520dcd53a22f727af3ee42c770e56c97a64fe3adb063799d8ab032fe551` |
| `appimage-type2-runtime/squashfuse-LICENSE.txt` | vasi/squashfuse `LICENSE` at `0.5.2` | `9e909cc8a8ba27b1a649c964cf9eda37de911f3138c2b64e6d2f01703904ac13` |
| `appimage-type2-runtime/zstd-LICENSE.txt` | facebook/zstd `LICENSE` at `v1.5.6` (BSD-3-Clause half of its dual license) | `7055266497633c9025b777c78eb7235af13922117480ed5c674677adc381c9d8` |
| `appimage-type2-runtime/zlib-LICENSE.txt` | madler/zlib `LICENSE` at `v1.3.2` | `e32ff4e00d9d94930537635291da39e7e612703334bf6fde8c7f1686fe8a45a2` |
| `appimage-type2-runtime/musl-COPYRIGHT.txt` | musl `COPYRIGHT` at `v1.2.5` | `f9bc4423732350eb0b3f7ed7e91d530298476f8fec0c6c427a1c04ade22655af` |
