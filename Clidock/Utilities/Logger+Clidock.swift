// Modified for Clidock on 2026-11-27. SPDX-License-Identifier: GPL-3.0-only
import os.log

extension Logger {
    /// A logger in Clidock's subsystem.
    /// - Parameter category: the part of the app that logs, such as "StoreManager"
    nonisolated init(clidockCategory category: String) {
        self.init(subsystem: AppIdentity.namespace, category: category)
    }
}
