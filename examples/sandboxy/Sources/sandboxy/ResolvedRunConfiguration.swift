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

/// Resolved before any instance or VM work, for both normal launches and previews.
struct ResolvedRunConfiguration: Encodable {
    let agent: String
    let workspace: String
    /// Additional mounts after merging user defaults and CLI.
    let mounts: [MountSpec]
    let agentMounts: [AgentMountPreview]
    let allowedHosts: [String]
    let networkFiltering: Bool

    struct AgentMountPreview: Encodable {
        let hostPath: String
        let containerPath: String
        let readOnly: Bool
        let skippedReason: String?
    }

    static func resolve(
        config: SandboxyConfig,
        agentName: String,
        definition: AgentDefinition,
        options: AgentOptions
    ) throws -> ResolvedRunConfiguration {
        let defaults = options.noRunDefaults ? nil : config.runDefaults?[agentName]
        let defaultMounts = (defaults?.mounts ?? []).map {
            MountSpec(
                hostPath: URL(
                    fileURLWithPath: ($0.hostPath as NSString).expandingTildeInPath,
                    relativeTo: .currentDirectory()
                ).absoluteURL.path(percentEncoded: false),
                containerPath: $0.containerPath,
                readOnly: $0.readOnly
            )
        }
        let cliMounts = try options.mount.map { try MountSpec.parse($0) }
        try validateUniqueDestinations(defaultMounts, source: "runDefaults")
        try validateUniqueDestinations(cliMounts, source: "--mount")
        let cliDestinations = Set(cliMounts.map { destinationKey($0.containerPath) })
        let mounts = defaultMounts.filter { !cliDestinations.contains(destinationKey($0.containerPath)) } + cliMounts

        var seenHosts = Set<String>()
        let allowedHosts = (definition.allowedHosts + (defaults?.allowHosts ?? []) + options.allowHosts)
            .filter { seenHosts.insert($0).inserted }
        let agentMounts = definition.mounts.map { mount in
            AgentMountPreview(
                hostPath: mount.resolvedHostPath,
                containerPath: mount.containerPath,
                readOnly: mount.readOnly,
                skippedReason: options.noAgentMounts
                    ? "--no-agent-mounts"
                    : (FileManager.default.fileExists(atPath: mount.resolvedHostPath) ? nil : "host path not found")
            )
        }
        return ResolvedRunConfiguration(
            agent: agentName,
            workspace: options.workspace ?? FileManager.default.currentDirectoryPath,
            mounts: mounts,
            agentMounts: agentMounts,
            allowedHosts: allowedHosts,
            networkFiltering: !options.noNetworkFilter
        )
    }

    private static func destinationKey(_ path: String) -> String {
        // Normalize Linux path components lexically, without resolving host symlinks.
        var components: [Substring] = []
        for component in path.split(separator: "/") {
            if component == "." { continue }
            if component == ".." {
                if !components.isEmpty { components.removeLast() }
            } else {
                components.append(component)
            }
        }
        return "/" + components.joined(separator: "/")
    }

    private static func validateUniqueDestinations(_ mounts: [MountSpec], source: String) throws {
        var destinations = Set<String>()
        for mount in mounts {
            guard mount.containerPath.hasPrefix("/") else {
                throw ValidationError("Mount destination must be absolute: \(mount.containerPath)")
            }
            guard destinations.insert(destinationKey(mount.containerPath)).inserted else {
                throw ValidationError("Duplicate mount destination in \(source): \(mount.containerPath)")
            }
        }
    }
}
