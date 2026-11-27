import SwiftData
import XCTest

@MainActor
final class LibraryBackupTests: XCTestCase {
    /// Creates a separate local library for each side of a restore.
    private func library() throws -> ModelContainer {
        try ModelContainer(for: ClipboardItem.self, Pinboard.self, PinboardEntry.self, ExcludedApp.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    func testRestorePreservesSourcesBoardIdentityOrderAndExclusions() throws {
        /// Seed includes legal duplicates that must retain distinct identities.
        let source = try library()
        for index in 0..<2 {
            /// Two apps copied identical bytes.
            let clip = ClipboardItem(contentType: .plainText, rawData: Data("hello".utf8), textContent: "hello",
                                     sourceAppBundleId: "test.app.\(index)", contentHash: "same")
            clip.isPinned = true
            /// A display name can be reused for different boards.
            let board = Pinboard(name: "Notes", displayOrder: index)
            source.mainContext.insert(board)
            source.mainContext.insert(clip)
            source.mainContext.insert(PinboardEntry(clipboardItem: clip, pinboard: board, displayOrder: index))
        }
        source.mainContext.insert(ExcludedApp(bundleId: "test.private", appName: "Private"))
        try source.mainContext.save()

        /// Transfer the same file twice to exercise the merge behavior.
        let data = try TransferService.exportDocument(context: source.mainContext)
        // Existing 0.1.0 archives and all three app variants use this wire-format identifier.
        XCTAssertEqual(try JSONDecoder().decode(TransferDocument.self, from: data).format,
                       "io.github.share-man-man.popback.backup")
        /// Empty destination with independent object and relationship storage.
        let target = try library()
        /// Result of the first restore.
        let result = try TransferService.importDocument(data, context: target.mainContext)
        XCTAssertEqual(result.importedItems, 2)
        XCTAssertEqual(result.importedBoards, 2)
        XCTAssertEqual(result.importedEntries, 2)
        XCTAssertEqual(result.importedExclusions, 1)
        /// Repeat restores should only skip records already present.
        let repeatResult = try TransferService.importDocument(data, context: target.mainContext)
        XCTAssertEqual(repeatResult.skippedItems, 2)
        XCTAssertEqual(repeatResult.importedEntries, 0)
        /// Compare both stores through their persisted models, including entry order.
        let boards = try target.mainContext.fetch(FetchDescriptor<Pinboard>(sortBy: [SortDescriptor(\.displayOrder)]))
        XCTAssertEqual(boards.count, 2)
        for (index, board) in boards.enumerated() {
            XCTAssertEqual(board.name, "Notes")
            XCTAssertEqual(board.entries.count, 1)
            XCTAssertEqual(board.entries.first?.displayOrder, index)
            XCTAssertEqual(board.entries.first?.clipboardItem?.sourceAppBundleId, "test.app.\(index)")
            XCTAssertEqual(board.entries.first?.clipboardItem?.rawData, Data("hello".utf8))
        }
        XCTAssertEqual(try target.mainContext.fetch(FetchDescriptor<ExcludedApp>()).map(\.bundleId), ["test.private"])
    }

    func testRejectsForeignMissingAndFutureFormatsBeforeMerging() throws {
        /// Populated library that an incompatible document must leave intact.
        let target = try library()
        target.mainContext.insert(ExcludedApp(bundleId: "test.keep", appName: "Keep"))
        try target.mainContext.save()
        for header in [["format": "foreign", "version": 1], ["version": 1],
                       ["format": AppIdentity.backupFormat, "version": 2]] as [[String: Any]] {
            /// A complete empty archive apart from its incompatible header.
            let document = header.merging(["items": [], "pinboards": [], "entries": [], "exclusions": [], "exportedAt": 0]) { first, _ in first }
            /// JSON input from a different app or schema.
            let data = try JSONSerialization.data(withJSONObject: document)
            XCTAssertThrowsError(try TransferService.importDocument(data, context: target.mainContext)) { error in
                XCTAssertTrue(error is TransferService.BackupError)
            }
        }
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<ExcludedApp>()), 1)
    }

    func testBrokenBoardLinkRollsBackTheEntireImport() throws {
        /// A document containing one clip and one broken membership.
        let source = try library()
        source.mainContext.insert(ClipboardItem(contentType: .plainText, rawData: Data([1]), contentHash: "sample"))
        /// Decode and alter a genuine export to exercise an error after insertion.
        let encoded = try TransferService.exportDocument(context: source.mainContext)
        var doc = try JSONDecoder().decode(TransferDocument.self, from: encoded)
        doc.entries.append(.init(id: UUID(), pinboardID: UUID(), itemID: doc.items[0].id,
                                 displayOrder: 0, addedAt: Date()))

        /// Existing exclusions in the receiving library must survive the failure.
        let target = try library()
        target.mainContext.insert(ExcludedApp(bundleId: "test.private", appName: "Private"))
        try target.mainContext.save()
        XCTAssertThrowsError(try TransferService.importDocument(JSONEncoder().encode(doc), context: target.mainContext))
        XCTAssertFalse(target.mainContext.hasChanges)
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<ClipboardItem>()), 0)
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<ExcludedApp>()), 1)
    }

    func testFirstLaunchLeavesOtherStoresUntouched() throws {
        /// Isolated Application Support root containing an unrelated database.
        let root = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        /// Existing file must survive the new application's first launch.
        let other = root.appending(component: "default.store")
        try Data("unrelated".utf8).write(to: other)
        XCTAssertEqual(StoreManager.resolveStoreURL(in: root).path,
                       root.appending(path: "\(AppIdentity.namespace)/Popback.store").path)
        XCTAssertEqual(try Data(contentsOf: other), Data("unrelated".utf8))
    }
}
