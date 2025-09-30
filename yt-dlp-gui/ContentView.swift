import SwiftUI
import AppKit

struct ContentView: View {
    @State private var url: String = ""
    @State private var settings = YtDlpSettings.load()
    @State private var showSettings = false
    @StateObject private var downloadManager = DownloadManager()
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            mainContent
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
    
    private var mainContent: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 20) {
                urlInputSection
                statusMessageView
                progressSection
                controlsSection
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 360, alignment: .leading)
            
            Divider()
                .padding(.vertical, -16)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text("Session Log")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    if !downloadManager.downloadLogs.isEmpty {
                        Button("Copy") {
                            copyLogsToPasteboard()
                        }
                        .controlSize(.small)

                        Button("Clear") {
                            downloadManager.clearLogs()
                        }
                        .controlSize(.small)
                    }
                }

                logsSection
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                rawOutputSection
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Video/Playlist URL")
                .font(.headline)
                .foregroundColor(.primary)
            
            TextField("Enter video or playlist URL...", text: $url)
                .textFieldStyle(.plain)
                .font(.body)
                .textContentType(.URL)
                .disableAutocorrection(true)
                .submitLabel(.go)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
                )
                .help("Accepts full video or playlist links from YouTube or any yt-dlp supported site.")
                .onSubmit {
                    if !url.isEmpty && !downloadManager.isDownloading {
                        startDownload()
                    }
                }

        }
    }
    
    @ViewBuilder
    private var statusMessageView: some View {
        if !downloadManager.statusMessage.isEmpty {
            Text(downloadManager.statusMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(NSColor.separatorColor).opacity(0.25), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if downloadManager.isDownloading {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("Download Progress")
                        .font(.headline)

                    Spacer()

                    if !downloadManager.downloadSpeed.isEmpty {
                        Label(downloadManager.downloadSpeed, systemImage: "speedometer")
                            .labelStyle(TitleAndIconLabelStyle())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !downloadManager.eta.isEmpty {
                        Label(downloadManager.eta, systemImage: "clock")
                            .labelStyle(TitleAndIconLabelStyle())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                ProgressView(value: downloadManager.progress)
                    .progressViewStyle(.linear)

                Text("\(Int(downloadManager.progress * 100))% complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.25), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(lastIndex, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var rawOutputSection: some View {
        if settings.showRawOutput && !downloadManager.rawOutput.isEmpty {
            GroupBox {
                ScrollView {
                    Text(downloadManager.rawOutput)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 2)
                }
                .frame(maxHeight: 200)
            } label: {
                Label("Raw Output", systemImage: "chevron.left.slash.chevron.right")
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
                .controlSize(.regular)
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
            } else {
                Button("Download") {
                    startDownload()
                }
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return)
                .controlSize(.regular)
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor)
                )
                .foregroundColor(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.8), lineWidth: 1)
                )
            }

            Spacer()

            if !settings.outputPath.isEmpty && settings.outputPath != "~/Downloads" {
                Label(URL(fileURLWithPath: settings.outputPath).lastPathComponent, systemImage: "folder")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func copyLogsToPasteboard() {
        let pasteboard = NSPasteboard.general
        let joinedLogs = downloadManager.downloadLogs.joined(separator: "\n")
        pasteboard.clearContents()
        pasteboard.setString(joinedLogs, forType: .string)
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
            downloadManager.statusMessage = "Ready to download"
        }
    }
}

#Preview {
    ContentView()
}
