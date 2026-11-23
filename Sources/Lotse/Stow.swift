import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Ablage: Bilder auf die Insel ziehen und als Kopie in einem anderen Format neben dem Original speichern.
enum Stow {
    enum Job: Equatable {
        case web            // fürs Web: max. 2000 px, JPEG
        case send           // zum Verschicken: max. 1280 px, kleines JPEG
        case print          // ein PDF mit einer A4-Seite je Bild
        case format(String) // reine Umwandlung: "jpg", "png", "heic", "avif"
    }

    static let formats: [(label: String, ext: String, type: UTType)] = {
        let writable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        let all: [(String, String, UTType?)] = [
            ("JPG", "jpg", .jpeg), ("PNG", "png", .png), ("HEIC", "heic", .heic),
            ("AVIF", "avif", UTType("public.avif")), ("TIFF", "tiff", .tiff),
        ]
        return all.compactMap { l, e, t in
            guard let t, writable.contains(t.identifier) else { return nil }
            return (l, e, t)
        }
    }()

    static func isImage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .image) ?? false
    }

    static func thumbnail(_ url: URL, size: CGFloat = 200) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: img, size: .zero)
    }

    static func run(_ job: Job, files: [URL]) -> [URL] {
        switch job {
        case .web: return files.compactMap { convert($0, to: .jpeg, ext: "jpg", maxEdge: 2000, quality: 0.82, suffix: "-web") }
        case .send: return files.compactMap { convert($0, to: .jpeg, ext: "jpg", maxEdge: 1280, quality: 0.7, suffix: "-klein") }
        case .print: return pdf(files).map { [$0] } ?? []
        case .format(let ext):
            guard let f = formats.first(where: { $0.ext == ext }) else { return [] }
            return files.compactMap { convert($0, to: f.type, ext: f.ext, maxEdge: nil, quality: 0.9, suffix: "") }
        }
    }

    /// Freier Dateiname neben dem Original – überschreibt nie etwas.
    private static func target(for url: URL, suffix: String, ext: String) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent + suffix
        var out = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: out.path) {
            out = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return out
    }

    private static func load(_ url: URL, maxEdge: CGFloat?) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = props?[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
        let h = props?[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
        let edge = min(maxEdge ?? .greatestFiniteMagnitude, max(w, h, 1))
        // Über den Thumbnail-Weg wird die Ausrichtung (EXIF) gleich mit angewendet.
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
        ] as CFDictionary)
    }

    private static func convert(_ url: URL, to type: UTType, ext: String, maxEdge: CGFloat?, quality: Double, suffix: String) -> URL? {
        guard let img = load(url, maxEdge: maxEdge) else { return nil }
        let out = target(for: url, suffix: suffix, ext: ext)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out : nil
    }

    private static func pdf(_ files: [URL]) -> URL? {
        guard let first = files.first else { return nil }
        let out = target(for: first, suffix: files.count > 1 ? "-druck" : "", ext: "pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4 in Punkt
        guard let ctx = CGContext(out as CFURL, mediaBox: &box, nil) else { return nil }
        var pages = 0
        for url in files {
            guard let img = load(url, maxEdge: 3000) else { continue }
            let iw = CGFloat(img.width), ih = CGFloat(img.height)
            var page = iw > ih ? CGRect(x: 0, y: 0, width: 842, height: 595) : CGRect(x: 0, y: 0, width: 595, height: 842)
            let margin: CGFloat = 28
            let scale = min((page.width - 2 * margin) / iw, (page.height - 2 * margin) / ih)
            let rect = CGRect(x: (page.width - iw * scale) / 2, y: (page.height - ih * scale) / 2, width: iw * scale, height: ih * scale)
            ctx.beginPage(mediaBox: &page)
            ctx.draw(img, in: rect)
            ctx.endPage()
            pages += 1
        }
        ctx.closePDF()
        if pages == 0 { try? FileManager.default.removeItem(at: out); return nil }
        return out
    }
}
