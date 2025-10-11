import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct SettingsView: View {
    @Binding var settings: YtDlpSettings
    @Environment(\.presentationMode) var presentationMode
    @State private var cookieCount: Int = 0
    @State private var isYtdlpMissing: Bool = false
    @State private var isFfmpegMissing: Bool = false
    @State private var showLanguageRestartNotice: Bool = false
    private let browserCookieOptions: [(labelKey: LocalizedStringKey, value: String)] = [
        ("browser_option_safari", "safari"),
        ("browser_option_brave", "brave"),
        ("browser_option_chrome", "chrome"),
        ("browser_option_chromium", "chromium"),
        ("browser_option_edge", "edge"),
        ("browser_option_firefox", "firefox"),
        ("browser_option_opera", "opera"),
        ("browser_option_vivaldi", "vivaldi")
    ]
    private var ytdlpFooterText: String? {
        guard isYtdlpMissing else { return nil }
        return String(
            format: String(
                localized: "settings_ytdlp_missing_footer",
                comment: "Footer advising yt-dlp installation"
            ),
            "brew install yt-dlp"
        )
    }
    private var ffmpegFooterText: String? {
        guard isFfmpegMissing else { return nil }
        return String(
            format: String(
                localized: "settings_ffmpeg_missing_footer",
                comment: "Footer advising ffmpeg installation"
            ),
            "brew install ffmpeg"
        )
    }
    private var cookiesLoadedText: String {
        String(
            format: String(
                localized: "settings_cookies_loaded_format",
                comment: "Indicates how many cookies were loaded"
            ),
            locale: Locale.current,
            cookieCount
        )
    }
    private var languageOptions: [LocalizationManager.LanguageOption] {
        LocalizationManager.shared.supportedLanguages
    }
    
    init(settings: Binding<YtDlpSettings>) {
        _settings = settings
        _cookieCount = State(initialValue: SettingsView.countCookies(in: settings.wrappedValue.cookieData))
        _isYtdlpMissing = State(initialValue: SettingsView.binaryMissing("yt-dlp", customPath: settings.wrappedValue.customYtdlpPath))
        _isFfmpegMissing = State(initialValue: SettingsView.binaryMissing("ffmpeg", customPath: settings.wrappedValue.customFfmpegPath))
    }

    private func refreshBinaryAvailability() {
        isYtdlpMissing = SettingsView.binaryMissing("yt-dlp", customPath: settings.customYtdlpPath)
        isFfmpegMissing = SettingsView.binaryMissing("ffmpeg", customPath: settings.customFfmpegPath)
    }

    private func refreshCookieCount() {
        cookieCount = SettingsView.countCookies(in: settings.cookieData)
    }

    
    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    generalSection
                    applicationSection
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
            .navigationTitle("settings_title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("settings_cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("settings_save") {
                        settings.save()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 680, minHeight: 760)
        .onAppear {
            showLanguageRestartNotice = false
            settings.preferredLanguageCode = LocalizationManager.shared.normalized(code: settings.preferredLanguageCode)
            refreshBinaryAvailability()
            refreshCookieCount()
        }
        .onChange(of: settings.customYtdlpPath) { _, newValue in
            isYtdlpMissing = SettingsView.binaryMissing("yt-dlp", customPath: newValue)
        }
        .onChange(of: settings.customFfmpegPath) { _, newValue in
            isFfmpegMissing = SettingsView.binaryMissing("ffmpeg", customPath: newValue)
        }
        .onChange(of: settings.cookieData) { _, newValue in
            cookieCount = SettingsView.countCookies(in: newValue)
        }
        .onChange(of: settings.preferredLanguageCode) { _, newValue in
            let normalized = LocalizationManager.shared.normalized(code: newValue)
            if normalized != newValue {
                settings.preferredLanguageCode = normalized
                return
            }
            LocalizationManager.shared.apply(languageCode: normalized)
            showLanguageRestartNotice = true
        }
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(
        title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
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
    private func settingsField<Content: View>(
        label: LocalizedStringKey,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .textCase(.uppercase)
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
    
    private var applicationSection: some View {
        settingsGroup(title: "settings_section_application", systemImage: "globe") {
            settingsField(label: "settings_field_language") {
                Picker("settings_picker_language", selection: $settings.preferredLanguageCode) {
                    ForEach(languageOptions) { option in
                        Text(option.labelKey).tag(option.code)
                    }
                }
                .pickerStyle(.menu)
            }

            if showLanguageRestartNotice {
                Text("settings_language_restart")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var generalSection: some View {
        settingsGroup(title: "settings_section_general", systemImage: "gearshape") {
            settingsField(label: "settings_field_output_directory") {
                HStack(spacing: 12) {
                    TextField("settings_output_placeholder", text: $settings.outputPath)
                        .textFieldStyle(.roundedBorder)
                    Button("settings_browse_button", action: selectOutputDirectory)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                }
            }
            
            settingsField(
                label: "settings_field_custom_ytdlp_path",
                footer: ytdlpFooterText
            ) {
                HStack(spacing: 12) {
                    TextField("settings_autodetect_placeholder", text: $settings.customYtdlpPath)
                        .textFieldStyle(.roundedBorder)
                    Button("settings_browse_button", action: selectYtdlpPath)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                }
            }
            
            settingsField(
                label: "settings_field_custom_ffmpeg_path",
                footer: ffmpegFooterText
            ) {
                HStack(spacing: 12) {
                    TextField("settings_autodetect_placeholder", text: $settings.customFfmpegPath)
                        .textFieldStyle(.roundedBorder)
                    Button("settings_browse_button", action: selectFfmpegPath)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                }
            }
        }
    }
    
    private var videoSection: some View {
        settingsGroup(title: "settings_section_video", systemImage: "film") {
            settingsField(label: "settings_field_video_format") {
                Picker("settings_picker_video_format", selection: $settings.format) {
                    Text("settings_option_video_best").tag("best")
                    Text("settings_option_video_mp4").tag("mp4")
                    Text("settings_option_video_webm").tag("webm")
                    Text("settings_option_video_mkv").tag("mkv")
                    Text("settings_option_video_avi").tag("avi")
                }
                .pickerStyle(.menu)
                .disabled(settings.audioOnly || settings.subtitleOnly)
            }
            
            settingsField(label: "settings_field_resolution_cap") {
                Picker("settings_picker_video_quality", selection: $settings.quality) {
                    Text("settings_option_quality_best").tag("best")
                    Text("settings_option_quality_2160p").tag("height<=2160")
                    Text("settings_option_quality_1440p").tag("height<=1440")
                    Text("settings_option_quality_1080p").tag("height<=1080")
                    Text("settings_option_quality_720p").tag("height<=720")
                    Text("settings_option_quality_480p").tag("height<=480")
                    Text("settings_option_quality_360p").tag("height<=360")
                }
                .pickerStyle(.menu)
                .disabled(settings.audioOnly || settings.subtitleOnly)
            }

            settingsField(label: "settings_field_preferred_codec") {
                Picker("settings_picker_video_codec", selection: $settings.videoCodec) {
                    Text("settings_option_codec_auto").tag("auto")
                    Text("settings_option_codec_h264").tag("h264")
                    Text("settings_option_codec_h265").tag("h265")
                    Text("settings_option_codec_vp9").tag("vp9")
                    Text("settings_option_codec_av1").tag("av01")
                }
                .pickerStyle(.menu)
                .disabled(settings.audioOnly || settings.subtitleOnly)
                .help("settings_video_codec_help")
            }
        }
    }
    
    private var audioSection: some View {
        settingsGroup(title: "settings_section_audio", systemImage: "music.note") {
            Toggle("settings_toggle_audio_only", isOn: $settings.audioOnly)
                .toggleStyle(.switch)
                .padding(.vertical, 4)
                .disabled(settings.subtitleOnly)
            
            settingsField(label: "settings_field_audio_format") {
                Picker("settings_picker_audio_format", selection: $settings.audioFormat) {
                    Text("settings_option_audio_mp3").tag("mp3")
                    Text("settings_option_audio_aac").tag("aac")
                    Text("settings_option_audio_ogg").tag("ogg")
                    Text("settings_option_audio_opus").tag("opus")
                    Text("settings_option_audio_m4a").tag("m4a")
                    Text("settings_option_audio_flac").tag("flac")
                    Text("settings_option_audio_wav").tag("wav")
                }
                .pickerStyle(.menu)
                .disabled(settings.subtitleOnly)
            }
            
            settingsField(label: "settings_field_audio_bitrate") {
                Picker("settings_picker_audio_quality", selection: $settings.audioQuality) {
                    Text("settings_option_bitrate_320").tag("320")
                    Text("settings_option_bitrate_256").tag("256")
                    Text("settings_option_bitrate_192").tag("192")
                    Text("settings_option_bitrate_128").tag("128")
                    Text("settings_option_bitrate_96").tag("96")
                    Text("settings_option_bitrate_64").tag("64")
                }
                .pickerStyle(.menu)
                .disabled(settings.subtitleOnly)
            }
            
            if settings.audioOnly {
                Toggle("settings_toggle_keep_video", isOn: $settings.keepVideo)
                    .disabled(settings.subtitleOnly)
            }
        }
    }
    
    private var postProcessingSection: some View {
        settingsGroup(title: "settings_section_post_processing", systemImage: "wand.and.stars") {
            Group {
                Toggle("settings_toggle_force_conversion", isOn: $settings.forceConversion)
                
                if !settings.audioOnly {
                    Toggle("settings_toggle_delete_original", isOn: $settings.deleteOriginal)
                }
                
                Text("settings_text_force_conversion_warning")
                    .font(.footnote)
                    .foregroundColor(.secondary.opacity(settings.subtitleOnly ? 0.6 : 1))
            }
            .disabled(settings.subtitleOnly)
        }
    }
    
    private var subtitlesSection: some View {
        settingsGroup(title: "settings_section_subtitles", systemImage: "captions.bubble") {
            Toggle("settings_toggle_download_subtitles", isOn: $settings.downloadSubtitles)
                .toggleStyle(.switch)
                .padding(.bottom, settings.downloadSubtitles ? 8 : 0)
                .onChange(of: settings.downloadSubtitles) { oldValue, newValue in
                    guard oldValue != newValue, newValue == false else { return }
                    settings.writeAutoSubs = false
                    settings.embedSubs = false
                    settings.subtitleOnly = false
                }

            if settings.downloadSubtitles {
                settingsField(label: "settings_field_subtitle_languages") {
                    TextField("settings_placeholder_language_examples", text: $settings.subtitleLanguage)
                        .textFieldStyle(.roundedBorder)
                }
                
                settingsField(label: "settings_field_subtitle_format") {
                    Picker("settings_picker_subtitle_format", selection: $settings.subtitleFormat) {
                        Text("settings_option_subtitle_srt").tag("srt")
                        Text("settings_option_subtitle_vtt").tag("vtt")
                        Text("settings_option_subtitle_ass").tag("ass")
                    }
                    .pickerStyle(.segmented)
                }

                if !settings.audioOnly {
                    Toggle("settings_toggle_embed_subtitles", isOn: $settings.embedSubs)
                        .disabled(settings.subtitleOnly)
                }

                Toggle("settings_toggle_download_auto_subtitles", isOn: $settings.writeAutoSubs)

                Toggle("settings_toggle_subtitle_only", isOn: $settings.subtitleOnly)
                    .toggleStyle(.switch)
                    .onChange(of: settings.subtitleOnly) { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        if newValue {
                            settings.audioOnly = false
                            settings.embedSubs = false
                        }
                    }
            }
        }
    }
    
    private var metadataSection: some View {
        settingsGroup(title: "settings_section_metadata", systemImage: "tag") {
            Toggle("settings_toggle_download_thumbnail", isOn: $settings.downloadThumbnail)
            if !settings.audioOnly {
                Toggle("settings_toggle_embed_thumbnail", isOn: $settings.embedThumbnail)
            }
            Toggle("settings_toggle_save_description", isOn: $settings.writeDescription)
            Toggle("settings_toggle_save_info_json", isOn: $settings.writeInfoJson)
        }
    }
    
    private var playlistSection: some View {
        settingsGroup(title: "settings_section_playlists", systemImage: "text.badge.plus") {
            Toggle("settings_toggle_single_video", isOn: $settings.noPlaylist)
            
            settingsField(label: "settings_field_max_downloads") {
                TextField("settings_placeholder_unlimited", text: $settings.maxDownloads)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
    
    private var networkSection: some View {
        settingsGroup(title: "settings_section_network", systemImage: "network") {
            settingsField(label: "settings_field_rate_limit") {
                TextField("settings_placeholder_rate_limit", text: $settings.rateLimit)
                    .textFieldStyle(.roundedBorder)
            }
            
            settingsField(label: "settings_field_retries") {
                TextField("settings_placeholder_retries", text: $settings.retries)
                    .textFieldStyle(.roundedBorder)
            }
            
            settingsField(label: "settings_field_proxy") {
                TextField("settings_placeholder_proxy", text: $settings.proxy)
                    .textFieldStyle(.roundedBorder)
            }
            
            settingsField(label: "settings_field_user_agent") {
                TextField("settings_placeholder_user_agent", text: $settings.userAgent)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
    
    private var loggingSection: some View {
        settingsGroup(title: "settings_section_logging", systemImage: "terminal") {
            Toggle("settings_toggle_verbose_logging", isOn: $settings.enableVerboseLogging)
            Toggle("settings_toggle_show_raw_output", isOn: $settings.showRawOutput)
            Toggle("settings_toggle_log_commands", isOn: $settings.logCommands)
            
            Text("settings_text_verbose_logging_info")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
    
    private var authenticationSection: some View {
        settingsGroup(title: "settings_section_authentication", systemImage: "lock") {
            Toggle("settings_toggle_pass_browser_cookies", isOn: $settings.useBrowserCookies)
                .toggleStyle(.switch)
                .help("settings_browser_help")

            if settings.useBrowserCookies {
                Text("settings_text_manual_cookie_disabled")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if settings.useBrowserCookies {
                settingsField(
                    label: "settings_field_browser",
                    footer: String(
                        localized: "settings_browser_footer",
                        comment: "Explains browser cookie pass-through"
                    )
                ) {
                    Picker("settings_picker_browser", selection: $settings.browserCookieSource) {
                        ForEach(browserCookieOptions, id: \.value) { option in
                            Text(option.labelKey).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            if settings.useBrowserCookies {
                Divider()
            }

            Text("settings_text_cookies_title")
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
                .disabled(settings.useBrowserCookies)
            
            if !settings.cookieData.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(cookiesLoadedText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("settings_clear_cookies_button") {
                        settings.cookieData = ""
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .disabled(settings.useBrowserCookies)
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
    
    private static func binaryMissing(_ name: String, customPath: String) -> Bool {
        let fm = FileManager.default
        let resolvedCustom = expandTilde(customPath)
        if !resolvedCustom.isEmpty, fm.isExecutableFile(atPath: resolvedCustom) {
            return false
        }

        let pathVariable = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var searchPaths = pathVariable
            .split(separator: ":")
            .map(String.init)

        let fallbackPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/opt/homebrew/sbin",
            "/usr/local/sbin"
        ]

        searchPaths.append(contentsOf: fallbackPaths)
        var visited = Set<String>()

        for path in searchPaths {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, visited.insert(trimmed).inserted else { continue }
            let candidate = (trimmed as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) {
                return false
            }
        }
        return true
    }

    private static func expandTilde(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : (trimmed as NSString).expandingTildeInPath
    }

    private static func countCookies(in cookieData: String) -> Int {
        var count = 0
        cookieData.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                count += 1
            }
        }
        return count
    }
}
