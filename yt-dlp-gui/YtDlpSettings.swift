import Foundation

struct YtDlpSettings: Codable {
    var format: String = "best"
    var quality: String = "best"
    var downloadSubtitles: Bool = true
    var subtitleLanguage: String = "en"
    var audioOnly: Bool = false
    var cookieData: String = ""
    var outputPath: String = "~/Downloads"
    var customYtdlpPath: String = ""
    var customFfmpegPath: String = ""
    var embedSubs: Bool = true
    var writeAutoSubs: Bool = false
    var subtitleFormat: String = "srt"
    var audioFormat: String = "mp3"
    var audioQuality: String = "192"
    var videoCodec: String = "auto"
    var audioCodec: String = "aac"
    var subtitleOnly: Bool = false
    var downloadThumbnail: Bool = false
    var embedThumbnail: Bool = false
    var writeDescription: Bool = false
    var writeInfoJson: Bool = false
    var keepVideo: Bool = false
    var noPlaylist: Bool = false
    var maxDownloads: String = ""
    var rateLimit: String = ""
    var retries: String = "10"
    var userAgent: String = ""
    var proxy: String = ""
    
    var forceConversion: Bool = false
    var deleteOriginal: Bool = true
    
    var enableVerboseLogging: Bool = false
    var showRawOutput: Bool = false
    var logCommands: Bool = true
    
    var useBrowserCookies: Bool = false
    var browserCookieSource: String = "safari"
    var preferredLanguageCode: String = ""
    
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "YtDlpSettings")
        }
    }
    
    static func load() -> YtDlpSettings {
        let decodedSettings: YtDlpSettings
        if let data = UserDefaults.standard.data(forKey: "YtDlpSettings"),
           let settings = try? JSONDecoder().decode(YtDlpSettings.self, from: data) {
            decodedSettings = settings
        } else {
            decodedSettings = YtDlpSettings()
        }

        var adjusted = decodedSettings
        let storedOverride = LocalizationManager.shared.storedLanguageCode()
        if adjusted.preferredLanguageCode.isEmpty, !storedOverride.isEmpty {
            adjusted.preferredLanguageCode = storedOverride
        }

        if !adjusted.preferredLanguageCode.isEmpty {
            LocalizationManager.shared.apply(languageCode: adjusted.preferredLanguageCode)
        }

        var normalizedSubtitleFormat = adjusted.subtitleFormat.lowercased()
        if normalizedSubtitleFormat == "ass" {
            adjusted.subtitleFormat = "srt"
            normalizedSubtitleFormat = "srt"
        }

        if normalizedSubtitleFormat == "txt" {
            adjusted.embedSubs = false
        }

        return adjusted
    }
}
