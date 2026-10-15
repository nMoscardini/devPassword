import SwiftUI
import VaultCore

/// Shows only the characters a site asks for (decision 0007 amendment). Never the whole secret,
/// never the clipboard. Hides again after `showSeconds`. Records the action, not the positions.
struct CharacterPickView: View {
    @EnvironmentObject var model: AppModel
    let label: String
    let value: String
    @State private var positionsText = ""
    @State private var picks: [CharacterPicker.Pick] = []
    @State private var message: String?
    @State private var hideTask: Task<Void, Never>?
    static let showSeconds = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick characters: \(label)").font(.headline)
            Text("Type the positions asked for, such as 2 5 7. \(value.count) characters.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Positions", text: $positionsText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit(show)
                Button("Show", action: show)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            if !picks.isEmpty {
                HStack(spacing: 10) {
                    ForEach(picks, id: \.position) { p in
                        VStack(spacing: 4) {
                            Text(p.character == " " ? "\u{2423}" : p.character)
                                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                                .frame(minWidth: 40)
                            Text(ordinal(p.position)).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Text("Hides after \(Self.showSeconds) seconds.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(minWidth: 320, alignment: .leading)
        .onDisappear { clear() }
    }

    private func show() {
        hideTask?.cancel()
        do {
            picks = try CharacterPicker.pick(value, positionsText: positionsText)
            message = nil
            model.auditCharactersPicked()
            model.touch()
            hideTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Self.showSeconds) * 1_000_000_000)
                if !Task.isCancelled { picks = [] }
            }
        } catch let e as CharacterPicker.PickError {
            picks = []
            message = e.description
        } catch {
            picks = []
            message = "Could not read those positions."
        }
    }

    private func clear() {
        hideTask?.cancel()
        picks = []
        positionsText = ""
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        if (11...13).contains(n % 100) {
            suffix = "th"
        } else {
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}
