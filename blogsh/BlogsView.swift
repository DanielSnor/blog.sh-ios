import SwiftUI

/// The blogs the app drives, and the way from one to another: a row opens
/// its blog, the last key begins a new one. A blog is its own server, its
/// own key and its own colour; nothing of one is used for another.
struct BlogsView: View {
    /// Told when a blog was added, so its settings can open next.
    let added: () -> Void
    @Environment(\.dismiss) private var dismiss
    private var blogs = Blogs.shared
    @State private var removing: Blog?

    init(added: @escaping () -> Void) {
        self.added = added
    }

    var body: some View {
        List {
            ScreenHeader(title: String(localized: "Blogs"), count: blogs.all.isEmpty ? nil : blogs.all.count.formatted())
                .padding(.top, 2)
                .padding(.bottom, 6)
                .paperRow()
            ForEach(blogs.all) { blog in
                Button {
                    blogs.select(blog.id)
                    dismiss()
                } label: {
                    BlogRow(blog: blog, open: blog.id == blogs.currentID)
                }
                .buttonStyle(PressStyle())
                .confirmationDialog("Remove '\(blog.label)' from the app? Its key is deleted with it; the blog itself is not touched.",
                                    isPresented: Binding(get: { removing?.id == blog.id }, set: { if !$0 { removing = nil } }),
                                    titleVisibility: .visible) {
                    Button("Remove", role: .destructive) { blogs.remove(blog.id) }
                }
                .paperRow()
                .swipeActions {
                    Button("Remove", role: .destructive) { removing = blog }
                }
            }
            Command("Add a blog", symbol: "plus") {
                blogs.add()
                added()
                dismiss()
            }
            .padding(.vertical, 12)
            .paperRow(rule: false)
        }
        .paperList()
        .navigationTitle("Blogs")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

/// A blog as a row says it: its mark, its name, where it is -- and which one is open.
struct BlogRow: View {
    let blog: Blog
    let open: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let mark = SiteIcon.kept(for: blog.url) {
                Image(uiImage: mark)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "globe").foregroundStyle(Theme.muted))
            }
            VStack(alignment: .leading, spacing: 2) {
                if blog.label.isEmpty {
                    Text("A new blog").font(.ui(15, weight: .medium)).foregroundStyle(Theme.muted)
                } else {
                    Text(verbatim: blog.label).font(.ui(15, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                }
                let place = blog.host.isEmpty ? "" : "\(blog.user.isEmpty ? "" : blog.user + "@")\(blog.host)"
                if !place.isEmpty {
                    Text(verbatim: place).font(.mono(12, bold: false)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if open {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tint)
                    .accessibilityLabel(Text("Open"))
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack { BlogsView(added: {}) }
}
