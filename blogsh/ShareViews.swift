import SwiftUI
import UIKit
import LinkPresentation

/// The key that hands a post's address to somebody: the system's own
/// sheet, with the address and the title to go with it. It stands in the
/// bar of every screen that is about one post, once the engine has said
/// where the post is.
struct ShareKey: View {
    let link: PostLink

    var body: some View {
        ShareLink(item: link.url, subject: Text(verbatim: link.title), message: Text(verbatim: link.title), preview: preview) {
            Label("Share the link", systemImage: "square.and.arrow.up")
        }
    }

    /// What the sheet shows of what it is about to hand on: the post's
    /// title, and the blog's own mark where the app has it.
    private var preview: SharePreview<Image, Never> {
        if let mark = SiteIcon.kept(for: Blogs.shared.current?.url ?? "") {
            return SharePreview(link.title, image: Image(uiImage: mark))
        }
        return SharePreview(link.title, image: Image(systemName: "doc.text"))
    }
}

/// The same sheet for a place that learns the address only when asked --
/// a row of the archive, which has to ask the engine first. What it hands
/// on is the address with the post's title for its name, so the sheet
/// says which post it is about, as the key's own does.
struct ShareSheet: UIViewControllerRepresentable {
    let link: PostLink

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [Named(link: link)], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    private final class Named: NSObject, UIActivityItemSource {
        let link: PostLink

        init(link: PostLink) { self.link = link }

        func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { link.url }

        func activityViewController(_ controller: UIActivityViewController,
                                    itemForActivityType type: UIActivity.ActivityType?) -> Any? { link.url }

        func activityViewController(_ controller: UIActivityViewController,
                                    subjectForActivityType type: UIActivity.ActivityType?) -> String { link.title }

        func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
            let said = LPLinkMetadata()
            said.originalURL = link.url
            said.url = link.url
            said.title = link.title
            if let mark = SiteIcon.kept(for: Blogs.shared.current?.url ?? "") {
                said.iconProvider = NSItemProvider(object: mark)
            }
            return said
        }
    }
}
