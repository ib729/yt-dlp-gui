import SwiftUI

struct ContentView: View {
    @State private var url: String = ""
    @State private var settings = YtDlpSettings.load()
    @State private var showSettings = false
    @StateObject private var downloadManager = DownloadManager()
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            VStack(spacing: 24) {
                urlInputSection
                statusSection
                controlsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 700, minHeight: 500)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: $settings)
        }
        .onAppear {
            checkYtdlpInstallation()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            settings = YtDlpSettings.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("yt-dlp-gui")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button(action: { showSettings = true }) {
                Label("Settings", systemImage: "gear")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Video URL", systemImage: "link")
                .font(.headline)
                .foregroundColor(.primary)
            
            TextField("Enter YouTube or video URL...", text: $url)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit {
                    if !url.isEmpty && !downloadManager.isDownloading {
                        startDownload()
                    }
                }
        }
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if downloadManager.isDownloading {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Progress")
                            .font(.headline)
                        
                        Spacer()
                        
                        if !downloadManager.downloadSpeed.isEmpty {
                            Text(downloadManager.downloadSpeed)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if !downloadManager.eta.isEmpty {
                            Text(downloadManager.eta)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    ProgressView(value: downloadManager.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text("\(Int(downloadManager.progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if !downloadManager.downloadLogs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Logs")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button("Clear") {
                            downloadManager.clearLogs()
                        }
                        .controlSize(.small)
                    }
                    
                    ScrollView {
                        ScrollViewReader { proxy in
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(downloadManager.downloadLogs.enumerated()), id: \.offset) { index, log in
                                    Text(log)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(index)
                                }
                            }
                            .onChange(of: downloadManager.downloadLogs.count) {
                                if let lastIndex = downloadManager.downloadLogs.indices.last {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(lastIndex, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                }
            }
            
            if settings.showRawOutput && !downloadManager.rawOutput.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Raw Output")
                        .font(.headline)
                    
                    ScrollView {
                        Text(downloadManager.rawOutput)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                }
            }
        }
    }
    
    private var controlsSection: some View {
        HStack(spacing: 16) {
            if downloadManager.isDownloading {
                Button("Cancel") {
                    downloadManager.cancelDownload()
                }
                .keyboardShortcut(.escape)
                .controlSize(.large)
            } else {
                Button("Download") {
                    startDownload()
                }
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
            
            Spacer()
            
            if settings.audioOnly {
                Label("Audio Only", systemImage: "music.note")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !settings.outputPath.isEmpty && settings.outputPath != "~/Downloads" {
                Label(URL(fileURLWithPath: settings.outputPath).lastPathComponent, systemImage: "folder")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func startDownload() {
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty else { return }
        
        downloadManager.downloadVideo(url: trimmedUrl, settings: settings)
    }
    
    private func checkYtdlpInstallation() {
        let ytdlpPath = downloadManager.findYTdlpPath()
        let ffmpegPath = downloadManager.findFfmpegPath()
        
        if ytdlpPath.isEmpty {
            downloadManager.statusMessage = "⚠️ yt-dlp not found. Install it with: brew install yt-dlp"
        } else if ffmpegPath.isEmpty {
            downloadManager.statusMessage = "⚠️ ffmpeg not found. Install it with: brew install ffmpeg"
        } else {
            downloadManager.statusMessage = "✅ Ready to download"
        }
    }
}

#Preview {
    ContentView()
}
