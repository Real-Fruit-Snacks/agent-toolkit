# Pinned versions

Generated 2026-11-01 by scripts/write-versions.ps1.

| Component | Version | File | MB | SHA256 |
|---|---|---|---|---|
| T3 Code (Windows installer) | 0.1.7-nightly.20261101.4035 | `T3-Code-0.1.7-nightly.20261101.4035-x64.exe` | 277 | `042581475dcec80114981386bf0a34aaf3cae87b79965e2a3d75e2e2aaf59004` |
| T3 Code (Windows portable) | 0.1.7-nightly.20261101.4035 | `T3-Code-0.1.7-nightly.20261101.4035-x64.zip` | 185 | `215302f7c5714768af7fada95311ccf94e69047209ce6ec04ec50083b65d3f94` |
| T3 server/CLI (win32) | 0.1.7-nightly.20261101.4035 | `t3-0.1.7-nightly.20261101.4035-win32-x64.zip` | 108 | `73134dddd8477c3330162e9ad5cadc1d86c778f559f99ffb128c33c3a3e43b03` |
| T3 Code (deb) | 0.1.7-nightly.20261101.4035 | `T3-Code-0.1.7-nightly.20261101.4035-amd64.deb` | 153 | `bb8aa9c356321cb88974c8976d4e8b1bc53d90c5519a40b48cec9ee2590febfe` |
| T3 Code (AppImage) | 0.1.7-nightly.20261101.4035 | `T3-Code-0.1.7-nightly.20261101.4035-x86_64.AppImage` | 182 | `45e15a08452b9b4d917fdf9bc1c26fb68003eed9101bcc79e36a43e384dd060f` |
| T3 server/CLI (linux) | 0.1.7-nightly.20261101.4035 | `t3-0.1.7-nightly.20261101.4035-linux-x64.tar.gz` | 118 | `4f825b649b12f3367b2b3a001140f7c5985fd56f180c0c9bfef886c17e49dc87` |
| Claude Code (Windows) | 2.1.316 | `claude-2.1.316-win32-x64.exe` | 320 | `e896a9d8da519353a49bf69ca4a695ba7e09067752687c675b3969041e632d52` |
| Claude Code (Linux glibc) | 2.1.316 | `claude-2.1.316-linux-x64` | 313 | `fd13c70000fec3f2116dfbcbb6121210b4a29328bf0e46210a59dd594a67d824` |
| Claude Code (Linux musl) | 2.1.316 | `claude-2.1.316-linux-x64-musl` | 300 | `8bc3d015479b8b87dfde3f69f9bdb96c658758a8eb31892fd8fbece8d8a08bcf` |
| Node.js (msi) | v24.22.2 | `node-v24.22.2-x64.msi` | 32 | `9231bf64d19bef391dd5ee8af65411d3799c3c44a842d2320849cc1da60b6b6d` |
| Node.js (linux) | v24.22.2 | `node-v24.22.2-linux-x64.tar.xz` | 31 | `48cc0e21e048790e54c0cf5749c2725005313d652651c40b7a21feb9697aaf75` |
| PowerShell 7 (msi) | 7.6.9 | `PowerShell-7.6.9-win-x64.msi` | 112 | `50d33c7494aaf82b987cfd4de3f232d04f91fdd4c0deeca8a669cced3e7cf8f9` |
| Python (Windows) | 3.14.10 | `python-3.14.10-amd64.exe` | 32 | `92480239264744fe0386a1bd8275786fefa126e3129e56a68e22b52c73329965` |
| Git for Windows | 2.56.0.4 | `Git-2.56.0.4-64-bit.exe` | 64 | `4961a4a8cc778d8b6e00a5819e5fe4d078b754555aff7aedc2d77a5d74c2de80` |
| GitHub CLI (msi) | 2.103.3 | `gh_2.103.3_windows_amd64.msi` | 15 | `5073112b7abb5ffbba24b76aee7e89269af531218c0a42751f5f0bfb6440c2cc` |
| GitHub CLI (deb) | 2.103.3 | `gh_2.103.3_linux_amd64.deb` | 14 | `e3bafef96328d1a67de3a968bdfe1cc2ffd58cf6aba8b5e201356897ed06bb3d` |
| WSL platform | 3.0.3.0 | `wsl.3.0.3.0.x64.msi` | 351 | `ae977286974255bd26bf925f00f40f5692c6b2084155cbc0563c09aea091f211` |
| Ubuntu WSL rootfs | noble | `ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz` | 340 | `8251e27ffff381a4af5f41dcb94d867de3e0d9774a9241908ab34555d99315ea` |
| Baked distro export | ubuntu-dev | `ubuntu-dev.tar.gz` | 1424 | `e3d9ee566894e692dcd90ef921e6b43a22596cd8e9347869fe87079448fc9c50` |
| chrome-headless-shell (linux) | 156.0.8078.70 | `chrome-headless-shell-linux64-156.0.8078.70.zip` | 121 | `a313da592261ff1e342c1e507d315f25b1809006c0508f77ce86151d464d4ccb` |

## T3 tool cache (caches/t3-tools-win)

- agent-device 0.21.31
- chrome-headless-shell 156.0.8078.70
- expo-device-hub 0.19.1

## Playwright browsers (caches/playwright-browsers)

- .links
- chromium-1248
- chromium_headless_shell-1248
- ffmpeg-1013
- winldd-1007

## Also in the release

- caches/npm-cache: seeded npm cache for offline installs of playwright, agent-device, expo-device-hub and the skill packages
- caches/claude-skills: the public anthropics/skills set (Apache-2.0)
- caches/claude-code-docs: Claude Code documentation, markdown, from code.claude.com/docs/llms.txt
- caches/pip-wheelhouse: Python wheels for the document skills (win + linux)
- caches/playwright-browsers-linux and caches/t3-tools-linux: Linux browser and tool caches taken from the baked distro
- docs/reference/t3code: T3 Code user docs (MIT), in the repo

## npm tarballs (caches/npm)

- agent-device-0.21.31.tgz
- expo-device-hub-0.19.1.tgz
- playwright-1.64.1.tgz
- playwright-cli-0.1.23.tgz
- playwright-test-1.64.1.tgz
