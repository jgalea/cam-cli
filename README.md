# cam

Viewfinder + capture from any Mac camera, including iPhone Continuity Camera, in a single terminal command.

`cam` opens a live viewfinder window. Press space or return to capture; the photo lands on disk and either renders inline in your terminal (iTerm2/Ghostty/WezTerm/kitty) or pops in Quick Look. No saving to Photos, no AirDrop dance.

It's macOS-only: the camera access and viewfinder window are built on AVFoundation and AppKit, which don't exist on Linux or Windows.

## Install

### Homebrew

```sh
brew tap jgalea/tools
brew install cam
```

### From source

```sh
git clone https://github.com/jgalea/cam-cli.git
cd cam-cli
make
make install            # installs to /usr/local/bin
```

## Use

```sh
cam                     # capture to ~/Pictures/cam/cam-<timestamp>.jpg
cam photo.jpg           # save as ./photo.jpg in current directory
cam -o ~/Desktop/x.jpg  # save at a specific path
cam --no-inline         # skip inline render / Quick Look
cam -d "FaceTime"       # pick a camera by substring of its name
cam --list              # list available cameras
```

In the viewfinder window: **space** or **return** to capture, **esc** or **q** to cancel.

## How it works

`cam` is a small Swift binary that uses `AVFoundation` to open the selected camera, shows a live preview in a borderless NSWindow, and writes the captured JPEG to disk. Inline rendering uses the iTerm2 image protocol (OSC 1337), which is supported by iTerm2, Ghostty, WezTerm, and kitty. When the binary detects no controlling terminal (e.g. running through a pipe or an agent), it falls back to opening Quick Look.

The binary embeds an `Info.plist` with `NSCameraUsageDescription` via a linker section, so macOS can prompt for camera permission cleanly on first run.

## Requirements

- macOS 13 Ventura or newer
- For iPhone Continuity Camera: iPhone XR or later running iOS 16+, unlocked and nearby, signed in to the same Apple Account, with Bluetooth and Wi-Fi on
- Swift toolchain to build from source (`xcode-select --install`)

## Privacy

`cam` makes no network calls. Photos are written only to the path you specify. There is no telemetry.

## License

MIT. See [LICENSE](LICENSE).
