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
    private var ffmpegEncoderCache: [String: Set<String>] = [:]
    private var downloadedFilesForSession: [String] = []
    private var pendingProcessingFiles: [String] = []
    
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

    private func availableEncoders(for ffmpegPath: String) -> Set<String> {
        let canonicalPath = URL(fileURLWithPath: ffmpegPath).standardizedFileURL.path
        if let cached = ffmpegEncoderCache[canonicalPath] {
            return cached
        }

        let encoderProcess = Process()
        encoderProcess.executableURL = URL(fileURLWithPath: canonicalPath)
        encoderProcess.arguments = ["-hide_banner", "-encoders"]

        let outputPipe = Pipe()
        encoderProcess.standardOutput = outputPipe
        encoderProcess.standardError = Pipe()

        do {
            try encoderProcess.run()
            encoderProcess.waitUntilExit()
        } catch {
            addLog("Failed to query ffmpeg encoders: \(error)")
            ffmpegEncoderCache[canonicalPath] = []
            return []
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            ffmpegEncoderCache[canonicalPath] = []
            return []
        }

        let encoders = output.split(separator: "\n").reduce(into: Set<String>()) { result, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }

            let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })
            if tokens.count >= 2 {
                result.insert(String(tokens[1]))
            }
        }

        ffmpegEncoderCache[canonicalPath] = encoders
        return encoders
    }

    private func ffmpegSupportsEncoder(_ encoder: String, ffmpegPath: String) -> Bool {
        return availableEncoders(for: ffmpegPath).contains(encoder)
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
    
    private func buildDownloadArguments(for urls: [String], settings: YtDlpSettings) -> [String] {
        var args: [String] = []
        
        let outputPath = settings.outputPath.isEmpty ? "~/Downloads" : settings.outputPath
        let expandedPath = expandPath(outputPath)
        
        args.append("-o")
        args.append("\(expandedPath)/%(title)s.%(ext)s")

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
        
        if settings.subtitleOnly {
            args.append("--skip-download")
        }

        if settings.audioOnly && !settings.subtitleOnly {
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
        } else if !settings.subtitleOnly {
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
                    addLog("Will verify downloaded media against requested format/codec")
                }
            }
        }
        
        // Subtitles
        if settings.downloadSubtitles {
            args.append("--write-subs")
            let trimmedSubtitleLang = settings.subtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSubtitleLang.isEmpty {
                args.append("--sub-langs")
                args.append(trimmedSubtitleLang)
            } else if settings.writeAutoSubs {
                args.append("--sub-langs")
                args.append("all")
            }
            args.append("--sub-format")
            args.append(settings.subtitleFormat)
            
            if settings.embedSubs && !settings.audioOnly && !needsConversion && !settings.subtitleOnly {
                args.append("--embed-subs")
            }
        }

        if settings.downloadSubtitles && settings.writeAutoSubs {
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
        if settings.useBrowserCookies {
            addLog("Using cookies from browser: \(settings.browserCookieSource)")
            args.append("--cookies-from-browser")
            args.append(settings.browserCookieSource)
        }

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
        
        for url in urls {
            args.append(url)
        }
        
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
        case "opus":
            return "opus"
        default:
            return format
        }
    }

    private func mapAudioCodec(for format: String) -> String {
        switch format.lowercased() {
        case "mp3":
            return "mp3"
        case "aac", "m4a":
            return "aac"
        case "ogg":
            return "ogg"
        case "opus":
            return "opus"
        case "flac":
            return "flac"
        case "wav":
            return "pcm_s16le"
        default:
            return "aac"
        }
    }

    private func finalOutputPath(for path: String, desiredExtension: String? = nil) -> String {
        let inputURL = URL(fileURLWithPath: path)
        var baseName = inputURL.deletingPathExtension().lastPathComponent
        if baseName.hasSuffix("_temp") {
            baseName = String(baseName.dropLast(5))
        }

        let resolvedExtension: String
        if let desiredExtension, !desiredExtension.isEmpty, desiredExtension != "best" {
            resolvedExtension = desiredExtension
        } else {
            resolvedExtension = inputURL.pathExtension
        }

        let directoryURL = inputURL.deletingLastPathComponent()
        let finalURL = directoryURL
            .appendingPathComponent(baseName)
            .appendingPathExtension(resolvedExtension)

        return finalURL.path
    }

    private func renameTempFileIfNeeded(at path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let directoryURL = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let tempStem = baseName

        let finalPath = finalOutputPath(for: path)
        guard finalPath != path else {
            return path
        }

        do {
            if FileManager.default.fileExists(atPath: finalPath) {
                try FileManager.default.removeItem(atPath: finalPath)
            }
            try FileManager.default.moveItem(atPath: path, toPath: finalPath)
            addLog("Renamed temporary file to final name: \(finalPath)")

            cleanupAssociatedTempFiles(finalPath: finalPath, originalTempStem: tempStem, directory: directoryURL)

            return finalPath
        } catch {
            addLog("Failed to rename temporary file: \(error)")
            return path
        }
    }

    private func finalizeFileWithoutProcessing(at path: String) -> String {
        guard !path.isEmpty else {
            return path
        }

        let finalPath = renameTempFileIfNeeded(at: path)
        cleanupSidecarFiles(for: finalPath)
        addLog("✅ No conversion needed: \(finalPath)")
        return finalPath
    }

    private func finalizePendingFilesWithoutProcessing(successMessage: String) {
        var lastFinalPath = ""

        for path in pendingProcessingFiles {
            let finalPath = finalizeFileWithoutProcessing(at: path)
            lastFinalPath = finalPath
        }

        pendingProcessingFiles.removeAll()
        downloadedFilesForSession.removeAll()
        downloadedFilePath = lastFinalPath

        DispatchQueue.main.async {
            self.statusMessage = successMessage
            self.progress = 1.0
            self.isDownloading = false
        }
    }

    private func processNextPendingFile(settings: YtDlpSettings, successMessage: String) {
        guard let path = pendingProcessingFiles.first else {
            pendingProcessingFiles.removeAll()
            downloadedFilesForSession.removeAll()
            DispatchQueue.main.async {
                self.statusMessage = successMessage
                self.progress = 1.0
                self.isDownloading = false
            }
            return
        }

        pendingProcessingFiles.removeFirst()

        processDownloadedFile(at: path, settings: settings) { success, errorMessage, finalPath in
            if success {
                if let finalPath {
                    self.downloadedFilePath = finalPath
                }
                self.processNextPendingFile(settings: settings, successMessage: successMessage)
            } else {
                self.pendingProcessingFiles.removeAll()
                DispatchQueue.main.async {
                    self.statusMessage = errorMessage ?? "Processing failed"
                    self.progress = 0.0
                    self.isDownloading = false
                }
            }
        }
    }

    private func cleanupAssociatedTempFiles(finalPath: String, originalTempStem: String? = nil, directory: URL? = nil) {
        let finalURL = URL(fileURLWithPath: finalPath)
        let directoryURL = directory ?? finalURL.deletingLastPathComponent()
        let finalStem = finalURL.deletingPathExtension().lastPathComponent
        let tempStem = originalTempStem ?? "\(finalStem)_temp"

        renameAssociatedTempFiles(tempStem: tempStem, finalStem: finalStem, directory: directoryURL)
    }

    private func renameAssociatedTempFiles(tempStem: String, finalStem: String, directory: URL) {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return
        }

        for name in items {
            guard name.hasPrefix(tempStem) else { continue }

            let suffixIndex = name.index(name.startIndex, offsetBy: tempStem.count)
            let suffix = name[suffixIndex...]
            let candidateName = finalStem + suffix

            let sanitizedName = candidateName.replacingOccurrences(of: "_temp.", with: ".")

            guard sanitizedName != name else { continue }

            let oldPath = directory.appendingPathComponent(name).path
            let newPath = directory.appendingPathComponent(sanitizedName).path

            if fileManager.fileExists(atPath: oldPath) {
                do {
                    if fileManager.fileExists(atPath: newPath) {
                        try fileManager.removeItem(atPath: newPath)
                    }
                    try fileManager.moveItem(atPath: oldPath, toPath: newPath)
                    addLog("Renamed associated temp file: \(sanitizedName)")
                } catch {
                    addLog("Failed to rename associated temp file \(name): \(error)")
                }
            }
        }
    }

    private func recordDownloadedFile(path: String) {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else { return }

        downloadedFilePath = normalizedPath

        if !downloadedFilesForSession.contains(normalizedPath) {
            downloadedFilesForSession.append(normalizedPath)
            addLog("Downloaded file: \(normalizedPath)")
        }
    }

    private func cleanupSidecarFiles(for outputPath: String) {
        let baseURL = URL(fileURLWithPath: outputPath).deletingPathExtension()
        let descriptionURL = baseURL.appendingPathExtension("description")

        guard FileManager.default.fileExists(atPath: descriptionURL.path) else { return }

        do {
            let data = try Data(contentsOf: descriptionURL)
            let contents = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            if contents.isEmpty {
                try FileManager.default.removeItem(at: descriptionURL)
                addLog("Removed empty description file: \(descriptionURL.path)")
            }
        } catch {
            addLog("Failed to inspect description file: \(error)")
        }
    }
    
    private func makeTemporaryPath(for path: String, suffix: String) -> String {
        let originalURL = URL(fileURLWithPath: path)
        let directoryURL = originalURL.deletingLastPathComponent()
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let extensionName = originalURL.pathExtension

        func buildURL(with base: String) -> URL {
            var url = directoryURL.appendingPathComponent(base)
            if !extensionName.isEmpty {
                url = url.appendingPathExtension(extensionName)
            }
            return url
        }

        var candidateBase = baseName + suffix
        var candidateURL = buildURL(with: candidateBase)
        var counter = 1
        let fileManager = FileManager.default

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateBase = baseName + suffix + "-\(counter)"
            candidateURL = buildURL(with: candidateBase)
            counter += 1
        }

        return candidateURL.path
    }

    private func needsPostProcessing(_ settings: YtDlpSettings) -> Bool {
        return settings.format != "best" ||
               settings.videoCodec != "auto" ||
               settings.forceConversion ||
               (settings.embedSubs && settings.downloadSubtitles) ||
               settings.embedThumbnail
    }

    private func canonicalVideoCodecName(_ codec: String) -> String {
        let lowercased = codec.lowercased()

        if lowercased.hasPrefix("avc") || lowercased == "h264" {
            return "h264"
        }
        if lowercased == "hevc" || lowercased == "h265" || lowercased.hasPrefix("hev") {
            return "h265"
        }
        if lowercased.hasPrefix("vp09") || lowercased == "vp9" {
            return "vp9"
        }
        if lowercased.hasPrefix("av01") || lowercased == "av1" {
            return "av1"
        }
        if lowercased.hasPrefix("vp8") {
            return "vp8"
        }

        return lowercased
    }

    private func requestedVideoCodecValue(for codecSetting: String) -> String? {
        switch codecSetting {
        case "auto":
            return nil
        case "h264":
            return "h264"
        case "h265":
            return "h265"
        case "vp9":
            return "vp9"
        case "av01":
            return "av1"
        default:
            return codecSetting.lowercased()
        }
    }

    private func videoCodecMatchesRequest(actualCodec: String, requestedSetting: String) -> Bool {
        guard let requested = requestedVideoCodecValue(for: requestedSetting) else {
            return true
        }

        return canonicalVideoCodecName(actualCodec) == requested
    }

    private func extractHeight(from quality: String) -> String {
        if quality.contains("<=") {
            return quality.replacingOccurrences(of: "height<=", with: "")
        }
        return quality
    }
    
    private func processDownloadedFile(at inputPath: String, settings: YtDlpSettings, completion: @escaping (Bool, String?, String?) -> Void) {
        let ffmpegPath = settings.customFfmpegPath.isEmpty ? findFfmpegPath() : expandPath(settings.customFfmpegPath)
        
        guard !ffmpegPath.isEmpty && FileManager.default.fileExists(atPath: ffmpegPath) else {
            addLog("❌ Cannot process: ffmpeg not found")
            completion(false, "Processing failed: ffmpeg not found", nil)
            return
        }
        
        let targetExtension = settings.format == "best" ? nil : settings.format
        let outputPath = finalOutputPath(for: inputPath, desiredExtension: targetExtension)
        
        // Get media information
        let mediaInfo = getMediaInfo(filePath: inputPath)
        let requestedCodecMatches = videoCodecMatchesRequest(actualCodec: mediaInfo.videoCodec, requestedSetting: settings.videoCodec)
        let targetFormat = settings.format.lowercased()
        let sourceContainer = mediaInfo.container.lowercased()
        let containerMatches = targetFormat == "best" || targetFormat == sourceContainer

        if requestedCodecMatches && containerMatches && !settings.forceConversion {
            addLog("✅ Requested codec already present - skipping additional processing")
            let finalPath = finalizeFileWithoutProcessing(at: inputPath)
            completion(true, nil, finalPath)
            return
        }

        let canRemuxDirectly = requestedCodecMatches &&
            targetFormat != "best" &&
            canRemux(
                from: mediaInfo.container,
                to: settings.format,
                videoCodec: mediaInfo.videoCodec,
                audioCodec: mediaInfo.audioCodec
            )

        if canRemuxDirectly && !settings.forceConversion {
            addLog("✅ Compatible formats detected - remuxing without re-encoding")
            remuxVideo(inputPath: inputPath, outputPath: outputPath, settings: settings, completion: completion)
            return
        }

        if !requestedCodecMatches {
            addLog("⚙️ Downloaded codec \(mediaInfo.videoCodec) does not match requested \(settings.videoCodec) - re-encoding")
        } else if settings.forceConversion {
            addLog("⚙️ Forced conversion requested - re-encoding")
        } else {
            addLog("⚙️ Cannot remux from \(mediaInfo.container) to \(settings.format) without re-encoding")
        }

        convertVideo(inputPath: inputPath, outputPath: outputPath, settings: settings, completion: completion)
    }
    
    private func remuxVideo(inputPath: String, outputPath: String, settings: YtDlpSettings, completion: @escaping (Bool, String?, String?) -> Void) {
        let ffmpegPath = settings.customFfmpegPath.isEmpty ? findFfmpegPath() : expandPath(settings.customFfmpegPath)

        guard !ffmpegPath.isEmpty else {
            completion(false, "Remux failed: ffmpeg not found", nil)
            return
        }

        addLog("🚀 Remuxing (no re-encoding): \(inputPath) -> \(outputPath)")

        DispatchQueue.main.async {
            self.statusMessage = "Remuxing to \(settings.format) (preserving quality)..."
            self.progress = max(self.progress, 0.5)
        }

        var args = ["-i", inputPath]

        let tempOutputPath = outputPath == inputPath ? makeTemporaryPath(for: outputPath, suffix: ".remux") : outputPath
        
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
        args.append(tempOutputPath)
        
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

            if remuxProcess.terminationStatus == 0 {
                let finalPath: String

                if tempOutputPath != outputPath {
                    do {
                        if FileManager.default.fileExists(atPath: outputPath) {
                            try FileManager.default.removeItem(atPath: outputPath)
                        }
                        try FileManager.default.moveItem(atPath: tempOutputPath, toPath: outputPath)
                        finalPath = outputPath
                    } catch {
                        self.addLog("Failed to replace original during remux: \(error)")
                        try? FileManager.default.removeItem(atPath: tempOutputPath)
                        completion(false, "Failed to finalize remuxed file", nil)
                        return
                    }
                } else {
                    finalPath = outputPath
                }

                self.addLog("✅ Remux completed: \(finalPath)")
                self.downloadedFilePath = finalPath
                self.cleanupAssociatedTempFiles(finalPath: finalPath)
                self.cleanupSidecarFiles(for: finalPath)
                DispatchQueue.main.async {
                    self.statusMessage = "Remuxing completed successfully!"
                    self.progress = max(self.progress, 0.85)
                }

                if settings.deleteOriginal && inputPath != finalPath {
                    do {
                        try FileManager.default.removeItem(atPath: inputPath)
                        self.addLog("Deleted original file: \(inputPath)")
                    } catch {
                        self.addLog("Failed to delete original file: \(error)")
                    }
                }

                completion(true, nil, finalPath)
            } else {
                self.addLog("❌ Remux failed with exit code \(remuxProcess.terminationStatus)")
                DispatchQueue.main.async {
                    self.statusMessage = "Remuxing failed - falling back to conversion"
                }
                if tempOutputPath != outputPath {
                    try? FileManager.default.removeItem(atPath: tempOutputPath)
                }
                self.convertVideo(inputPath: inputPath, outputPath: outputPath, settings: settings, completion: completion)
            }
        } catch {
            addLog("Failed to start remux: \(error)")
            DispatchQueue.main.async {
                self.statusMessage = "Remuxing failed - falling back to conversion"
            }
            if tempOutputPath != outputPath {
                try? FileManager.default.removeItem(atPath: tempOutputPath)
            }
            self.convertVideo(inputPath: inputPath, outputPath: outputPath, settings: settings, completion: completion)
        }
    }
    
    private func convertVideo(inputPath: String, outputPath: String, settings: YtDlpSettings, completion: @escaping (Bool, String?, String?) -> Void) {
        let ffmpegPath = settings.customFfmpegPath.isEmpty ? findFfmpegPath() : expandPath(settings.customFfmpegPath)
        
        guard !ffmpegPath.isEmpty else {
            completion(false, "Conversion failed: ffmpeg not found", nil)
            return
        }
        
        addLog("⚙️ Converting with re-encoding: \(inputPath) -> \(outputPath)")
        
        DispatchQueue.main.async {
            self.statusMessage = "Converting to \(settings.format) (re-encoding)..."
            self.progress = 0.0
        }
        
        var args = ["-i", inputPath]
        let tempOutputPath = outputPath == inputPath ? makeTemporaryPath(for: outputPath, suffix: ".converted") : outputPath

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
                if ffmpegSupportsEncoder("libsvtav1", ffmpegPath: ffmpegPath) {
                    args.append(contentsOf: ["-c:v", "libsvtav1"])
                    args.append(contentsOf: ["-preset", "6"])
                    addLog("Using libsvtav1 encoder for AV1 re-encode (preset 6)")
                } else {
                    addLog("libsvtav1 encoder not available - falling back to libaom-av1")
                    args.append(contentsOf: ["-c:v", "libaom-av1"])
                }
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
        case "ogg", "vorbis":
            args.append(contentsOf: ["-c:a", "libvorbis"])
        case "opus":
            args.append(contentsOf: ["-c:a", "libopus"])
        case "flac":
            args.append(contentsOf: ["-c:a", "flac"])
        case "pcm_s16le", "wav":
            args.append(contentsOf: ["-c:a", "pcm_s16le"])
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
        args.append(tempOutputPath)
        
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

            if conversionProcess.terminationStatus == 0 {
                let finalPath: String

                if tempOutputPath != outputPath {
                    do {
                        if FileManager.default.fileExists(atPath: outputPath) {
                            try FileManager.default.removeItem(atPath: outputPath)
                        }
                        try FileManager.default.moveItem(atPath: tempOutputPath, toPath: outputPath)
                        finalPath = outputPath
                    } catch {
                        self.addLog("Failed to replace original with converted file: \(error)")
                        try? FileManager.default.removeItem(atPath: tempOutputPath)
                        completion(false, "Failed to finalize converted file", nil)
                        return
                    }
                } else {
                    finalPath = outputPath
                }

                self.addLog("✅ Conversion completed: \(finalPath)")
                self.downloadedFilePath = finalPath
                self.cleanupAssociatedTempFiles(finalPath: finalPath)
                self.cleanupSidecarFiles(for: finalPath)
                DispatchQueue.main.async {
                    self.statusMessage = "Conversion completed successfully!"
                    self.progress = max(self.progress, 0.9)
                }

                if settings.deleteOriginal && inputPath != finalPath {
                    do {
                        try FileManager.default.removeItem(atPath: inputPath)
                        self.addLog("Deleted original file: \(inputPath)")
                    } catch {
                        self.addLog("Failed to delete original file: \(error)")
                    }
                }

                completion(true, nil, finalPath)
            } else {
                self.addLog("❌ Conversion failed with exit code \(conversionProcess.terminationStatus)")
                DispatchQueue.main.async {
                    self.statusMessage = "Conversion failed"
                }
                if tempOutputPath != outputPath {
                    try? FileManager.default.removeItem(atPath: tempOutputPath)
                }
                completion(false, "Conversion failed with exit code \(conversionProcess.terminationStatus)", nil)
            }
        } catch {
            addLog("Failed to start conversion: \(error)")
            DispatchQueue.main.async {
                self.statusMessage = "Failed to start conversion: \(error.localizedDescription)"
            }
            if tempOutputPath != outputPath {
                try? FileManager.default.removeItem(atPath: tempOutputPath)
            }
            completion(false, "Failed to start conversion: \(error.localizedDescription)", nil)
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
    
    func downloadVideos(urls: [String], settings: YtDlpSettings) {
        guard !isDownloading else { return }

        let sanitizedUrls = urls
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !sanitizedUrls.isEmpty else { return }

        let downloadCount = sanitizedUrls.count

        var effectiveSettings = settings
        effectiveSettings.audioCodec = mapAudioCodec(for: settings.audioFormat)

        self.settings = effectiveSettings
        self.needsConversion = false
        self.downloadedFilePath = ""
        self.downloadedFilesForSession.removeAll()
        self.pendingProcessingFiles.removeAll()

        let ytdlpPath = effectiveSettings.customYtdlpPath.isEmpty ?
            findYTdlpPath() : expandPath(effectiveSettings.customYtdlpPath)

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

        let args = buildDownloadArguments(for: sanitizedUrls, settings: effectiveSettings)
        
        DispatchQueue.main.async {
            self.isDownloading = true
            if downloadCount == 1 {
                self.statusMessage = "Starting download..."
            } else {
                self.statusMessage = "Starting downloads (\(downloadCount) items)..."
            }
            self.progress = 0.0
            self.downloadSpeed = ""
            self.eta = ""
        }
        
        if downloadCount == 1, let singleURL = sanitizedUrls.first {
            addLog("Starting download for URL: \(singleURL)")
        } else {
            addLog("Starting download batch for \(downloadCount) URLs")
            addLog("Targets: \(sanitizedUrls.joined(separator: ", "))")
        }
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

                    self.pendingProcessingFiles = self.downloadedFilesForSession
                    self.downloadedFilesForSession.removeAll()

                    let successMessage = "Download completed successfully!"

                    if self.needsConversion {
                        self.processNextPendingFile(settings: effectiveSettings, successMessage: successMessage)
                    } else {
                        self.finalizePendingFilesWithoutProcessing(successMessage: successMessage)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.statusMessage = "Download failed with exit code \(exitCode)"
                        self.progress = 0.0
                        self.isDownloading = false
                    }
                    self.pendingProcessingFiles.removeAll()
                    self.downloadedFilesForSession.removeAll()
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
                self.pendingProcessingFiles.removeAll()
                self.downloadedFilesForSession.removeAll()
                self.addLog("Failed to start download: \(error.localizedDescription)")
            }
        }
    }
    
    func downloadVideo(url: String, settings: YtDlpSettings) {
        downloadVideos(urls: [url], settings: settings)
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
            
            if let destinationRange = trimmedLine.range(of: "Destination:") {
                let rawPath = trimmedLine[destinationRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !rawPath.isEmpty {
                    recordDownloadedFile(path: rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
                    continue
                }
            }

            if let mergerRange = trimmedLine.range(of: "Merging formats into \"") {
                let tail = trimmedLine[mergerRange.upperBound...]
                if let closingQuoteIndex = tail.firstIndex(of: "\"") {
                    let rawPath = String(tail[..<closingQuoteIndex])
                    recordDownloadedFile(path: rawPath)
                    continue
                }
            }

            if !trimmedLine.hasPrefix("[") && trimmedLine.contains("/") {
                let lowercasedLine = trimmedLine.lowercased()
                let knownExtensions = [
                    "mp4", "mkv", "webm", "avi", "mov", "m4v",
                    "m4a", "mp3", "flac", "wav", "opus", "ogg",
                    "aac", "ts"
                ]

                if knownExtensions.contains(where: { lowercasedLine.hasSuffix(".\($0)") }) {
                    recordDownloadedFile(path: trimmedLine)
                }
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
