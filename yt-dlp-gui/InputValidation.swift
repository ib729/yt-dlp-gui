import Foundation

struct InputValidation {
    /// Validates that a string contains only digits
    static func isNumeric(_ string: String) -> Bool {
        guard !string.isEmpty else { return false }
        return string.allSatisfy { $0.isNumber }
    }
    
    /// Validates that a string is a positive integer
    static func isPositiveInteger(_ string: String) -> Bool {
        guard isNumeric(string) else { return false }
        guard let value = Int(string) else { return false }
        return value > 0
    }
    
    /// Validates URL format
    static func isValidURL(_ string: String) -> Bool {
        guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        guard let url = URL(string: string) else {
            return false
        }
        
        // Must have a scheme (http, https, etc.)
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        
        // Allow common schemes
        let allowedSchemes = ["http", "https", "ftp", "ftps"]
        guard allowedSchemes.contains(scheme) else {
            return false
        }
        
        // Must have a host
        return url.host != nil
    }
    
    /// Validates rate limit format (e.g., "1M", "500K")
    static func isValidRateLimit(_ string: String) -> Bool {
        guard !string.isEmpty else { return true } // Empty is allowed
        
        let pattern = "^\\d+(\\.\\d+)?[KMG]?$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return false
        }
        
        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }
    
    /// Validates and sanitizes file paths
    static func isValidPath(_ path: String) -> Bool {
        guard !path.isEmpty else { return true }
        
        let expanded = (path as NSString).expandingTildeInPath
        
        // Check for path traversal attempts
        if path.contains("..") {
            return false
        }
        
        // Check if path starts with allowed prefixes
        let allowedPrefixes = ["/Users/", "/Volumes/", "~/"]
        return allowedPrefixes.contains(where: { path.hasPrefix($0) || expanded.hasPrefix($0) })
    }
    
    /// Sanitizes a numeric input by removing non-digit characters
    static func sanitizeNumeric(_ string: String) -> String {
        return string.filter { $0.isNumber }
    }
    
    /// Validates audio quality is within acceptable range
    static func isValidAudioQuality(_ quality: String) -> Bool {
        guard !quality.isEmpty else { return true }
        guard let value = Int(quality) else { return false }
        return value >= 32 && value <= 320
    }
    
    /// Validates max downloads is reasonable
    static func isValidMaxDownloads(_ max: String) -> Bool {
        guard !max.isEmpty else { return true }
        guard let value = Int(max) else { return false }
        return value > 0 && value <= 1000
    }
    
    /// Validates retries count
    static func isValidRetries(_ retries: String) -> Bool {
        guard !retries.isEmpty else { return true }
        guard let value = Int(retries) else { return false }
        return value >= 0 && value <= 100
    }
}

