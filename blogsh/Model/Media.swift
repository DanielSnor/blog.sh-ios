import SwiftUI
import PhotosUI
import AVFoundation
import CoreTransferable
import os

/// What the picker hands over, made into what travels. A photograph is
/// shrunk and written as JPEG whatever it was -- HEIC included, which is
/// what a phone writes by default and what the /write/ page has to send
/// whole for the blog to convert. A video is exported as H.264 in an MP4
/// at 720p: the size the page's own recipe sends, and a format every
/// browser plays, where a phone's own HEVC plays mainly in Safari. Neither
/// carries where it was taken. What cannot be converted goes as it is, as
/// on the page.
nonisolated enum Media {
    /// A movie as the picker hands it over: a file, copied to where the app may read it.
    struct Movie: Transferable {
        let url: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .movie) { movie in
                SentTransferredFile(movie.url)
            } importing: { received in
                let name = UUID().uuidString + "." + (received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try FileManager.default.copyItem(at: received.file, to: copy)
                return Movie(url: copy)
            }
        }
    }

    /// Why nothing could be read of a picked item.
    enum Unread: Error, Equatable {
        /// The library does not hold it whole on this device, and what is
        /// missing could not be fetched: there is no network to fetch it over.
        case needsNetwork
        case unreadable

        /// The sentence for it, in the reader's language.
        var words: String {
            switch self {
            case .needsNetwork:
                String(localized: "The picture could not be read: it is most likely kept in iCloud, and without a network it cannot be fetched. One that is on this device whole -- taken just now, say -- can be added.")
            case .unreadable:
                String(localized: "One picture could not be read.")
            }
        }
    }

    private static let log = Logger(subsystem: "app.blogsh.ios", category: "media")

    /// What a failed read was: the library saying it needs the network,
    /// in so many words or by failing while the device has none.
    static func unread(_ error: Error?, online: Bool) -> Unread {
        var next = error.map { $0 as NSError }
        while let one = next {
            if one.domain == "PHPhotosErrorDomain", [3164, 3169].contains(one.code) { return .needsNetwork }
            if one.domain == NSURLErrorDomain { return .needsNetwork }
            next = one.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return online ? .unreadable : .needsNetwork
    }

    /// One picked item as a shot; thrown, why nothing could be read of it.
    @concurrent static func shot(from item: PhotosPickerItem, index: Int, taken: [String]) async throws(Unread) -> Shot {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let shot = await video(from: item, index: index, taken: taken) else {
                throw unread(nil, online: NetworkWatch.hasNetwork)
            }
            return shot
        }
        let data: Data?
        do {
            data = try await item.loadTransferable(type: Data.self)
        } catch {
            // Kept where a device's log can be read: the picker's own reason.
            log.error("picture not read: \(String(describing: error), privacy: .public)")
            throw unread(error, online: NetworkWatch.hasNetwork)
        }
        guard let data, let shrunk = Pictures.shrink(data) else {
            log.error("picture not read: nothing came, or not a picture")
            throw unread(nil, online: NetworkWatch.hasNetwork)
        }
        let name = Pictures.freeName(Pictures.safeName(item.itemIdentifier, index: index), taken: taken)
        return Shot(name: name, data: shrunk.data, width: shrunk.width, height: shrunk.height,
                    thumb: Pictures.thumbnail(shrunk.data))
    }

    @concurrent private static func video(from item: PhotosPickerItem, index: Int, taken: [String]) async -> Shot? {
        guard let movie = try? await item.loadTransferable(type: Movie.self) else { return nil }
        defer { try? FileManager.default.removeItem(at: movie.url) }
        let poster = await poster(of: movie.url)
        if let converted = await h264(movie.url) {
            defer { try? FileManager.default.removeItem(at: converted) }
            guard let data = try? Data(contentsOf: converted) else { return nil }
            let name = Pictures.freeName(Pictures.safeName(item.itemIdentifier, index: index, stem: "video", ext: "mp4"), taken: taken)
            return Shot(name: name, data: data, width: 0, height: 0, kind: .video, poster: poster)
        }
        // Not converted: whole, under the extension it came with.
        guard let data = try? Data(contentsOf: movie.url) else { return nil }
        let ext = ["mp4", "mov", "m4v"].contains(movie.url.pathExtension.lowercased()) ? movie.url.pathExtension.lowercased() : "mov"
        let name = Pictures.freeName(Pictures.safeName(item.itemIdentifier, index: index, stem: "video", ext: ext), taken: taken)
        return Shot(name: name, data: data, width: 0, height: 0, kind: .video, poster: poster, converted: false)
    }

    /// The video as H.264 in an MP4, 720p at most, or nil when the export fails.
    @concurrent private static func h264(_ source: URL) async -> URL? {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { return nil }
        session.shouldOptimizeForNetworkUse = true
        // Where it was taken stays on the phone: a photograph loses its
        // place when it is re-encoded, and a video must not keep what a
        // photograph does not.
        session.metadataItemFilter = .forSharing()
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        do {
            try await session.export(to: out, as: .mp4)
            return out
        } catch {
            try? FileManager.default.removeItem(at: out)
            return nil
        }
    }

    /// A frame of the video, small, for its card.
    @concurrent private static func poster(of source: URL) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        guard let frame = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: frame).jpegData(compressionQuality: 0.7)
    }
}

/// What a delivery weighs and whether the blog will take it -- the line
/// the /write/ page keeps under its pictures, and the legend beside it.
nonisolated enum Delivery {
    /// The encoded stream, the thing the receiver measures: every file's
    /// base64 with its line breaks, its name, and the line that ends it.
    static func wireBytes(shots: [Shot], textBytes: Int) -> Int {
        shots.reduce(0) { $0 + encodedSize($1.data.count) + 80 } + encodedSize(textBytes + 200) + 80
    }

    static func over(shots: [Shot], textBytes: Int, maxMb: Int) -> Bool {
        maxMb > 0 && wireBytes(shots: shots, textBytes: textBytes) > maxMb * 1_048_576
    }

    static func size(_ bytes: Int) -> String {
        let kb = max(bytes > 0 ? 1 : 0, Int((Double(bytes) / 1024).rounded()))
        if kb < 1024 { return "\(kb) kB" }
        return (Double(bytes) / 1_048_576).formatted(.number.precision(.fractionLength(1))) + " MB"
    }

    /// "3 pictures, 1 video, 4.2 MB", with the plural the reader's language
    /// wants: one, a few (two to four, which Czech counts differently), many.
    static func describe(shots: [Shot], textBytes: Int) -> String {
        let videos = shots.filter { $0.kind == .video }.count
        let pictures = shots.count - videos
        var parts: [String] = []
        if pictures > 0 { parts.append("\(pictures) " + pictureWord(pictures)) }
        if videos > 0 { parts.append("\(videos) " + videoWord(videos)) }
        if parts.isEmpty { parts.append(String(localized: "batch.text_only", defaultValue: "text only")) }
        return parts.joined(separator: ", ") + ", " + size(shots.reduce(textBytes) { $0 + $1.data.count })
    }

    private static func pictureWord(_ n: Int) -> String {
        if n == 1 { return String(localized: "batch.pictures.one", defaultValue: "picture") }
        return n < 5 ? String(localized: "batch.pictures.few", defaultValue: "pictures")
                     : String(localized: "batch.pictures.many", defaultValue: "pictures")
    }

    private static func videoWord(_ n: Int) -> String {
        if n == 1 { return String(localized: "batch.videos.one", defaultValue: "video") }
        return n < 5 ? String(localized: "batch.videos.few", defaultValue: "videos")
                     : String(localized: "batch.videos.many", defaultValue: "videos")
    }
}
