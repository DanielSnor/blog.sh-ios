import SwiftUI

/// The blogs the app drives, and the way from one to another: a row opens
/// its blog, the key at its end opens that blog's settings, the last key
/// begins a new one -- with a code from the server, or by hand. A blog is its own server, its own key and its own
/// colour; nothing of one is used for another.
struct BlogsView: View {
    @Environment(\.dismiss) private var dismiss
    private var blogs = Blogs.shared
    @State private var removing: Blog?
    @State private var settingUp = false
    @State private var adding = false

    var body: some View {
        List {
            ForEach(blogs.all) { blog in
                HStack(spacing: 4) {
                    Button {
                        blogs.select(blog.id)
                        dismiss()
                    } label: {
                        BlogRow(blog: blog, open: blog.id == blogs.currentID)
                    }
                    .buttonStyle(PressStyle())
                    // The settings are the open blog's: the key opens the blog with them.
                    Button {
                        blogs.select(blog.id)
                        settingUp = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16))
                            .foregroundStyle(.tint)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(Text("The blog's settings"))
                }
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
            Command("Add a blog", symbol: "plus") { adding = true }
            .padding(.vertical, 12)
            .paperRow(rule: false)
        }
        .paperList(name: String(localized: "Blogs"), count: blogs.all.isEmpty ? nil : blogs.all.count.formatted())
        .navigationTitle("Blogs")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .navigationDestination(isPresented: $adding) {
            AddBlogView(close: { dismiss() })
        }
        .navigationDestination(isPresented: $settingUp) {
            BlogSettingsView(close: { dismiss() })
        }
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
    NavigationStack { BlogsView() }
}
