// Modified for Popback on 2026-11-27. SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SwiftData

struct TransferDocument: Codable {
    struct Item: Codable {
        var id: UUID
        var contentType: String
        var rawData: Data
        var textContent: String?
        var thumbnailData: Data?
        var sourceAppName: String?
        var sourceAppBundleId: String?
        var contentHash: String
        var copiedAt: Date
        var userTitle: String?
        var isPinned: Bool
    }

    struct Board: Codable {
        var id: UUID
        var name: String
        var displayOrder: Int
        var createdAt: Date
    }

    struct Entry: Codable {
        var id: UUID
        var pinboardID: UUID
        var itemID: UUID
        var displayOrder: Int
        var addedAt: Date
    }

    struct Exclusion: Codable {
        var bundleId: String
        var appName: String
    }

    /// Identifies backups belonging to this application.
    var format: String
    var version: Int
    var exportedAt: Date
    var items: [Item]
    var pinboards: [Board]
    var entries: [Entry]
    var exclusions: [Exclusion]
}

@MainActor
enum TransferService {

    /// Current JSON backup schema.
    private static let formatVersion = 1

    enum BackupError: LocalizedError {
        case unsupportedFormat

        var errorDescription: String? {
            String(localized: "Select a supported Popback backup.")
        }
    }

    struct ImportSummary {
        var importedItems = 0
        var skippedItems = 0
        var importedBoards = 0
        var importedEntries = 0
        var importedExclusions = 0

        /// User-facing result shown after an import, one sentence per line so
        /// each part translates on its own.
        var localizedMessage: String {
            var lines = [String(localized: "Imported \(importedItems) clips.")]
            if skippedItems > 0 {
                lines.append(String(localized: "Skipped \(skippedItems) duplicates."))
            }
            if importedBoards > 0 {
                lines.append(String(localized: "Imported \(importedBoards) pinboards."))
            }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - Export

    /// Encodes history, board memberships and app exclusions.
    /// - Parameter context: Source library selected for export.
    static func exportDocument(context: ModelContext) throws -> Data {
        let items = try context.fetch(FetchDescriptor<ClipboardItem>())
        let boards = try context.fetch(FetchDescriptor<Pinboard>())
        let exclusions = try context.fetch(FetchDescriptor<ExcludedApp>())

        var entryRecords: [TransferDocument.Entry] = []
        for board in boards {
            for entry in board.entries {
                guard let item = entry.clipboardItem else { continue }
                entryRecords.append(TransferDocument.Entry(
                    id: entry.id,
                    pinboardID: board.id,
                    itemID: item.id,
                    displayOrder: entry.displayOrder,
                    addedAt: entry.addedAt
                ))
            }
        }

        let doc = TransferDocument(
            format: AppIdentity.backupFormat,
            version: formatVersion,
            exportedAt: Date(),
            items: items.map { item in
                TransferDocument.Item(
                    id: item.id,
                    contentType: item.contentTypeRaw,
                    rawData: item.rawData,
                    textContent: item.textContent,
                    thumbnailData: item.thumbnailData,
                    sourceAppName: item.sourceAppName,
                    sourceAppBundleId: item.sourceAppBundleId,
                    contentHash: item.contentHash,
                    copiedAt: item.copiedAt,
                    userTitle: item.userTitle,
                    isPinned: item.isPinned
                )
            },
            pinboards: boards.map { board in
                TransferDocument.Board(
                    id: board.id,
                    name: board.name,
                    displayOrder: board.displayOrder,
                    createdAt: board.createdAt
                )
            },
            entries: entryRecords,
            exclusions: exclusions.map { exclusion in
                TransferDocument.Exclusion(bundleId: exclusion.bundleId, appName: exclusion.appName)
            }
        )

        let encoder = JSONEncoder()
        return try encoder.encode(doc)
    }

    // MARK: - Import

    /// Merges records by their persistent IDs so equal content from different apps survives.
    /// - Parameters:
    ///   - data: Contents of a Popback JSON backup.
    ///   - context: Destination library used by the calling window.
    static func importDocument(_ data: Data, context: ModelContext) throws -> ImportSummary {
        /// Shared decoder for the format check and full archive.
        let decoder = JSONDecoder()
        // Reject foreign or newer backups before reading or modifying the library.
        struct Header: Decodable {
            var format: String?
            var version: Int
        }
        /// Identity and version shared by every supported backup.
        let header = try decoder.decode(Header.self, from: data)
        guard header.format == AppIdentity.backupFormat, header.version == formatVersion else {
            throw BackupError.unsupportedFormat
        }
        /// Validated Popback archive.
        let doc = try decoder.decode(TransferDocument.self, from: data)

        // Preserve pending UI edits before starting the all-or-nothing restore.
        if context.hasChanges { try context.save() }
        do {
            return try merge(doc, into: context)
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Restores the decoded records and saves all relationships in one transaction.
    /// - Parameters:
    ///   - doc: Validated backup.
    ///   - context: Destination context with no pending edits.
    private static func merge(_ doc: TransferDocument, into context: ModelContext) throws -> ImportSummary {
        var summary = ImportSummary()

        /// Resolve links by record identity, including on a repeated import.
        let existingItems = try context.fetch(FetchDescriptor<ClipboardItem>())
        var itemsByID = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
        for record in doc.items {
            if itemsByID[record.id] != nil {
                summary.skippedItems += 1
                continue
            }
            let item = ClipboardItem(
                contentType: ContentType(rawValue: record.contentType) ?? .unknown,
                rawData: record.rawData,
                textContent: record.textContent,
                thumbnailData: record.thumbnailData,
                sourceAppName: record.sourceAppName,
                sourceAppBundleId: record.sourceAppBundleId,
                contentHash: record.contentHash
            )
            item.id = record.id
            item.copiedAt = record.copiedAt
            item.userTitle = record.userTitle
            item.isPinned = record.isPinned
            context.insert(item)
            itemsByID[record.id] = item
            summary.importedItems += 1
        }

        /// Pinboards with identical display names are distinct collections.
        let existingBoards = try context.fetch(FetchDescriptor<Pinboard>())
        var boardsByID = Dictionary(uniqueKeysWithValues: existingBoards.map { ($0.id, $0) })
        for record in doc.pinboards where boardsByID[record.id] == nil {
            let board = Pinboard(name: record.name, displayOrder: record.displayOrder)
            board.id = record.id
            board.createdAt = record.createdAt
            context.insert(board)
            boardsByID[record.id] = board
            summary.importedBoards += 1
        }

        // Pinboard entries (skip if the board already contains the item)
        for record in doc.entries {
            guard let board = boardsByID[record.pinboardID],
                  let item = itemsByID[record.itemID] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            item.isPinned = true
            if board.entries.contains(where: { $0.clipboardItem?.id == item.id }) { continue }
            /// Recreate the saved link and its position within this pinboard.
            let entry = PinboardEntry(clipboardItem: item, pinboard: board, displayOrder: record.displayOrder)
            entry.id = record.id
            entry.addedAt = record.addedAt
            context.insert(entry)
            summary.importedEntries += 1
        }

        // App exclusions (dedupe by bundle id)
        let existingExclusions = try context.fetch(FetchDescriptor<ExcludedApp>())
        var excludedIDs = Set(existingExclusions.map { $0.bundleId })
        for record in doc.exclusions {
            guard !excludedIDs.contains(record.bundleId) else { continue }
            context.insert(ExcludedApp(bundleId: record.bundleId, appName: record.appName))
            excludedIDs.insert(record.bundleId)
            summary.importedExclusions += 1
        }

        try context.save()
        return summary
    }
}
