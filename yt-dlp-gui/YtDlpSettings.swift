import Foundation

struct YtDlpSettings: Codable {
    var format: String = "best"
    var quality: String = "best"
    var downloadSubtitles: Bool = false
    var subtitleLanguage: String = "en"
    var audioOnly: Bool = false
    var cookieData: String = ""
    var outputPath: String = "~/Downloads"
    var customYtdlpPath: String = ""
    var customFfmpegPath: String = ""
    var embedSubs: Bool = false
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
    
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "YtDlpSettings")
        }
    }
    
    static func load() -> YtDlpSettings {
        if let data = UserDefaults.standard.data(forKey: "YtDlpSettings"),
           let settings = try? JSONDecoder().decode(YtDlpSettings.self, from: data) {
            return settings
        }
        return YtDlpSettings()
    }
}
