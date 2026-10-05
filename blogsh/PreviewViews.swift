import SwiftUI
import WebKit
import AVKit

/// The post as the blog would show it, before it is sent: the text
/// rendered the way the /write/ page renders it, in the blog's own
/// stylesheets. Near enough, not exact -- and it says so.
struct PreviewSheet: View {
    let title: String
    let markdown: String
    let shown: [String: Preview.Shown]
    /// The language the text is in, when it is not the reader's own: a translation's.
    var lang: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let site = Blogs.shared.current?.url ?? ""
        let lang = lang ?? Locale.current.language.languageCode?.identifier ?? "en"
        let page = Preview.document(title: title, body: Preview.render(markdown, shots: shown, words: Preview.spoken), lang: lang)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                ScreenHeader(title: String(localized: "Preview"))
                Spacer()
                Button { dismiss() } label: { Text("Done").font(.ui(16, weight: .semibold)).foregroundStyle(.tint) }
                    .buttonStyle(PressStyle())
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 18)
            Rectangle().fill(Theme.line).frame(height: 1).padding(.top, 10)
            WebPage(html: page, base: URL(string: site))
            Rectangle().fill(Theme.line).frame(height: 1)
            Hint("Near enough, not exact: the blog itself renders the post, and the draft's preview after sending is the real thing.")
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 10)
        }
        .background(Theme.paper.ignoresSafeArea())
    }
}

/// A page of markup, shown; a link in it leads nowhere -- this is a look
/// at a post, not a browser.
private struct WebPage: UIViewRepresentable {
    let html: String
    let base: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.loadHTMLString(html, baseURL: base)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            action.navigationType == .other ? .allow : .cancel
        }
    }
}

/// The shots of a form, one to a page and large: what each of them is, and
/// under it the line that describes it -- written while looking at it.
struct ShotsViewer: View {
    @Binding var shots: [Shot]
    @State var current: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                if let index = shots.firstIndex(where: { $0.id == current }) {
                    Text("\(index + 1) of \(shots.count)").engineLabel(13).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { dismiss() } label: { Text("Done").font(.ui(16, weight: .semibold)).foregroundStyle(.tint) }
                    .buttonStyle(PressStyle())
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 14)
            TabView(selection: $current) {
                ForEach($shots) { $shot in
                    ShotPage(shot: $shot).tag(shot.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Theme.paper.ignoresSafeArea())
    }
}

private struct ShotPage: View {
    @Binding var shot: Shot
    // Decoded once: the whole picture is too heavy to read again with every letter.
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var file: URL?

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Theme.gutter)
            Plate {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: shot.name).font(.mono(12, bold: false)).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(verbatim: Delivery.size(shot.data.count)).font(.mono(11, bold: false)).foregroundStyle(Theme.muted)
                }
                TextField("", text: $shot.alt, prompt: Text("No description yet").foregroundStyle(Theme.muted), axis: .vertical)
                    .lineLimit(1...4)
                    .font(.ui(16))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 16)
        }
        .task(id: shot.id) { await open() }
        .onDisappear {
            player?.pause()
            if let file { try? FileManager.default.removeItem(at: file) }
        }
    }

    /// A picture is decoded; a video is put where a player can read it.
    private func open() async {
        if shot.kind == .video {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("look-" + shot.id.uuidString + "-" + shot.name)
            let data = shot.data
            let written = await Task.detached { (try? data.write(to: url, options: .atomic)) != nil }.value
            if written {
                file = url
                player = AVPlayer(url: url)
            } else if let frame = shot.poster {
                image = UIImage(data: frame)
            }
        } else {
            let data = shot.data
            image = await Task.detached { UIImage(data: data) }.value
        }
    }
}
