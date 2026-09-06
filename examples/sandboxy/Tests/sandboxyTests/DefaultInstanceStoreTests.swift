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

import ArgumentParser
import Foundation
import Testing

@testable import sandboxy

@Suite("Default instances")
struct DefaultInstanceStoreTests {
    @Test("set-default is parsed before or after the agent")
    func setDefaultParsing() throws {
        let options = try AgentOptions.parse(["--set-default"])
        #expect(options.setDefault)

        let trailing = parseRunPassthrough(["--set-default", "--", "--version"])
        #expect(trailing == ParsedRunPassthrough(setDefault: true, agentArguments: ["--version"]))

        let escaped = parseRunPassthrough(["--", "--set-default"])
        #expect(escaped == ParsedRunPassthrough(setDefault: false, agentArguments: ["--set-default"]))
    }

    @Test("set-default cannot be combined with rm")
    func setDefaultCannotBeRemoved() throws {
        let options = try AgentOptions.parse(["--set-default", "--rm"])
        #expect(throws: ValidationError.self) {
            try validateInstanceOptions(options)
        }
    }

    @Test("defaults persist independently for each agent")
    func defaultsPersistPerAgent() throws {
        let appRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: appRoot) }

        var store = DefaultInstanceStore()
        store.set(instanceName: "agy-main", for: "agy")
        store.set(instanceName: "codex-main", for: "codex")
        try store.save(appRoot: appRoot)

        let loaded = try DefaultInstanceStore.load(appRoot: appRoot)
        #expect(loaded.instanceName(for: "agy") == "agy-main")
        #expect(loaded.instanceName(for: "codex") == "codex-main")
    }

    @Test("explicit name takes priority over an agent default")
    func explicitNameTakesPriority() throws {
        let appRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: appRoot) }

        var store = DefaultInstanceStore()
        store.set(instanceName: "codex-default", for: "codex")
        try store.save(appRoot: appRoot)

        let resolved = try resolveInstanceName(
            agentName: "codex",
            explicitName: "codex-explicit",
            appRoot: appRoot
        )
        #expect(resolved == "codex-explicit")
    }

    @Test("a valid default resolves to its preserved rootfs")
    func validDefaultResolves() throws {
        let appRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: appRoot) }

        let namedDir = InstanceState.namedRootfsDir(appRoot: appRoot)
        try FileManager.default.createDirectory(at: namedDir, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(
            atPath: InstanceState.namedRootfsPath(appRoot: appRoot, name: "codex-main")
                .path(percentEncoded: false),
            contents: Data()
        )

        var store = DefaultInstanceStore()
        store.set(instanceName: "codex-main", for: "codex")
        try store.save(appRoot: appRoot)

        let resolved = try resolveInstanceName(
            agentName: "codex",
            explicitName: nil,
            appRoot: appRoot
        )
        #expect(resolved == "codex-main")
    }

    @Test("a stale default is removed and replaced with an auto-generated name")
    func staleDefaultIsRemoved() throws {
        let appRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: appRoot) }

        var store = DefaultInstanceStore()
        store.set(instanceName: "missing", for: "codex")
        store.set(instanceName: "agy-main", for: "agy")
        try store.save(appRoot: appRoot)

        let date = Date(timeIntervalSince1970: 0)
        let resolved = try resolveInstanceName(
            agentName: "codex",
            explicitName: nil,
            appRoot: appRoot,
            date: date
        )

        #expect(resolved == generatedInstanceName(agentName: "codex", date: date))
        let reloaded = try DefaultInstanceStore.load(appRoot: appRoot)
        #expect(reloaded.instanceName(for: "codex") == nil)
        #expect(reloaded.instanceName(for: "agy") == "agy-main")
    }

    @Test("removing an instance clears every default that references it")
    func removalClearsDefaults() throws {
        let appRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: appRoot) }

        var store = DefaultInstanceStore()
        store.set(instanceName: "shared", for: "agy")
        store.set(instanceName: "shared", for: "codex")
        store.set(instanceName: "claude-main", for: "claude")
        try store.save(appRoot: appRoot)

        let instance = InstanceState(
            id: "codex-123",
            name: "shared",
            agent: "codex",
            workspace: "/tmp/workspace",
            status: .stopped,
            createdAt: Date(),
            cpus: 4,
            memoryMB: 4096
        )
        try instance.save(appRoot: appRoot)
        let namedDir = InstanceState.namedRootfsDir(appRoot: appRoot)
        try FileManager.default.createDirectory(at: namedDir, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(
            atPath: InstanceState.namedRootfsPath(appRoot: appRoot, name: "shared")
                .path(percentEncoded: false),
            contents: Data()
        )

        try instance.removeAll(appRoot: appRoot)

        let reloaded = try DefaultInstanceStore.load(appRoot: appRoot)
        #expect(reloaded.instanceName(for: "agy") == nil)
        #expect(reloaded.instanceName(for: "codex") == nil)
        #expect(reloaded.instanceName(for: "claude") == "claude-main")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandboxy-default-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
