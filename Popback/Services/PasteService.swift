// Modified for Popback on 2026-11-27. SPDX-License-Identifier: GPL-3.0-only
import AppKit

@MainActor
struct PasteService {

    private static let tempDir = NSTemporaryDirectory() + "Popback/"

    /// Backing key for the "Always Paste as Plain Text" setting (Settings > Pasting).
    nonisolated static let alwaysPlainTextDefaultsKey = "alwaysPastePlainText"

    /// Whether stripping formatting is meaningful for this item (RTF/HTML only).
    static func supportsPlainText(_ item: ClipboardItem) -> Bool {
        switch item.contentType {
        case .richText, .html:
            return !(item.textContent?.isEmpty ?? true)
        default:
            return false
        }
    }

    /// Combines the setting with the Shift modifier using XOR.
    /// Setting off: Shift strips formatting. Setting on: Shift keeps formatting.
    static func resolvePlainText() -> Bool {
        let always = UserDefaults.standard.bool(forKey: alwaysPlainTextDefaultsKey)
        let shiftHeld = NSEvent.modifierFlags.contains(.shift)
        return always != shiftHeld
    }

    /// - Parameter asPlainText: `nil` resolves from the setting combined with the Shift modifier.
    func paste(item: ClipboardItem, asPlainText: Bool? = nil) {
        write(item: item, asPlainText: asPlainText ?? Self.resolvePlainText())
    }

    /// Puts the item on the clipboard without counting it as a paste. The
    /// Clip Queue uses this to line up the next item before ⌘V is pressed.
    /// - Parameters:
    ///   - item: The history entry to restore.
    ///   - asPlainText: Whether to strip rich-text formatting.
    ///   - pasteboard: Destination for the restored items.
    func write(item: ClipboardItem, asPlainText: Bool, to pasteboard: NSPasteboard = .general) {
        if asPlainText, Self.supportsPlainText(item) {
            pastePlainText(item: item, to: pasteboard)
            return
        }

        pasteboard.clearContents()
        // Tag it last, so the file URL stays the first item (Ghostty needs that).
        defer { OwnPasteboardWrite.mark(pasteboard) }

        switch item.contentType {
        case .plainText, .html, .richText:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
            // Also set original format for rich text / HTML
            if item.contentType == .richText {
                pasteboard.setData(item.rawData, forType: .rtf)
            } else if item.contentType == .html {
                pasteboard.setData(item.rawData, forType: .html)
            }

        case .image:
            guard let image = NSImage(data: item.rawData),
                  let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                pasteboard.setData(item.rawData, forType: .tiff)
                break
            }

            // 임시 PNG 파일 저장 — 터미널 앱(Ghostty 등)이 파일 경로로 이미지를 전달
            let tempURL = Self.writeTempPNG(pngData, sourceApp: item.sourceAppName)

            // NSURL writeObjects로 파일 URL을 먼저 쓴 뒤 PNG/TIFF 추가
            // — Ghostty가 이미지 파일로 인식하려면 이 순서가 필요
            if let tempURL {
                pasteboard.writeObjects([tempURL as NSURL])
            }
            pasteboard.setData(pngData, forType: .png)
            pasteboard.setData(tiffData, forType: .tiff)

        case .url:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
                if let url = URL(string: text) {
                    pasteboard.setString(url.absoluteString, forType: .URL)
                }
            }

        case .fileURL:
            if let files = FileClip(data: item.rawData) {
                // Publish all items together so Finder sees the original selection.
                let items = files.pasteboardItems.map { representations in
                    /// One Finder file and its alternate text representation.
                    let file = NSPasteboardItem()
                    for (type, data) in representations { file.setData(data, forType: type) }
                    return file
                }
                pasteboard.writeObjects(items)
            }

        case .color:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }

        case .unknown:
            pasteboard.setData(item.rawData, forType: .string)
        }
    }

    /// The same types and data the normal paste puts on the clipboard, in
    /// the same order, for callers that hand the data out lazily (the Clip Queue).
    /// - Parameters:
    ///   - item: The history entry to prepare.
    ///   - asPlainText: Whether to strip rich-text formatting.
    func contents(for item: ClipboardItem, asPlainText: Bool) -> [PasteboardRepresentations] {
        func text(_ string: String) -> Data { Data(string.utf8) }

        if asPlainText, Self.supportsPlainText(item) {
            guard let string = item.textContent else { return [] }
            return [[(.string, text(string))]]
        }

        switch item.contentType {
        case .plainText, .html, .richText:
            var result: [(NSPasteboard.PasteboardType, Data)] = []
            if let string = item.textContent {
                result.append((.string, text(string)))
            }
            if item.contentType == .richText {
                result.append((.rtf, item.rawData))
            } else if item.contentType == .html {
                result.append((.html, item.rawData))
            }
            return [result]

        case .image:
            guard let image = NSImage(data: item.rawData),
                  let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                return [[(.tiff, item.rawData)]]
            }
            var result: [(NSPasteboard.PasteboardType, Data)] = []
            // File URL first, as in write(): Ghostty and other terminals take the path.
            if let tempURL = Self.writeTempPNG(pngData, sourceApp: item.sourceAppName) {
                result.append((.fileURL, text(tempURL.absoluteString)))
            }
            result.append((.png, pngData))
            result.append((.tiff, tiffData))
            return [result]

        case .url:
            guard let string = item.textContent else { return [] }
            var result = [(NSPasteboard.PasteboardType.string, text(string))]
            if let url = URL(string: string) {
                result.append((.URL, text(url.absoluteString)))
            }
            return [result]

        case .fileURL:
            return FileClip(data: item.rawData)?.pasteboardItems ?? []

        case .color:
            guard let string = item.textContent else { return [] }
            return [[(.string, text(string))]]

        case .unknown:
            return [[(.string, item.rawData)]]
        }
    }

    /// - Parameters:
    ///   - item: A clip whose plain text will be written.
    ///   - pasteboard: Destination for the plain-text representation.
    private func pastePlainText(item: ClipboardItem, to pasteboard: NSPasteboard) {
        guard let text = item.textContent else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        OwnPasteboardWrite.mark(pasteboard)
    }

    /// 오래된 임시 파일 정리 (1시간 이상)
    func cleanupTempFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: Self.tempDir) else { return }
        let cutoff = Date().addingTimeInterval(-3600)
        for file in files {
            let path = Self.tempDir + file
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let modified = attrs[.modificationDate] as? Date,
                  modified < cutoff else { continue }
            try? fm.removeItem(atPath: path)
        }
    }

    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f
    }()

    private static func writeTempPNG(_ data: Data, sourceApp: String?) -> URL? {
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        let asciiOnly = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_")
        let safeName = sourceApp?
            .unicodeScalars.filter { asciiOnly.contains($0) }
            .reduce(into: "") { $0.append(String($1)) }
            .trimmingCharacters(in: .whitespaces)
        let appName = (safeName?.isEmpty ?? true) ? "Popback" : safeName!
        let timestamp = filenameDateFormatter.string(from: Date())
        let filename = "\(appName) \(timestamp).png" as String
        let url = URL(fileURLWithPath: tempDir + filename)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
