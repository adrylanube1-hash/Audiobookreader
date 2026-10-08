import Foundation
import PDFKit
import UIKit
import ZIPFoundation

enum DocumentImportError: LocalizedError {
    case unsupported, empty, unreadable
    var errorDescription: String? {
        switch self {
        case .unsupported: return "Unsupported document format. Use PDF, EPUB, TXT or HTML."
        case .empty: return "The document does not contain readable text."
        case .unreadable: return "The selected document could not be read."
        }
    }
}

final class DocumentImporter {
    func importDocument(_ source: URL) async throws -> LibraryBook {
        try await Task.detached(priority: .userInitiated) {
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            let extensionName = source.pathExtension.lowercased()
            guard ["pdf", "epub", "txt", "text", "html", "htm"].contains(extensionName) else {
                throw DocumentImportError.unsupported
            }
            let id = UUID()
            let booksDirectory = Storage.support.appendingPathComponent("books", isDirectory: true)
            try FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true, attributes: nil)
            let storedName = "\(id.uuidString).\(extensionName)"
            let destination = booksDirectory.appendingPathComponent(storedName)
            try FileManager.default.copyItem(at: source, to: destination)

            let result: ([BookChapter], Data?)
            switch extensionName {
            case "pdf": result = try Self.parsePDF(destination)
            case "epub": result = try Self.parseEPUB(destination)
            case "html", "htm":
                let data = try Data(contentsOf: destination)
                result = ([BookChapter(id: "chapter-1", title: source.deletingPathExtension().lastPathComponent,
                                       text: Self.htmlText(data))], nil)
            default:
                guard let text = String(data: try Data(contentsOf: destination), encoding: .utf8) else {
                    throw DocumentImportError.unreadable
                }
                result = ([BookChapter(id: "chapter-1", title: source.deletingPathExtension().lastPathComponent,
                                       text: TextChunker.normalize(text))], nil)
            }
            let chapters = result.0.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !chapters.isEmpty else { throw DocumentImportError.empty }
            var coverName: String?
            if let cover = result.1 {
                coverName = "\(id.uuidString)-cover.jpg"
                try cover.write(to: booksDirectory.appendingPathComponent(coverName!), options: .atomic)
            }
            return LibraryBook(id: id, title: source.deletingPathExtension().lastPathComponent,
                               fileName: storedName, chapters: chapters, language: "en", coverFileName: coverName)
        }.value
    }

    private static func parsePDF(_ url: URL) throws -> ([BookChapter], Data?) {
        guard let document = PDFDocument(url: url) else { throw DocumentImportError.unreadable }
        var chapters: [BookChapter] = []
        for index in 0..<document.pageCount {
            guard let text = document.page(at: index)?.string else { continue }
            let normalized = TextChunker.normalize(text)
            if !normalized.isEmpty {
                chapters.append(BookChapter(id: "page-\(index + 1)", title: "Page \(index + 1)", text: normalized))
            }
        }
        let cover = document.page(at: 0)?.thumbnail(of: CGSize(width: 640, height: 900), for: .cropBox)
            .jpegData(compressionQuality: 0.86)
        return (chapters, cover)
    }

    private static func parseEPUB(_ url: URL) throws -> ([BookChapter], Data?) {
        let archive = try Archive(url: url, accessMode: .read)
        guard let containerData = data(in: archive, path: "META-INF/container.xml") else {
            throw DocumentImportError.unreadable
        }
        let container = XMLCollector(data: containerData)
        guard let opfPath = container.rootFile else { throw DocumentImportError.unreadable }
        guard let opfData = data(in: archive, path: opfPath) else { throw DocumentImportError.unreadable }
        let package = XMLCollector(data: opfData)
        let base = (opfPath as NSString).deletingLastPathComponent
        var chapters: [BookChapter] = []
        for (index, id) in package.spine.enumerated() {
            guard let href = package.manifest[id] else { continue }
            let path = base.isEmpty ? href : (base as NSString).appendingPathComponent(href)
            guard let html = data(in: archive, path: path) else { continue }
            let text = htmlText(html)
            if !text.isEmpty { chapters.append(BookChapter(id: "chapter-\(index + 1)", title: "Chapter \(index + 1)", text: text)) }
        }
        var cover: Data?
        if let coverId = package.coverId, let href = package.manifest[coverId] {
            let path = base.isEmpty ? href : (base as NSString).appendingPathComponent(href)
            cover = data(in: archive, path: path)
        }
        return (chapters, cover)
    }

    private static func data(in archive: Archive, path: String) -> Data? {
        let clean = path.removingPercentEncoding ?? path
        guard let entry = archive[clean] else { return nil }
        var result = Data()
        _ = try? archive.extract(entry) { result.append($0) }
        return result.isEmpty ? nil : result
    }

    private static func htmlText(_ data: Data) -> String {
        guard var html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return "" }
        html = html.replacingOccurrences(of: "(?i)</(p|div|h[1-6]|li|blockquote|tr)>", with: "$0\n\n", options: .regularExpression)
        guard let converted = html.data(using: .utf8),
              let attributed = try? NSAttributedString(data: converted, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                                  .characterEncoding: String.Encoding.utf8.rawValue],
                                                       documentAttributes: nil) else { return "" }
        return TextChunker.normalize(attributed.string)
    }
}

private final class XMLCollector: NSObject, XMLParserDelegate {
    var rootFile: String?
    var manifest: [String: String] = [:]
    var spine: [String] = []
    var coverId: String?

    init(data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        if name.hasSuffix("rootfile") { rootFile = attributeDict["full-path"] }
        if name.hasSuffix("item"), let id = attributeDict["id"], let href = attributeDict["href"] {
            manifest[id] = href
            if attributeDict["properties"]?.split(separator: " ").contains("cover-image") == true { coverId = id }
        }
        if name.hasSuffix("itemref"), let id = attributeDict["idref"] { spine.append(id) }
        if name.hasSuffix("meta"), attributeDict["name"] == "cover" { coverId = attributeDict["content"] }
    }
}
