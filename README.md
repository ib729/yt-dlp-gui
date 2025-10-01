<div align="center">
    <img src="stuff/yt-dlp-gui banner.png">
    <h1>yt-dlp-gui</h1>
    <p>A native SwiftUI interface for yt-dlp.</p>
</div>

## Features
- Clean, responsive, and minimal SwiftUI interface for yt-dlp.
- Support for yt-dlp's full range of formats (video, audio, playlists).
- Customizable download options including quality, audio, subtitles, etc.
- Download media from [thousands of sites](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md).

## Screenshots
Coming soon...

## Installation
- Install [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://github.com/FFmpeg/FFmpeg) first.
- Download the .dmg from Releases and drag yt-dlp-gui.app into /Applications.
- Right-click the app, choose Open, then confirm to bypass Gatekeeper.  

If Gatekeeper still blocks the app:
```
xattr -r -d com.apple.quarantine /Applications/yt-dlp-gui.app
```

## Usage
  - Launch yt-dlp-gui on macOS (first run may require Gatekeeper approval).
  - Pick your preferred format and output folder in settings (cmd+, or click gear icon top right)
  - Paste URL into input field.
  - Click Download and watch the progress log for status and errors.

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for more information.
