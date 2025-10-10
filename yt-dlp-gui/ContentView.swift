import SwiftUI
import Foundation
import AppKit

struct ContentView: View {
    @State private var url: String = ""
    @State private var settings = YtDlpSettings.load()
    @State private var showSettings = false
    @StateObject private var downloadManager = DownloadManager()

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? String(
                localized: "content_header_version_unknown",
                comment: "Fallback value when app version is unavailable"
            )
    }

    private var progressLabelText: String {
        let percentage = Int(downloadManager.progress * 100)
        return String(
            format: String(localized: "download_progress_format", comment: "Download progress percentage label"),
            locale: Locale.current,
            percentage
        )
    }
    
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("content_header_title")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(
                    String(
                        format: String(
                            localized: "content_header_version_format",
                            comment: "App version label with placeholder"
                        ),
                        appVersion
                    )
                )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
            
            Button(action: { showSettings = true }) {
                Label("content_header_settings", systemImage: "gear")
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
                    Text("session_log_title")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    if !downloadManager.downloadLogs.isEmpty {
                        Button("session_log_copy") {
                            copyLogsToPasteboard()
                        }
                        .controlSize(.small)

                        Button("session_log_clear") {
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
            Text("url_input_title")
                .font(.headline)
                .foregroundColor(.primary)
            
            TextField("url_input_placeholder", text: $url)
                .textFieldStyle(.plain)
                .font(.body)
                .textContentType(.URL)
                .disableAutocorrection(true)
                .submitLabel(.go)
                .padding(.vertical, 13)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
                )
                .help("url_input_help")
                .onSubmit {
                    let urls = normalizedUrls(from: url)
                    if !urls.isEmpty && !downloadManager.isDownloading {
                        startDownload(with: urls)
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
                .padding(.vertical, 13)
                .padding(.horizontal, 16)
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
                    Text("download_progress_title")
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

                Text(progressLabelText)
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
                Label("raw_output_title", systemImage: "chevron.left.slash.chevron.right")
            }
        }
    }
    
    private var controlsSection: some View {
        HStack(spacing: 16) {
            if downloadManager.isDownloading {
                Button(action: downloadManager.cancelDownload) {
                    Text("cancel_button")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(NSColor.windowBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                        )
                }
                .keyboardShortcut(.escape)
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                let parsedUrls = normalizedUrls(from: url)
                let isDisabled = parsedUrls.isEmpty

                Button(action: { startDownload(with: parsedUrls) }) {
                    Text("download_button")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isDisabled ? Color.accentColor.opacity(0.45) : Color.accentColor)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.accentColor.opacity(isDisabled ? 0.35 : 0.8), lineWidth: 1)
                        )
                        .foregroundColor(.white.opacity(isDisabled ? 0.8 : 1))
                }
                .disabled(isDisabled)
                .keyboardShortcut(.return)
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    
    private func startDownload(with urls: [String]) {
        guard !urls.isEmpty else { return }
        
        downloadManager.downloadVideos(urls: urls, settings: settings)
    }

    private func normalizedUrls(from rawValue: String) -> [String] {
        return rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private func checkYtdlpInstallation() {
        let ytdlpPath = downloadManager.findYTdlpPath()
        let ffmpegPath = downloadManager.findFfmpegPath()
        
        if ytdlpPath.isEmpty {
            let installCommand = "brew install yt-dlp"
            downloadManager.statusMessage = String(
                format: String(
                    localized: "status_ytdlp_missing",
                    comment: "Warns user yt-dlp is missing with install command placeholder"
                ),
                installCommand
            )
        } else if ffmpegPath.isEmpty {
            let installCommand = "brew install ffmpeg"
            downloadManager.statusMessage = String(
                format: String(
                    localized: "status_ffmpeg_missing",
                    comment: "Warns user ffmpeg is missing with install command placeholder"
                ),
                installCommand
            )
        } else {
            downloadManager.statusMessage = String(
                localized: "status_ready",
                comment: "Status message when everything is ready"
            )
        }
    }
}

#Preview {
    ContentView()
}
