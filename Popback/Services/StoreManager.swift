// Modified for Popback on 2026-11-27. SPDX-License-Identifier: GPL-3.0-only
import Foundation
import os.log

enum StoreManager {

    static let logger = Logger(popbackCategory: "StoreManager")

    /// Directory SwiftData uses for externally stored clipboard payloads.
    private static let newSupportDirName = ".Popback_SUPPORT"

    /// Returns the library inside Popback's own Application Support directory.
    /// - Parameter applicationSupport: Root directory, overridable for isolated tests.
    static func resolveStoreURL(in applicationSupport: URL = URL.applicationSupportDirectory) -> URL {
        /// Each installation uses the namespace registered by this application.
        let directory = applicationSupport.appending(component: AppIdentity.namespace, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(component: "Popback.store")
    }

    /// store + WAL + SHM + external storage 모두 백업
    static func backupStore(at storeURL: URL) {
        let fm = FileManager.default
        let dir = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent

        for suffix in ["", "-wal", "-shm"] {
            let src = dir.appendingPathComponent(name + suffix)
            let dst = dir.appendingPathComponent(name + ".backup" + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.removeItem(at: dst)
            try? fm.copyItem(at: src, to: dst)
        }

        let srcSupport = dir.appendingPathComponent(newSupportDirName)
        let dstSupport = dir.appendingPathComponent(newSupportDirName + ".backup")
        if fm.fileExists(atPath: srcSupport.path) {
            try? fm.removeItem(at: dstSupport)
            try? fm.copyItem(at: srcSupport, to: dstSupport)
        }

        logger.info("Backup created")
    }

    /// 손상 복구용: store 및 관련 파일을 지우지 않고 옆으로 옮긴다.
    /// 삭제하면 다음 실행의 backupStore()가 빈 store로 백업을 덮어써서 기록이 영구히 사라진다.
    /// 설정 오류처럼 파일이 멀쩡한데 열기만 실패한 경우에도 복구할 수 있게 남겨 둔다.
    static func quarantineStore(at storeURL: URL) {
        let fm = FileManager.default
        let dir = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        let stamp = Int(Date().timeIntervalSince1970)
        let quarantine = dir.appendingPathComponent("Quarantine-\(stamp)", isDirectory: true)
        try? fm.createDirectory(at: quarantine, withIntermediateDirectories: true)

        for suffix in ["", "-wal", "-shm", ".backup", ".backup-wal", ".backup-shm"] {
            let src = dir.appendingPathComponent(name + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            if suffix.hasPrefix(".backup") {
                try? fm.copyItem(at: src, to: quarantine.appendingPathComponent(name + suffix))
            } else {
                try? fm.moveItem(at: src, to: quarantine.appendingPathComponent(name + suffix))
            }
        }
        let support = dir.appendingPathComponent(newSupportDirName)
        if fm.fileExists(atPath: support.path) {
            try? fm.moveItem(at: support, to: quarantine.appendingPathComponent(newSupportDirName))
        }
        logger.error("Moved unreadable store to \(quarantine.path)")
    }
}
