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

import ContainerizationOS
import Foundation

enum TerminalControl {
    private static let enterAlternateScreen = "\u{1b}[?1049h\u{1b}[2J\u{1b}[H"
    static let resetModes =
        "\u{1b}[0m\u{1b}[?25h\u{1b}[?2004l\u{1b}[?1000l\u{1b}[?1002l\u{1b}[?1003l\u{1b}[?1006l"
    private static let leaveAlternateScreen = "\u{1b}[?1049l"

    static func startSequence(useAlternateScreen: Bool) -> String {
        useAlternateScreen ? enterAlternateScreen : ""
    }

    static func restoreSequence(useAlternateScreen: Bool) -> String {
        (useAlternateScreen ? leaveAlternateScreen : "") + resetModes
    }
}

/// Owns the host terminal state for one interactive agent process.
struct InteractiveTerminalSession {
    let terminal: Terminal
    let useAlternateScreen: Bool
    private var started = false

    init(terminal: Terminal, useAlternateScreen: Bool) {
        self.terminal = terminal
        self.useAlternateScreen = useAlternateScreen
    }

    mutating func start() throws {
        let startSequence = TerminalControl.startSequence(useAlternateScreen: useAlternateScreen)
        if !startSequence.isEmpty {
            try terminal.write(Data(startSequence.utf8))
        }

        do {
            try terminal.setraw()
            started = true
        } catch {
            let restoreSequence = TerminalControl.restoreSequence(
                useAlternateScreen: useAlternateScreen)
            try? terminal.write(Data(restoreSequence.utf8))
            throw error
        }
    }

    mutating func restore() {
        guard started else { return }
        terminal.tryReset()
        let restoreSequence = TerminalControl.restoreSequence(
            useAlternateScreen: useAlternateScreen)
        try? terminal.write(Data(restoreSequence.utf8))
        started = false
    }
}
