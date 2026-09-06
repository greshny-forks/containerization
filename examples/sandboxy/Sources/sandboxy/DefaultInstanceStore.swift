//===----------------------------------------------------------------------===//
// Copyright © 2026 Apple Inc. and the Containerization project authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import Foundation

/// Persistent per-agent references to named instances.
struct DefaultInstanceStore: Codable, Sendable {
    private(set) var defaults: [String: String] = [:]

    static func statePath(appRoot: URL) -> URL {
        appRoot.appendingPathComponent("default-instances.json")
    }

    static func load(appRoot: URL) throws -> DefaultInstanceStore {
        let path = statePath(appRoot: appRoot)
        guard FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) else {
            return DefaultInstanceStore()
        }
        return try JSONDecoder().decode(DefaultInstanceStore.self, from: Data(contentsOf: path))
    }

    func save(appRoot: URL) throws {
        let path = Self.statePath(appRoot: appRoot)
        if defaults.isEmpty {
            if FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: path)
            }
            return
        }

        try FileManager.default.createDirectory(at: appRoot, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: path, options: .atomic)
    }

    func instanceName(for agentName: String) -> String? {
        defaults[agentName]
    }

    mutating func set(instanceName: String, for agentName: String) {
        defaults[agentName] = instanceName
    }

    @discardableResult
    mutating func removeDefault(for agentName: String) -> Bool {
        defaults.removeValue(forKey: agentName) != nil
    }

    @discardableResult
    mutating func removeDefaults(referencing instanceName: String) -> Bool {
        let oldCount = defaults.count
        defaults = defaults.filter { $0.value != instanceName }
        return defaults.count != oldCount
    }

    mutating func removeAll() {
        defaults.removeAll()
    }
}
