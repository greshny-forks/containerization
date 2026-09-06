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

import Testing

@testable import sandboxy

@Suite("AgentDefinition")
struct AgentDefinitionTests {
    @Test("Codex is a built-in agent")
    func codexBuiltInDefinition() throws {
        let definition = try #require(AgentDefinition.builtIn["codex"])

        #expect(definition.displayName == "OpenAI Codex CLI")
        #expect(definition.baseImage == "docker.io/library/node:22-slim")
        #expect(definition.launchCommand == ["codex"])
        #expect(definition.mounts.isEmpty)
        #expect(
            Set(definition.environmentVariables)
                == ["CODEX_HOME=/root/.codex", "OPENAI_API_KEY", "IS_SANDBOX=1"]
        )
        #expect(
            Set(definition.allowedHosts)
                == ["*.openai.com", "*.chatgpt.com", "*.oaistatic.com", "*.oaiusercontent.com"]
        )
        #expect(
            definition.installCommands.contains {
                $0.contains("https://chatgpt.com/codex/install.sh")
                    && $0.contains("CODEX_NON_INTERACTIVE=1")
            }
        )
    }

    @Test("Codex runtime allowlist only includes OpenAI-owned hosts")
    func codexAllowlistMatchesOnlyOpenAIOwnedHosts() {
        let allowedHosts = AgentDefinition.codex.allowedHosts

        #expect(HostProxy.isAllowed(host: "openai.com", allowedHosts: allowedHosts))
        #expect(HostProxy.isAllowed(host: "api.openai.com", allowedHosts: allowedHosts))
        #expect(HostProxy.isAllowed(host: "chatgpt.com", allowedHosts: allowedHosts))
        #expect(HostProxy.isAllowed(host: "ab.chatgpt.com", allowedHosts: allowedHosts))
        #expect(HostProxy.isAllowed(host: "persistent.oaistatic.com", allowedHosts: allowedHosts))
        #expect(HostProxy.isAllowed(host: "files.oaiusercontent.com", allowedHosts: allowedHosts))
        #expect(!HostProxy.isAllowed(host: "github.com", allowedHosts: allowedHosts))
        #expect(!HostProxy.isAllowed(host: "registry.npmjs.org", allowedHosts: allowedHosts))
    }
}
