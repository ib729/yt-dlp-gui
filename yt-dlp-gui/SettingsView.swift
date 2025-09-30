import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Binding var settings: YtDlpSettings
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var downloadManager = DownloadManager()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    generalSection
                    videoSection
                    audioSection
                    postProcessingSection
                    subtitlesSection
                    metadataSection
                    playlistSection
                    networkSection
                    loggingSection
                    authenticationSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        settings.save()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 680, minHeight: 760)
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.bottom, 4)

            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func settingsField<Content: View>(label: String, footer: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            content()

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private var loadedCookieCount: Int {
        settings.cookieData
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#")
            }
            .count
    }

    private var generalSection: some View {
        settingsGroup(title: "General", systemImage: "gearshape") {
            settingsField(label: "Output Directory") {
                HStack(spacing: 12) {
                    TextField("~/Downloads", text: $settings.outputPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse", action: selectOutputDirectory)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                }
            }
            
            settingsField(label: "Custom yt-dlp Path", footer: "yt-dlp powers downloads. Install with: brew install yt-dlp") {
                HStack(spacing: 12) {
                    TextField("Auto-detect", text: $settings.customYtdlpPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse", action: selectYtdlpPath)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                }
            }
            
            settingsField(label: "Custom FFmpeg Path", footer: "FFmpeg is required for audio extraction and video processing. Install with: brew install ffmpeg") {
                HStack(spacing: 12) {
                    TextField("Auto-detect", text: $settings.customFfmpegPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse", action: selectFfmpegPath)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                }
            }
        }
    }
    
    private var videoSection: some View {
        settingsGroup(title: "Video", systemImage: "film") {
            settingsField(label: "Video Format") {
                Picker("Video Format", selection: $settings.format) {
                    Text("Best Available").tag("best")
                    Text("MP4").tag("mp4")
                    Text("WebM").tag("webm")
                    Text("MKV").tag("mkv")
                    Text("AVI").tag("avi")
                }
                .pickerStyle(.menu)
                .disabled(settings.audioOnly)
            }
            
            settingsField(label: "Resolution Cap") {
                Picker("Video Quality", selection: $settings.quality) {
                    Text("Best Available").tag("best")
                    Text("4K (2160p)").tag("height<=2160")
                    Text("1440p").tag("height<=1440")
                    Text("1080p").tag("height<=1080")
                    Text("720p").tag("height<=720")
                    Text("480p").tag("height<=480")
                    Text("360p").tag("height<=360")
                }
                .pickerStyle(.menu)
                .disabled(settings.audioOnly)
            }
            
            settingsField(label: "Preferred Codec") {
                Picker("Video Codec", selection: $settings.videoCodec) {
                    Text("Auto").tag("auto")
                    Text("H.264").tag("h264")
                    Text("H.265 (HEVC)").tag("h265")
                    Text("VP9").tag("vp9")
                    Text("AV1").tag("av01")
                }
                .pickerStyle(.menu)
                .disabled(settings.audioOnly)
            }
        }
    }
    
    private var audioSection: some View {
        settingsGroup(title: "Audio", systemImage: "music.note") {
            Toggle("Audio Only", isOn: $settings.audioOnly)
                .toggleStyle(.switch)
                .padding(.vertical, 4)
            
            settingsField(label: "Audio Format") {
                Picker("Audio Format", selection: $settings.audioFormat) {
                    Text("MP3").tag("mp3")
                    Text("AAC").tag("aac")
                    Text("OGG Vorbis").tag("ogg")
                    Text("Opus").tag("opus")
                    Text("M4A").tag("m4a")
                    Text("FLAC").tag("flac")
                    Text("WAV").tag("wav")
                }
                .pickerStyle(.menu)
            }
            
            settingsField(label: "Bitrate") {
                Picker("Audio Quality", selection: $settings.audioQuality) {
                    Text("320 kbps").tag("320")
                    Text("256 kbps").tag("256")
                    Text("192 kbps").tag("192")
                    Text("128 kbps").tag("128")
                    Text("96 kbps").tag("96")
                    Text("64 kbps").tag("64")
                }
                .pickerStyle(.menu)
            }
            
            if settings.audioOnly {
                Toggle("Keep video file after extraction", isOn: $settings.keepVideo)
            }
        }
    }
    
    private var postProcessingSection: some View {
        settingsGroup(title: "Post-Processing", systemImage: "wand.and.stars") {
            Toggle("Force conversion", isOn: $settings.forceConversion)
            
            if !settings.audioOnly {
                Toggle("Delete original after conversion", isOn: $settings.deleteOriginal)
            }
            
            Text("Forcing conversion re-encodes media even when the source matches your target format.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
    
    private var subtitlesSection: some View {
        settingsGroup(title: "Subtitles", systemImage: "captions.bubble") {
            Toggle("Download subtitles", isOn: $settings.downloadSubtitles)
                .toggleStyle(.switch)
                .padding(.bottom, settings.downloadSubtitles ? 8 : 0)
            
            if settings.downloadSubtitles {
                settingsField(label: "Languages") {
                    TextField("e.g. en,es,fr", text: $settings.subtitleLanguage)
                        .textFieldStyle(.roundedBorder)
                }
                
                settingsField(label: "Subtitle Format") {
                    Picker("Subtitle Format", selection: $settings.subtitleFormat) {
                        Text("SRT").tag("srt")
                        Text("VTT").tag("vtt")
                        Text("ASS").tag("ass")
                    }
                    .pickerStyle(.segmented)
                }
                
                if !settings.audioOnly {
                    Toggle("Embed subtitles into video", isOn: $settings.embedSubs)
                }
                
                Toggle("Download auto-generated subtitles", isOn: $settings.writeAutoSubs)
            }
        }
    }
    
    private var metadataSection: some View {
        settingsGroup(title: "Metadata & Thumbnails", systemImage: "tag") {
            Toggle("Download thumbnail", isOn: $settings.downloadThumbnail)
            if !settings.audioOnly {
                Toggle("Embed thumbnail in media file", isOn: $settings.embedThumbnail)
            }
            Toggle("Save video description", isOn: $settings.writeDescription)
            Toggle("Save info JSON", isOn: $settings.writeInfoJson)
        }
    }
    
    private var playlistSection: some View {
        settingsGroup(title: "Playlists", systemImage: "text.badge.plus") {
            Toggle("Download single video only", isOn: $settings.noPlaylist)
            
            settingsField(label: "Max downloads") {
                TextField("Unlimited", text: $settings.maxDownloads)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
    
    private var networkSection: some View {
        settingsGroup(title: "Network", systemImage: "network") {
            settingsField(label: "Rate limit") {
                TextField("e.g. 1M", text: $settings.rateLimit)
                    .textFieldStyle(.roundedBorder)
            }
            
            settingsField(label: "Retries") {
                TextField("10", text: $settings.retries)
                    .textFieldStyle(.roundedBorder)
            }
            
            settingsField(label: "Proxy") {
                TextField("http://proxy:port", text: $settings.proxy)
                    .textFieldStyle(.roundedBorder)
            }
            
            settingsField(label: "User agent") {
                TextField("Default", text: $settings.userAgent)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
    
    private var loggingSection: some View {
        settingsGroup(title: "Logging & Debug", systemImage: "terminal") {
            Toggle("Enable verbose logging", isOn: $settings.enableVerboseLogging)
            Toggle("Show raw output", isOn: $settings.showRawOutput)
            Toggle("Log command invocations", isOn: $settings.logCommands)
            
            Text("Verbose logging streams the full yt-dlp output to the log panels.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
    
    private var authenticationSection: some View {
        settingsGroup(title: "Authentication", systemImage: "lock") {
            Text("Cookies (Netscape format)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            TextEditor(text: $settings.cookieData)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 120, maxHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            
            if settings.cookieData.isEmpty {
                Text("Paste browser cookies exported in Netscape format.\nExample:\n# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t…")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(loadedCookieCount) cookies loaded")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") {
                        settings.cookieData = ""
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
    }
    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                settings.outputPath = url.path
            }
        }
    }
    
    private func selectYtdlpPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.unixExecutable]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                settings.customYtdlpPath = url.path
            }
        }
    }
    
    private func selectFfmpegPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.unixExecutable]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                settings.customFfmpegPath = url.path
            }
        }
    }
}
