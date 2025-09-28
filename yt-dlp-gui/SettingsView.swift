import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Binding var settings: YtDlpSettings
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var downloadManager = DownloadManager()
    
    var body: some View {
        NavigationView {
            Form {
                // General Settings
                Section("General") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Output Directory")
                            .font(.headline)
                        HStack {
                            TextField("~/Downloads", text: $settings.outputPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse") {
                                selectOutputDirectory()
                            }
                            .controlSize(.small)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom yt-dlp Path")
                            .font(.headline)
                        HStack {
                            TextField("Auto-detect", text: $settings.customYtdlpPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse") {
                                selectYtdlpPath()
                            }
                            .controlSize(.small)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom FFmpeg Path")
                            .font(.headline)
                        HStack {
                            TextField("Auto-detect", text: $settings.customFfmpegPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse") {
                                selectFfmpegPath()
                            }
                            .controlSize(.small)
                        }
                        Text("FFmpeg is required for audio extraction and video processing. Install with: brew install ffmpeg")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Video Settings
                Section("Video") {
                    Picker("Video Format", selection: $settings.format) {
                        Text("Best").tag("best")
                        Text("MP4").tag("mp4")
                        Text("WebM").tag("webm")
                        Text("MKV").tag("mkv")
                        Text("AVI").tag("avi")
                    }
                    .disabled(settings.audioOnly)
                    
                    Picker("Video Quality", selection: $settings.quality) {
                        Text("Best").tag("best")
                        Text("4K (2160p)").tag("height<=2160")
                        Text("1440p").tag("height<=1440")
                        Text("1080p").tag("height<=1080")
                        Text("720p").tag("height<=720")
                        Text("480p").tag("height<=480")
                        Text("360p").tag("height<=360")
                    }
                    .disabled(settings.audioOnly)
                    
                    Picker("Video Codec", selection: $settings.videoCodec) {
                        Text("Auto (Best for format)").tag("auto")
                        Text("H.264").tag("h264")
                        Text("H.265 (HEVC)").tag("h265")
                        Text("VP9").tag("vp9")
                        Text("AV1").tag("av01")
                    }
                    .disabled(settings.audioOnly)
                }
                
                // Audio Settings
                Section("Audio") {
                    Toggle("Audio Only", isOn: $settings.audioOnly)
                    
                    Picker("Audio Format", selection: $settings.audioFormat) {
                        Text("MP3").tag("mp3")
                        Text("AAC").tag("aac")
                        Text("OGG Vorbis").tag("ogg")
                        Text("M4A").tag("m4a")
                        Text("FLAC").tag("flac")
                        Text("WAV").tag("wav")
                    }
                    
                    Picker("Audio Quality", selection: $settings.audioQuality) {
                        Text("320 kbps").tag("320")
                        Text("256 kbps").tag("256")
                        Text("192 kbps").tag("192")
                        Text("128 kbps").tag("128")
                        Text("96 kbps").tag("96")
                        Text("64 kbps").tag("64")
                    }
                    
                    if settings.audioOnly {
                        Toggle("Keep Video After Extraction", isOn: $settings.keepVideo)
                    }
                }
                
                // Conversion Settings
                Section("Post-Processing") {
                    Toggle("Force Conversion", isOn: $settings.forceConversion)
                    
                    if !settings.audioOnly {
                        Toggle("Delete Original After Conversion", isOn: $settings.deleteOriginal)
                    }
                    
                    Text("Force conversion will re-encode the video even if the format matches. This ensures consistent quality but takes longer.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                // Subtitles Settings
                Section("Subtitles") {
                    Toggle("Download Subtitles", isOn: $settings.downloadSubtitles)
                    
                    if settings.downloadSubtitles {
                        TextField("Languages (e.g., en,es,fr)", text: $settings.subtitleLanguage)
                            .textFieldStyle(.roundedBorder)
                        
                        Picker("Subtitle Format", selection: $settings.subtitleFormat) {
                            Text("SRT").tag("srt")
                            Text("VTT").tag("vtt")
                            Text("ASS").tag("ass")
                        }
                        
                        if !settings.audioOnly {
                            Toggle("Embed Subtitles", isOn: $settings.embedSubs)
                        }
                        
                        Toggle("Download Auto-Generated Subtitles", isOn: $settings.writeAutoSubs)
                    }
                }
                
                // Metadata Settings
                Section("Metadata & Thumbnails") {
                    Toggle("Download Thumbnail", isOn: $settings.downloadThumbnail)
                    
                    if !settings.audioOnly {
                        Toggle("Embed Thumbnail", isOn: $settings.embedThumbnail)
                    }
                    
                    Toggle("Write Description", isOn: $settings.writeDescription)
                    Toggle("Write Info JSON", isOn: $settings.writeInfoJson)
                }
                
                // Playlist Settings
                Section("Playlist") {
                    Toggle("Download Single Video Only", isOn: $settings.noPlaylist)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Max Downloads")
                            .font(.headline)
                        TextField("Unlimited", text: $settings.maxDownloads)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                // Network Settings
                Section("Network") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rate Limit")
                            .font(.headline)
                        TextField("e.g., 1M", text: $settings.rateLimit)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Retries")
                            .font(.headline)
                        TextField("10", text: $settings.retries)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Proxy")
                            .font(.headline)
                        TextField("http://proxy:port", text: $settings.proxy)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("User Agent")
                            .font(.headline)
                        TextField("Default", text: $settings.userAgent)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                // Logging & Debug Settings
                Section("Logging & Debug") {
                    Toggle("Enable Verbose Logging", isOn: $settings.enableVerboseLogging)
                    
                    Toggle("Show Raw Output", isOn: $settings.showRawOutput)
                    
                    Toggle("Log Commands", isOn: $settings.logCommands)
                    
                    Text("Enable verbose logging to see detailed yt-dlp output. Raw output shows unprocessed terminal output.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                // Authentication Settings
                Section("Authentication") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cookies (Netscape Format)")
                            .font(.headline)
                        
                        TextEditor(text: $settings.cookieData)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 100, maxHeight: 200)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        
                        if settings.cookieData.isEmpty {
                            Text("Paste your browser cookies here in Netscape format.\nExample:\n# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t...\t__Secure-3PSID\tvalue")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("\(settings.cookieData.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.hasPrefix("#") }.count) cookies loaded")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button("Clear") {
                                    settings.cookieData = ""
                                }
                                .controlSize(.small)
                                .buttonStyle(.borderless)
                                .foregroundColor(.red)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
            .formStyle(.grouped)
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
        .frame(minWidth: 600, minHeight: 700)
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
