// In-app web browser for Nexus Mods. Signing in here is remembered (WebKit's
// default persistent data store), "Mod Manager Download" nxm:// links are
// caught before they leave the app (so Tadpole and Starseed don't fight over
// the nxm scheme), and archives downloaded directly are installed.

import AppKit
import SwiftUI
import TadpoleCore
import WebKit

enum BrowserWindow {
    static let id = "nexus"
}

struct BrowserView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var browser = BrowserController()

    var body: some View {
        VStack(spacing: 0) {
            if model.nexusAccount.user == nil {
                keyBanner
                Divider()
            } else if let current = model.browserQueue.first {
                queueBanner(current)
                Divider()
            }
            WebViewHost(webView: browser.webView)
                .overlay(alignment: .top) {
                    if browser.isLoading {
                        ProgressView(value: browser.progress)
                            .progressViewStyle(.linear)
                            .controlSize(.mini)
                    }
                }
            if !model.downloads.isEmpty {
                Divider()
                DownloadList()
            }
        }
        .navigationTitle(browser.title.isEmpty ? "Nexus Mods" : browser.title)
        .navigationSubtitle(browser.url?.host() ?? "")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { browser.webView.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(!browser.canGoBack)
                Button { browser.webView.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                    .disabled(!browser.canGoForward)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if browser.isLoading {
                    Button { browser.webView.stopLoading() } label: { Label("Stop", systemImage: "xmark") }
                } else {
                    Button { browser.webView.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                }
                Button { browser.load(NexusClient.homeURL) } label: { Label("Baldur's Gate 3 on Nexus", systemImage: "house") }
                    .help("Baldur's Gate 3 mods on Nexus")
                Button {
                    if let url = browser.url { NSWorkspace.shared.open(url) }
                } label: {
                    Label("Open in Default Browser", systemImage: "safari")
                }
                .help("Open this page in your default browser")
                .disabled(browser.url == nil)
            }
        }
        .onAppear {
            browser.onNXMLink = { model.handleNXMLink($0) }
            browser.onArchiveDownloaded = { model.installBrowserDownload($0) }
            browser.onDownloadFailed = { model.show("Download Failed", $0) }
            browser.load(model.browserRequest?.url ?? NexusClient.homeURL)
        }
        .onChange(of: model.browserRequest) { _, request in
            if let request { browser.load(request.url) }
        }
        .onChange(of: model.browserDone) {
            // A download started (it goes on in the main window): close,
            // after a moment so the click visibly did something.
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                guard model.browserQueue.isEmpty else { return }
                dismissWindow(id: BrowserWindow.id)
            }
        }
    }

    private func queueBanner(_ current: BrowserQueueItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(current.title) — \(model.browserQueue.count) left")
                    .font(.headline)
                Text("Click **Slow download** below. The next mod opens by itself once each download starts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Skip") { model.skipQueuedDownload() }
            Button("Stop", role: .cancel) { model.cancelDownloadQueue() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var keyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Add your Nexus API key to install mods from here")
                    .font(.headline)
                Text("Then click **Mod Manager Download** on a mod's Files tab: Tadpole downloads and installs it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SettingsLink { Text("Settings…") }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct DownloadList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                if model.downloads.contains(where: \.isFinished) {
                    Button("Clear") { model.clearFinishedDownloads() }
                        .buttonStyle(.link)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.downloads) { item in
                        DownloadRow(item: item)
                    }
                }
            }
            .frame(maxHeight: 120)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct DownloadRow: View {
    let item: DownloadItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            if item.canCancel {
                Button {
                    item.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Cancel this download")
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.state {
        case .waiting:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .starting, .installing:
            ProgressView().controlSize(.mini)
        case .downloading:
            ProgressView(value: item.progress).progressViewStyle(.circular).controlSize(.mini)
        case .installed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .cancelled:
            Image(systemName: "xmark.circle").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var detail: String? {
        switch item.state {
        case .waiting: String(localized: "Waiting for another download to finish…")
        case .cancelled: String(localized: "Cancelled")
        case .starting: String(localized: "Asking Nexus…")
        case .downloading: String(localized: "Downloading… \(item.progress.formatted(.percent.precision(.fractionLength(0))))")
        case .installing: String(localized: "Installing…")
        case .installed(let names): String(localized: "Installed and turned on: \(names.formatted(.list(type: .and)))")
        case .failed(let message): message
        }
    }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

@MainActor
@Observable
final class BrowserController: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let webView: WKWebView
    private(set) var title = ""
    private(set) var url: URL?
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var progress = 0.0

    @ObservationIgnored var onNXMLink: (URL) -> Void = { _ in }
    @ObservationIgnored var onArchiveDownloaded: (URL) -> Void = { _ in }
    @ObservationIgnored var onDownloadFailed: (String) -> Void = { _ in }
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()  // keeps the Nexus sign-in
        webView = WKWebView(frame: .zero, configuration: configuration)
        // Present as Safari so sign-in pages don't reject an "embedded browser".
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self

        observations = [
            webView.observe(\.title) { [weak self] view, _ in MainActor.assumeIsolated { self?.title = view.title ?? "" } },
            webView.observe(\.url) { [weak self] view, _ in MainActor.assumeIsolated { self?.url = view.url } },
            webView.observe(\.canGoBack) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoBack = view.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoForward = view.canGoForward } },
            webView.observe(\.isLoading) { [weak self] view, _ in MainActor.assumeIsolated { self?.isLoading = view.isLoading } },
            webView.observe(\.estimatedProgress) { [weak self] view, _ in MainActor.assumeIsolated { self?.progress = view.estimatedProgress } },
        ]
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
        switch url.scheme?.lowercased() {
        case "nxm":
            onNXMLink(url)
            decisionHandler(.cancel)
        case "http", "https", "about", "blob", "data":
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
        default:
            // mailto:, steam:// etc. go to their usual apps.
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    /// Links that open a new window (target="_blank") load in this one.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // MARK: Downloads

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping @MainActor (URL?) -> Void) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "tadpole-browser-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return completionHandler(nil)
        }
        let destination = folder.appending(path: suggestedFilename.isEmpty ? "download.zip" : suggestedFilename)
        downloadDestinations[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let file = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let ext = file.pathExtension.lowercased()
        if ext == "pak" || ModInstaller.archiveExtensions.contains(ext) {
            onArchiveDownloaded(file)
        } else {
            // Not a mod: hand it to the user in Downloads instead.
            let target = URL.downloadsDirectory.appending(path: file.lastPathComponent)
            try? FileManager.default.moveItem(at: file, to: target)
            NSWorkspace.shared.activateFileViewerSelecting([target])
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        onDownloadFailed(error.localizedDescription)
    }
}
