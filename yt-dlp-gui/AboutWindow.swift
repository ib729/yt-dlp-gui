import SwiftUI
import AppKit

struct AboutWindowInfo {
    let appName: String
    let description: String
    let version: String
    let projectURL: URL

    static func fromBundle() -> AboutWindowInfo {
        let bundle = Bundle.main
        let info = bundle.infoDictionary ?? [:]

        let appName = info["CFBundleDisplayName"] as? String
            ?? info["CFBundleName"] as? String
            ?? "yt-dlp-gui"

        let description = info["AppDescription"] as? String
            ?? "A native SwiftUI interface for yt-dlp."

        let version = info["CFBundleShortVersionString"] as? String ?? "—"

        let fallbackURL = URL(string: "https://github.com/ib729/yt-dlp-gui")!
        let repositoryString = info["RepositoryURL"] as? String
            ?? info["GitRepositoryURL"] as? String
            ?? fallbackURL.absoluteString

        let projectURL = URL(string: repositoryString) ?? fallbackURL

        return AboutWindowInfo(
            appName: appName,
            description: description,
            version: version,
            projectURL: projectURL
        )
    }
}

struct AboutAppView: View {
    let info: AboutWindowInfo

    @State private var isVisible = false
    @State private var isHoveringButton = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            // Dark background
            Color(red: 0.15, green: 0.15, blue: 0.15)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 32)

                // App Icon
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Spacer()
                    .frame(height: 5)

                // App Name
                Text(info.appName)
                    .font(.system(size: 24, weight: .semibold, design: .default))
                    .foregroundStyle(.white)

                Spacer()
                    .frame(height: 10)

                // Description
                Text(info.description)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(Color(white: 0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 280)

                Spacer()
                    .frame(height: 28)

                // Version info
                HStack(spacing: 6) {
                    Text("Version")
                        .foregroundStyle(Color(white: 0.85))
                    Text(info.version)
                        .foregroundStyle(Color(white: 0.65))
                        .fontWeight(.medium)
                }
                .font(.system(size: 12))

                Spacer()
                    .frame(height: 24)

                // GitHub button
                Button {
                    openURL(info.projectURL)
                } label: {
                    Text("GitHub")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white:0.85))
                        .frame(width: 70, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(white: isHoveringButton ? 0.3 : 0.25))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHoveringButton = hovering
                    }
                }

                Spacer()
                    .frame(height: 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.2)) {
                    isVisible = true
                }
            }
        }
        .frame(width: 300, height: 320)
    }
}

final class AboutWindowController: NSWindowController {
    convenience init(info: AboutWindowInfo) {
        let hostingController = NSHostingController(rootView: AboutAppView(info: info))
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = true
        window.backgroundColor = NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()
        window.contentViewController = hostingController

        self.init(window: window)
    }

    func present() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class AboutWindowCoordinator {
    static let shared = AboutWindowCoordinator()

    private var windowController: AboutWindowController?

    func show() {
        let info = AboutWindowInfo.fromBundle()

        if let hosting = windowController?.contentViewController as? NSHostingController<AboutAppView> {
            hosting.rootView = AboutAppView(info: info)
        } else {
            windowController = AboutWindowController(info: info)
        }

        windowController?.present()
    }
}
