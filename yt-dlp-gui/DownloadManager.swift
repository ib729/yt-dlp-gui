import Foundation
import Combine

class DownloadManager: ObservableObject {
    @Published var isDownloading = false
    @Published var statusMessage = ""
    @Published var progress: Double = 0.0
    @Published var downloadSpeed = ""
    @Published var eta = ""
    @Published var downloadLogs: [String] = []
    @Published var rawOutput: String = ""
    
    private var process: Process?
    private var settings: YtDlpSettings?
    private var needsConversion = false
    private var downloadedFilePath = ""
    
    func findYTdlpPath() -> String {
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["yt-dlp"]
        
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        whichProcess.standardError = Pipe()
        
        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            
            if whichProcess.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    return path
                }
            }
        } catch {
            addLog("Error running which: \(error)")
        }
        
        let possiblePaths = [
            "/opt/homebrew/bin/yt-dlp",  // Apple Silicon Macs
            "/usr/local/bin/yt-dlp",     // Intel Macs
            "/usr/bin/yt-dlp",           // System installation
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                addLog("Found yt-dlp at: \(path)")
                return path
            }
        }
        
        addLog("yt-dlp not found in any standard location")
        return ""
    }
    
    func findFfmpegPath() -> String {
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["ffmpeg"]
        
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        whichProcess.standardError = Pipe()
        
        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            
            if whichProcess.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    addLog("Found ffmpeg at: \(path)")
                    return path
                }
            }
        } catch {
            addLog("Error running which for ffmpeg: \(error)")
        }
        
        let possiblePaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                addLog("Found ffmpeg at: \(path)")
                return path
            }
        }
        
        addLog("ffmpeg not found in any standard location")
        return ""
    }
    
    private func expandPath(_ path: String) -> String {
        return (path as NSString).expandingTildeInPath
    }
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"
        
        DispatchQueue.main.async {
            self.downloadLogs.append(logEntry)
            if self.downloadLogs.count > 1000 {
                self.downloadLogs.removeFirst(100)
            }
        }
    }
    
    func clearLogs() {
        DispatchQueue.main.async {
            self.downloadLogs.removeAll()
            self.rawOutput = ""
        }
    }
    
    
    private func canRemux(from sourceFormat: String, to targetFormat: String, videoCodec: String, audioCodec: String) -> Bool {
        let compatibilityMap: [String: [String: Set<String>]] = [
            "mp4": [
                "video": ["h264", "h265", "mpeg4", "av1"],
                "audio": ["aac", "mp3", "ac3"]
            ],
            "mkv": [
                "video": ["h264", "h265", "vp8", "vp9", "av1", "mpeg4"],
                "audio": ["aac", "mp3", "ac3", "dts", "flac", "vorbis", "opus"]
            ],
            "webm": [
                "video": ["vp8", "vp9", "av1"],
                "audio": ["vorbis", "opus"]
            ],
            "avi": [
                "video": ["h264", "mpeg4", "mjpeg"],
                "audio": ["mp3", "ac3", "pcm"]
            ]
        ]
        
        guard let targetFormats = compatibilityMap[targetFormat.lowercased()],
              let supportedVideoCodecs = targetFormats["video"],
              let supportedAudioCodecs = targetFormats["audio"] else {
            return false
        }
        
        let videoCompatible = supportedVideoCodecs.contains(videoCodec.lowercased()) ||
                             supportedVideoCodecs.contains(videoCodec.replacingOccurrences(of: "lib", with: ""))
        let audioCompatible = supportedAudioCodecs.contains(audioCodec.lowercased()) ||
                             supportedAudioCodecs.contains(audioCodec.replacingOccurrences(of: "lib", with: ""))
        
        return videoCompatible && audioCompatible
    }
    
    private func getMediaInfo(filePath: String) -> (videoCodec: String, audioCodec: String, container: String) {
        let ffmpegBasePath = settings?.customFfmpegPath.isEmpty == false ?
                            expandPath(settings!.customFfmpegPath) : findFfmpegPath()
        
        guard !ffmpegBasePath.isEmpty else {
            return ("unknown", "unknown", "unknown")
        }
        
        let ffprobePath = ffmpegBasePath.replacingOccurrences(of: "ffmpeg", with: "ffprobe")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "quiet",
            "-show_entries", "stream=codec_name",
            "-of", "csv=p=0",
            filePath
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let codecs = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
            
            let videoCodec = codecs.first ?? "unknown"
            let audioCodec = codecs.count > 1 ? codecs[1] : "unknown"
            let container = URL(fileURLWithPath: filePath).pathExtension.lowercased()
            
            addLog("Media info - Video: \(videoCodec), Audio: \(audioCodec), Container: \(container)")
            return (videoCodec, audioCodec, container)
        } catch {
            addLog("Failed to get media info: \(error)")
            return ("unknown", "unknown", "unknown")
        }
    }
    
    private func buildDownloadArguments(for url: String, settings: YtDlpSettings) -> [String] {
        var args: [String] = []
        
        let outputPath = settings.outputPath.isEmpty ? "~/Downloads" : settings.outputPath
        let expandedPath = expandPath(outputPath)
        
        args.append("-o")
        if settings.audioOnly || needsPostProcessing(settings) {
            args.append("\(expandedPath)/%(title)s_temp.%(ext)s")
        } else {
            args.append("\(expandedPath)/%(title)s.%(ext)s")
        }
        
        let ffmpegPath = settings.customFfmpegPath.isEmpty ? findFfmpegPath() : expandPath(settings.customFfmpegPath)
        if !ffmpegPath.isEmpty {
            args.append("--ffmpeg-location")
            args.append(ffmpegPath)
            addLog("Using ffmpeg at: \(ffmpegPath)")
        } else {
            addLog("⚠️ ffmpeg not found - audio extraction and conversion may not work")
        }
        
        if settings.enableVerboseLogging {
            args.append("--verbose")
        }
        
        if settings.audioOnly {
            args.append("--extract-audio")
            
            let audioFormat = mapAudioFormat(settings.audioFormat)
            args.append("--audio-format")
            args.append(audioFormat)
            
            if !settings.audioQuality.isEmpty {
                args.append("--audio-quality")
                args.append(settings.audioQuality + "K")
            }
            if settings.keepVideo {
                args.append("--keep-video")
            }
        } else {
            if settings.videoCodec == "auto" {
                if settings.quality != "best" {
                    args.append("--format")
                    args.append("best[height<=\(extractHeight(from: settings.quality))]/best")
                } else {
                    args.append("--format")
                    args.append("best")
                }
            } else {
                if settings.quality != "best" {
                    args.append("--format")
                    args.append("best[height<=\(extractHeight(from: settings.quality))]/best")
                } else {
                    args.append("--format")
                    args.append("best")
                }
                
                if settings.format != "best" || settings.videoCodec != "auto" || settings.forceConversion {
                    needsConversion = true
                    addLog("Will process to \(settings.format) after download")
                }
            }
        }
        
        // Subtitles
        if settings.downloadSubtitles {
            args.append("--write-subs")
            if !settings.subtitleLanguage.isEmpty {
                args.append("--sub-langs")
                args.append(settings.subtitleLanguage)
            }
            args.append("--sub-format")
            args.append(settings.subtitleFormat)
            
            if settings.embedSubs && !settings.audioOnly && !needsConversion {
                args.append("--embed-subs")
            }
        }
        
        if settings.writeAutoSubs {
            args.append("--write-auto-subs")
        }
        
        // Thumbnails
        if settings.downloadThumbnail {
            args.append("--write-thumbnail")
        }

        if settings.embedThumbnail && !needsConversion {
            args.append("--embed-thumbnail")
        }
        
        // Metadata
        if settings.writeDescription {
            args.append("--write-description")
        }
        if settings.writeInfoJson {
            args.append("--write-info-json")
        }
        
        // Playlist options
        if settings.noPlaylist {
            args.append("--no-playlist")
        }
        
        // Download limits
        if !settings.maxDownloads.isEmpty {
            args.append("--max-downloads")
            args.append(settings.maxDownloads)
        }
        
        // Rate limiting
        if !settings.rateLimit.isEmpty {
            args.append("--limit-rate")
            args.append(settings.rateLimit)
        }
        
        // Retries
        if !settings.retries.isEmpty {
            args.append("--retries")
            args.append(settings.retries)
        }
        
        // User agent
        if !settings.userAgent.isEmpty {
            args.append("--user-agent")
            args.append(settings.userAgent)
        }
        
        // Proxy
        if !settings.proxy.isEmpty {
            args.append("--proxy")
            args.append(settings.proxy)
        }
        
        // Cookies
        if !settings.cookieData.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let tempDir = FileManager.default.temporaryDirectory
            let cookieFileURL = tempDir.appendingPathComponent("cookies_\(UUID().uuidString).txt")
            
            do {
                try settings.cookieData.write(to: cookieFileURL, atomically: true, encoding: .utf8)
                args.append("--cookies")
                args.append(cookieFileURL.path)
                addLog("Created temporary cookie file: \(cookieFileURL.path)")
            } catch {
                addLog("Failed to write cookie file: \(error)")
            }
        }
        
        args.append("--newline")
        args.append("--progress")
        
        args.append("--print")
        args.append("after_move:filepath")
        
        args.append(url)
        
        if settings.logCommands {
            addLog("Download command: yt-dlp \(args.joined(separator: " "))")
        }
        
        return args
    }
    
    private func mapAudioFormat(_ format: String) -> String {
        switch format.lowercased() {
        case "ogg":
            return "vorbis"
        case "m4a":
            return "aac"
        default:
            return format
        }
    }
    
    private func needsPostProcessing(_ settings: YtDlpSettings) -> Bool {
        return settings.format != "best" ||
               settings.videoCodec != "auto" ||
               settings.forceConversion ||
               (settings.embedSubs && settings.downloadSubtitles) ||
               settings.embedThumbnail
    }
    
    private func extractHeight(from quality: String) -> String {
        if quality.contains("<=") {
            return quality.replacingOccurrences(of: "height<=", with: "")
        }
        return quality
    }
    
    private func processVideo(inputPath: String, settings: YtDlpSettings) {
        let ffmpegPath = settings.customFfmpegPath.isEmpty ? findFfmpegPath() : expandPath(settings.customFfmpegPath)
        
        guard !ffmpegPath.isEmpty && FileManager.default.fileExists(atPath: ffmpegPath) else {
            addLog("❌ Cannot process: ffmpeg not found")
            DispatchQueue.main.async {
                self.statusMessage = "Processing failed: ffmpeg not found"
                self.isDownloading = false
            }
            return
        }
        
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputPath = inputURL.deletingPathExtension()
            .appendingPathExtension(settings.format).path
        
        // Get media information
        let mediaInfo = getMediaInfo(filePath: inputPath)
        let canRemuxDirectly = canRemux(
            from: mediaInfo.container,
            to: settings.format,
            videoCodec: mediaInfo.videoCodec,
            audioCodec: mediaInfo.audioCodec
        ) && settings.videoCodec == "auto"
        
        if canRemuxDirectly && !settings.forceConversion {
            addLog("✅ Compatible formats detected - remuxing without re-encoding")
            remuxVideo(inputPath: inputPath, outputPath: outputPath, settings: settings)
        } else {
            addLog("⚙️ Incompatible formats or specific codec requested - re-encoding")
            convertVideo(inputPath: inputPath, outputPath: outputPath, settings: settings)
        }
    }
    
    private func remuxVideo(inputPath: String, outputPath: String, settings: YtDlpSettings) {
        let ffmpegPath = settings.customFfmpegPath.isEmpty ? findFfmpegPath() : expandPath(settings.customFfmpegPath)
        
        guard !ffmpegPath.isEmpty else {
            return
        }
        
        addLog("🚀 Remuxing (no re-encoding): \(inputPath) -> \(outputPath)")
        
        DispatchQueue.main.async {
            self.statusMessage = "Remuxing to \(settings.format) (preserving quality)..."
            self.progress = 0.5 // Remuxing is usually very fast
        }
        
        var args = ["-i", inputPath]
        
        args.append(contentsOf: ["-c", "copy"])
        
        if settings.embedSubs && settings.downloadSubtitles {
            if settings.format.lowercased() == "mp4" {
                args.append(contentsOf: ["-c:s", "mov_text"])
            } else {
                args.append(contentsOf: ["-c:s", "copy"])
            }
        }

        args.append(contentsOf: ["-map", "0"])
        
        args.append(contentsOf: ["-avoid_negative_ts", "make_zero"])
        
        args.append("-y")
        args.append(outputPath)
        
        addLog("Remux command: ffmpeg \(args.joined(separator: " "))")
        
        let remuxProcess = Process()
        remuxProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
        remuxProcess.arguments = args
        
        let pipe = Pipe()
        remuxProcess.standardOutput = pipe
        remuxProcess.standardError = pipe
        
        pipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if !data.isEmpty {
                let output = String(data: data, encoding: .utf8) ?? ""
                self.addLog("ffmpeg: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        
        do {
            try remuxProcess.run()
            remuxProcess.waitUntilExit()
            
            pipe.fileHandleForReading.readabilityHandler = nil
            
            DispatchQueue.main.async {
                if remuxProcess.terminationStatus == 0 {
                    self.addLog("✅ Remux completed: \(outputPath)")
                    self.statusMessage = "Remuxing completed successfully!"
                    self.progress = 1.0
                    
                    if settings.deleteOriginal {
                        do {
                            try FileManager.default.removeItem(atPath: inputPath)
                            self.addLog("Deleted original file: \(inputPath)")
                        } catch {
                            self.addLog("Failed to delete original file: \(error)")
                        }
                    }
                } else {
                    self.addLog("❌ Remux failed with exit code \(remuxProcess.terminationStatus)")
                    self.statusMessage = "Remuxing failed - falling back to conversion"
                    self.convertVideo(inputPath: inputPath, outputPath: outputPath, settings: settings)
                    return
                }
                self.isDownloading = false
            }
        } catch {
            addLog("Failed to start remux: \(error)")
            DispatchQueue.main.async {
                self.statusMessage = "Remuxing failed - falling back to conversion"
                self.convertVideo(inputPath: inputPath, outputPath: outputPath, settings: settings)
            }
        }
    }
    
    private func convertVideo(inputPath: String, outputPath: String, settings: YtDlpSettings) {
        let ffmpegPath = settings.customFfmpegPath.isEmpty ? findFfmpegPath() : expandPath(settings.customFfmpegPath)
        
        guard !ffmpegPath.isEmpty else {
            return
        }
        
        addLog("⚙️ Converting with re-encoding: \(inputPath) -> \(outputPath)")
        
        DispatchQueue.main.async {
            self.statusMessage = "Converting to \(settings.format) (re-encoding)..."
            self.progress = 0.0
        }
        
        var args = ["-i", inputPath]
        
        // Video codec selection
        if settings.videoCodec == "auto" {
            switch settings.format.lowercased() {
            case "mp4":
                args.append(contentsOf: ["-c:v", "libx264"])
            case "mkv":
                args.append(contentsOf: ["-c:v", "libx264"])
            case "webm":
                args.append(contentsOf: ["-c:v", "libvpx-vp9"])
            default:
                args.append(contentsOf: ["-c:v", "libx264"])
            }
        } else {
            switch settings.videoCodec {
            case "h264":
                args.append(contentsOf: ["-c:v", "libx264"])
            case "h265":
                args.append(contentsOf: ["-c:v", "libx265"])
            case "vp9":
                args.append(contentsOf: ["-c:v", "libvpx-vp9"])
            case "av01":
                args.append(contentsOf: ["-c:v", "libaom-av1"])
            default:
                args.append(contentsOf: ["-c:v", "libx264"])
            }
        }
        
        // Audio codec selection
        switch settings.audioCodec {
        case "aac":
            args.append(contentsOf: ["-c:a", "aac"])
        case "mp3":
            args.append(contentsOf: ["-c:a", "libmp3lame"])
        case "ogg":
            args.append(contentsOf: ["-c:a", "libvorbis"])
        default:
            args.append(contentsOf: ["-c:a", "aac"])
        }
        
        // Quality settings
        if !settings.audioQuality.isEmpty {
            args.append(contentsOf: ["-b:a", "\(settings.audioQuality)k"])
        }
        
        // Progress reporting
        args.append(contentsOf: ["-progress", "pipe:1"])
        args.append(contentsOf: ["-y"]) // Overwrite output file
        args.append(outputPath)
        
        addLog("Conversion command: ffmpeg \(args.joined(separator: " "))")
        
        let conversionProcess = Process()
        conversionProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
        conversionProcess.arguments = args
        
        let pipe = Pipe()
        conversionProcess.standardOutput = pipe
        conversionProcess.standardError = pipe
        
        pipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if !data.isEmpty {
                let output = String(data: data, encoding: .utf8) ?? ""
                self.parseConversionOutput(output)
            }
        }
        
        do {
            try conversionProcess.run()
            conversionProcess.waitUntilExit()
            
            pipe.fileHandleForReading.readabilityHandler = nil
            
            DispatchQueue.main.async {
                if conversionProcess.terminationStatus == 0 {
                    self.addLog("✅ Conversion completed: \(outputPath)")
                    self.statusMessage = "Conversion completed successfully!"
                    self.progress = 1.0
                    
                    // Delete original if requested
                    if settings.deleteOriginal {
                        do {
                            try FileManager.default.removeItem(atPath: inputPath)
                            self.addLog("Deleted original file: \(inputPath)")
                        } catch {
                            self.addLog("Failed to delete original file: \(error)")
                        }
                    }
                } else {
                    self.addLog("❌ Conversion failed with exit code \(conversionProcess.terminationStatus)")
                    self.statusMessage = "Conversion failed"
                }
                self.isDownloading = false
            }
        } catch {
            addLog("Failed to start conversion: \(error)")
            DispatchQueue.main.async {
                self.statusMessage = "Failed to start conversion: \(error.localizedDescription)"
                self.isDownloading = false
            }
        }
    }
    
    private func parseConversionOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("out_time_ms=") {
                // Parse ffmpeg progress - this is basic, could be enhanced
                addLog("ffmpeg: \(line)")
            } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                addLog("ffmpeg: \(line)")
            }
        }
    }
    
    func downloadVideo(url: String, settings: YtDlpSettings) {
        guard !isDownloading else { return }
        
        self.settings = settings
        self.needsConversion = false
        self.downloadedFilePath = ""
        
        let ytdlpPath = settings.customYtdlpPath.isEmpty ? findYTdlpPath() : expandPath(settings.customYtdlpPath)
        
        guard !ytdlpPath.isEmpty else {
            DispatchQueue.main.async {
                self.statusMessage = "Error: yt-dlp not found. Please install it via Homebrew: brew install yt-dlp"
                self.isDownloading = false
            }
            addLog("Error: yt-dlp not found")
            return
        }
        
        guard FileManager.default.fileExists(atPath: ytdlpPath) else {
            DispatchQueue.main.async {
                self.statusMessage = "Error: yt-dlp not found at path: \(ytdlpPath)"
                self.isDownloading = false
            }
            addLog("Error: yt-dlp not found at path: \(ytdlpPath)")
            return
        }
        
        let args = buildDownloadArguments(for: url, settings: settings)
        
        DispatchQueue.main.async {
            self.isDownloading = true
            self.statusMessage = "Starting download..."
            self.progress = 0.0
            self.downloadSpeed = ""
            self.eta = ""
        }
        
        addLog("Starting download for URL: \(url)")
        addLog("Using yt-dlp at: \(ytdlpPath)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.process = Process()
            self.process?.executableURL = URL(fileURLWithPath: ytdlpPath)
            self.process?.arguments = args
            
            let pipe = Pipe()
            self.process?.standardOutput = pipe
            self.process?.standardError = pipe
            
            pipe.fileHandleForReading.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                if !data.isEmpty {
                    let output = String(data: data, encoding: .utf8) ?? ""
                    self.parseOutput(output)
                }
            }
            
            do {
                try self.process?.run()
                self.addLog("Process started successfully")
                self.process?.waitUntilExit()
                
                pipe.fileHandleForReading.readabilityHandler = nil
                
                let exitCode = self.process?.terminationStatus ?? -1
                if exitCode == 0 {
                    self.addLog("Download completed successfully")
                    
                    // Check if we need processing
                    if self.needsConversion && !self.downloadedFilePath.isEmpty {
                        self.processVideo(inputPath: self.downloadedFilePath, settings: settings)
                    } else {
                        DispatchQueue.main.async {
                            self.statusMessage = "Download completed successfully!"
                            self.progress = 1.0
                            self.isDownloading = false
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.statusMessage = "Download failed with exit code \(exitCode)"
                        self.progress = 0.0
                        self.isDownloading = false
                    }
                    self.addLog("Download failed with exit code \(exitCode)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Failed to start download: \(error.localizedDescription)"
                    self.isDownloading = false
                    self.progress = 0.0
                    self.downloadSpeed = ""
                    self.eta = ""
                }
                self.addLog("Failed to start download: \(error.localizedDescription)")
            }
        }
    }
    
    private func parseOutput(_ output: String) {
        DispatchQueue.main.async {
            if self.settings?.showRawOutput == true {
                self.rawOutput += output
            }
        }
        
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            
            if settings?.enableVerboseLogging == true {
                addLog("Raw output: \(trimmedLine)")
            }
            
            if !trimmedLine.hasPrefix("[") && trimmedLine.contains("/") &&
               (trimmedLine.hasSuffix(".mp4") || trimmedLine.hasSuffix(".mkv") ||
                trimmedLine.hasSuffix(".webm") || trimmedLine.hasSuffix(".avi") ||
                trimmedLine.hasSuffix(".m4a") || trimmedLine.hasSuffix(".mp3")) {
                downloadedFilePath = trimmedLine
                addLog("Downloaded file: \(trimmedLine)")
            }
            
            if trimmedLine.hasPrefix("[download]") {
                parseDownloadLine(trimmedLine)
            } else if trimmedLine.hasPrefix("[info]") {
                DispatchQueue.main.async {
                    self.statusMessage = trimmedLine
                }
            } else if trimmedLine.hasPrefix("[youtube]") {
                DispatchQueue.main.async {
                    self.statusMessage = trimmedLine
                }
            } else if trimmedLine.contains("ERROR") {
                DispatchQueue.main.async {
                    self.statusMessage = "❌ \(trimmedLine)"
                }
            } else if trimmedLine.contains("WARNING") {
                DispatchQueue.main.async {
                    self.statusMessage = "⚠️ \(trimmedLine)"
                }
            } else {
                DispatchQueue.main.async {
                    self.statusMessage = trimmedLine
                }
            }
        }
    }
    
    private func parseDownloadLine(_ line: String) {
        if settings?.enableVerboseLogging == true {
            addLog("Parsing download line: \(line)")
        }
        
        let progressPatterns = [
            #"\[download\]\s+(\d+\.?\d*)%"#,                    // [download]  45.2%
            #"\[download\]\s+(\d+\.?\d*)%\s+of"#,               // [download]  45.2% of
            #"(\d+\.?\d*)%\s+of\s+[\d\.\w\s]+"#,                // 45.2% of 123.45MiB
            #"(\d+\.?\d*)%"#                                     // Simple 45.2%
        ]
        
        var foundProgress = false
        for pattern in progressPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                
                if let percentRange = Range(match.range(at: 1), in: line) {
                    let percentStr = String(line[percentRange])
                    if let percent = Double(percentStr) {
                        DispatchQueue.main.async {
                            self.progress = percent / 100.0
                        }
                        addLog("✅ Progress updated: \(percent)%")
                        foundProgress = true
                        break
                    }
                }
            }
        }
        
        if !foundProgress {
            if let regex = try? NSRegularExpression(pattern: #"(\d+\.?\d*)%"#),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                
                if let percentRange = Range(match.range(at: 1), in: line) {
                    let percentStr = String(line[percentRange])
                    if let percent = Double(percentStr) {
                        DispatchQueue.main.async {
                            self.progress = percent / 100.0
                        }
                        addLog("✅ Progress (fallback): \(percent)%")
                        foundProgress = true
                    }
                }
            }
        }
        
        if !foundProgress && settings?.enableVerboseLogging == true {
            addLog("⚠️ Could not parse progress from: \(line)")
        }
        
        let speedPatterns = [
            #"(\d+\.?\d*\s*[KMG]iB/s)"#,                       // 1.2 MiB/s
            #"(\d+\.?\d*[KMG]B/s)"#,                           // 1.2 MB/s
            #"(\d+\.?\d*\s*[KMG]iB/s)"#,                       // 1.2MiB/s
            #"(\d+\.?\d*\s*kb/s)"#                             // 1200 kb/s
        ]
        
        for speedPattern in speedPatterns {
            if let regex = try? NSRegularExpression(pattern: speedPattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                
                if let speedRange = Range(match.range(at: 1), in: line) {
                    let speed = String(line[speedRange]).trimmingCharacters(in: .whitespaces)
                    DispatchQueue.main.async {
                        self.downloadSpeed = speed
                    }
                    if settings?.enableVerboseLogging == true {
                        addLog("Speed: \(speed)")
                    }
                    break
                }
            }
        }
        
        let etaPatterns = [
            #"ETA\s+(\d+:\d+:\d+)"#,                           // ETA 00:01:23
            #"ETA\s+(\d+:\d+)"#,                               // ETA 01:23
            #"(\d+:\d+:\d+)\s+ETA"#,                           // 00:01:23 ETA
            #"(\d+:\d+)\s+ETA"#                                // 01:23 ETA
        ]
        
        for etaPattern in etaPatterns {
            if let regex = try? NSRegularExpression(pattern: etaPattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                
                if let etaRange = Range(match.range(at: 1), in: line) {
                    let eta = String(line[etaRange])
                    DispatchQueue.main.async {
                        self.eta = "ETA \(eta)"
                    }
                    if settings?.enableVerboseLogging == true {
                        addLog("ETA: \(eta)")
                    }
                    break
                }
            }
        }
        
        DispatchQueue.main.async {
            self.statusMessage = line
        }
    }
    
    func cancelDownload() {
        process?.terminate()
        addLog("Download cancelled by user")
        DispatchQueue.main.async {
            self.isDownloading = false
            self.statusMessage = "Download cancelled"
            self.progress = 0.0
            self.downloadSpeed = ""
            self.eta = ""
        }
    }
}
