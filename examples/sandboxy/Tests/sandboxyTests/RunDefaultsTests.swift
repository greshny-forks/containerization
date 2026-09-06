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

@Suite("Per-agent run defaults")
struct RunDefaultsTests {
    private let definition = AgentDefinition(
        displayName: "Test", baseImage: "test", installCommands: [],
        launchCommand: ["test"], environmentVariables: [], mounts: [],
        allowedHosts: ["builtin.example"]
    )

    private func resolve(_ config: SandboxyConfig, _ args: [String] = [], agent: String = "agy") throws -> ResolvedRunConfiguration {
        try ResolvedRunConfiguration.resolve(
            config: config, agentName: agent, definition: definition,
            options: AgentOptions.parse(args))
    }

    @Test("Config loading preserves optional defaults and rejects invalid types")
    func configLoading() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try SandboxyConfig.load(configRoot: root).runDefaults == nil)
        let file = root.appendingPathComponent("config.json")
        try Data(#"{"defaultCPUs":8}"#.utf8).write(to: file)
        let old = try SandboxyConfig.load(configRoot: root)
        #expect(old.runDefaults == nil)
        #expect(old.defaultCPUs == 8)
        try Data(
            #"""
            {"runDefaults":{"agy":{"mounts":[{"hostPath":"~/skills","containerPath":"/skills"}]},
            "codex":{"allowHosts":["codex.example"]}}}
            """#.utf8
        ).write(to: file)
        let loaded = try SandboxyConfig.load(configRoot: root)
        #expect(loaded.defaultCPUs == SandboxyConfig.defaults.defaultCPUs)
        #expect(loaded.runDefaults?["agy"]?.mounts?.first?.readOnly == false)
        #expect(loaded.runDefaults?["codex"]?.allowHosts == ["codex.example"])
        try Data(#"{"runDefaults":{"agy":{"mounts":"invalid"}}}"#.utf8).write(to: file)
        #expect(throws: (any Error).self) { try SandboxyConfig.load(configRoot: root) }
    }

    @Test("CLI replaces an equivalent saved destination and preserves other mounts")
    func mountPrecedence() throws {
        let config = SandboxyConfig(runDefaults: [
            "agy": AgentRunDefaults(mounts: [
                AgentMount(hostPath: "~/skills", containerPath: "/skills/", readOnly: true),
                AgentMount(hostPath: "/tmp/docs", containerPath: "/docs", readOnly: true),
            ])
        ])
        let result = try resolve(config, ["--mount", "/tmp/test:/skills:rw"])
        #expect(
            result.mounts == [
                MountSpec(hostPath: "/tmp/docs", containerPath: "/docs", readOnly: true),
                MountSpec(hostPath: "/tmp/test", containerPath: "/skills", readOnly: false),
            ])
    }

    @Test("Hosts remain additive and agent defaults remain isolated")
    func hostsAndIsolation() throws {
        let config = SandboxyConfig(runDefaults: [
            "agy": AgentRunDefaults(allowHosts: ["agy.example", "builtin.example"]),
            "codex": AgentRunDefaults(allowHosts: ["codex.example"]),
        ])
        #expect(
            try resolve(config, ["--allow-hosts", "cli.example"]).allowedHosts
                == ["builtin.example", "agy.example", "cli.example"])
        #expect(try resolve(config, agent: "codex").allowedHosts == ["builtin.example", "codex.example"])
        #expect(try resolve(config, agent: "other").allowedHosts == ["builtin.example"])
    }

    @Test("Opt-out keeps CLI inputs and built-in hosts")
    func optOut() throws {
        let config = SandboxyConfig(runDefaults: [
            "agy": AgentRunDefaults(
                mounts: [AgentMount(hostPath: "/saved", containerPath: "/saved")],
                allowHosts: ["saved.example"])
        ])
        let result = try resolve(config, ["--no-run-defaults", "--mount", "/tmp/cli:/cli", "--allow-hosts", "cli.example"])
        #expect(result.mounts.map(\.containerPath) == ["/cli"])
        #expect(result.allowedHosts == ["builtin.example", "cli.example"])
    }

    @Test("Workspace is current directory or CLI, and host tildes expand")
    func paths() throws {
        let config = SandboxyConfig(runDefaults: [
            "agy": AgentRunDefaults(
                mounts: [AgentMount(hostPath: "~/skills", containerPath: "/skills")])
        ])
        let home = FileManager.default.homeDirectoryForCurrentUser
        let result = try resolve(config)
        #expect(result.workspace == FileManager.default.currentDirectoryPath)
        #expect(result.mounts.first?.hostPath == home.appendingPathComponent("skills").path(percentEncoded: false))
        let cli = try resolve(config, ["-w", "~/work", "--mount", "~/test:/skills"])
        #expect(cli.workspace == home.appendingPathComponent("work").path(percentEncoded: false))
        #expect(cli.mounts.first?.hostPath == home.appendingPathComponent("test").path(percentEncoded: false))
        #expect(try resolve(.defaults).mounts.isEmpty)
    }

    @Test("Ambiguous mounts fail before launch")
    func duplicateMounts() throws {
        #expect(throws: ValidationError.self) {
            try resolve(.defaults, ["-m", "/tmp/a:/skills", "-m", "/tmp/b:/skills/"])
        }
        let config = SandboxyConfig(runDefaults: [
            "agy": AgentRunDefaults(mounts: [
                AgentMount(hostPath: "/a", containerPath: "/skills"),
                AgentMount(hostPath: "/b", containerPath: "/skills/./"),
            ])
        ])
        #expect(throws: ValidationError.self) { try resolve(config) }
        #expect(throws: ValidationError.self) {
            try resolve(.defaults, ["-m", "/tmp/a:relative"])
        }
    }

    @Test("Each run resolves the current config even with the same instance name")
    func refreshedDefaults() throws {
        var config = SandboxyConfig(runDefaults: ["agy": AgentRunDefaults(allowHosts: ["old.example"])])
        #expect(try resolve(config, ["--name", "existing"]).allowedHosts == ["builtin.example", "old.example"])
        config.runDefaults?["agy"] = AgentRunDefaults(
            mounts: [AgentMount(hostPath: "/new", containerPath: "/new")],
            allowHosts: ["new.example"])
        let next = try resolve(config, ["--name", "existing"])
        #expect(next.allowedHosts == ["builtin.example", "new.example"])
        #expect(next.mounts.first?.hostPath == "/new")
    }

    @Test("Run flags work before and after agent, with passthrough escaping")
    func flags() throws {
        let before = try Sandboxy.Run.parse(["--dry-run", "--no-run-defaults", "agy"])
        #expect(before.options.dryRun && before.options.noRunDefaults)
        let after = try Sandboxy.Run.parse(["agy", "--dry-run", "--no-run-defaults"])
        let parsed = parseRunPassthrough(after.passthroughArgs)
        #expect(parsed.dryRun && parsed.noRunDefaults)
        #expect(parsed.agentArguments.isEmpty)
        let forwarded = try Sandboxy.Run.parse(["agy", "--", "--dry-run", "--no-run-defaults"])
        let escaped = parseRunPassthrough(forwarded.passthroughArgs)
        #expect(!escaped.dryRun && !escaped.noRunDefaults)
        #expect(escaped.agentArguments == ["--dry-run", "--no-run-defaults"])
    }

    @Test("Dry run returns before kernel, environment or instance work")
    func dryRunDoesNotLaunch() async throws {
        // A normal run would fail resolving this unset environment variable or missing kernel.
        let options = try AgentOptions.parse([
            "--dry-run", "--kernel", "/nonexistent-sandboxy-test-kernel",
            "--env", "SANDBOXY_UNSET_TEST_" + UUID().uuidString,
        ])
        try await runAgent(
            config: .defaults, agentName: "agy", definition: definition,
            options: options, passthroughArgs: [])
    }

    @Test("Preview includes filtering mode and skipped agent mounts")
    func preview() throws {
        let definition = AgentDefinition(
            displayName: "Test", baseImage: "test", installCommands: [], launchCommand: [],
            environmentVariables: [],
            mounts: [
                AgentMount(hostPath: "/missing-sandboxy-test-path", containerPath: "/agent", readOnly: true)
            ], allowedHosts: ["builtin.example"])
        let resolved = try ResolvedRunConfiguration.resolve(
            config: .defaults, agentName: "agy", definition: definition,
            options: AgentOptions.parse(["--dry-run", "--no-network-filter"]))
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(resolved)) as? [String: Any])
        #expect(json["networkFiltering"] as? Bool == false)
        #expect(resolved.agentMounts.first?.skippedReason == "host path not found")
        #expect(resolved.allowedHosts == ["builtin.example"])
    }
}
