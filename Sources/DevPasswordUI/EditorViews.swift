import SwiftUI
import VaultCore

struct EntryEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    private let original: Entry
    @State private var draft: Entry
    @State private var urlsText: String
    @State private var tagsText: String
    @State private var showGenerator = false

    init(entry: Entry) {
        original = entry
        _draft = State(initialValue: entry)
        _urlsText = State(initialValue: entry.urls.joined(separator: "\n"))
        _tagsText = State(initialValue: entry.tags.joined(separator: ", "))
    }

    private var isNew: Bool { !model.entries.contains { $0.id == original.id } }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                }
                if draft.type == .login {
                    Section("Websites, one per line") {
                        TextEditor(text: $urlsText)
                            .font(.body)
                            .frame(minHeight: 44)
                    }
                }
                if !draft.type.fieldDefs.isEmpty {
                    Section(draft.type.displayName) {
                        ForEach(draft.type.fieldDefs, id: \.key) { def in
                            FieldEditor(label: def.label, placeholder: def.placeholder,
                                        concealed: def.kind == .concealed,
                                        value: binding(def.key),
                                        onGenerate: def.key == "password" ? { showGenerator = true } : nil)
                        }
                    }
                }
                Section("Custom fields") {
                    ForEach($draft.customFields) { $f in
                        HStack {
                            TextField("Label", text: $f.label).frame(width: 140)
                            Picker("", selection: $f.kind) {
                                ForEach([FieldKind.text, .concealed, .date], id: \.self) { k in Text(k.label).tag(k) }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                            FieldEditor(label: "Value", placeholder: f.kind == .date ? "YYYY-MM-DD" : "",
                                        concealed: f.kind == .concealed, value: $f.value, onGenerate: nil)
                            Button {
                                let id = f.id
                                draft.customFields.removeAll { $0.id == id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("Add Field") {
                        draft.customFields.append(CustomField(label: "", value: ""))
                    }
                }
                Section("Notes") {
                    TextEditor(text: $draft.notes)
                        .font(.body)
                        .frame(minHeight: 80)
                    if draft.type == .secureNote {
                        Toggle("Conceal note text until revealed", isOn: $draft.notesConcealed)
                    }
                }
                Section {
                    TextField("Tags, separated by commas", text: $tagsText)
                    Toggle("Favourite", isOn: $draft.favourite)
                }
            }
            .formStyle(.grouped)

            let warnings = EntryValidation.warnings(for: assembled())
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(warnings, id: \.self) { w in
                        Label(w, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    model.save(assembled())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 600)
        .navigationTitle(isNew ? "New \(draft.type.displayName)" : "Edit \(original.title)")
        .sheet(isPresented: $showGenerator) {
            GeneratorView { pw in draft[field: "password"] = pw }
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { draft[field: key] }, set: { draft[field: key] = $0 })
    }

    /// The draft with text fields parsed. Keeps the old password when it changes (spec section 7).
    private func assembled() -> Entry {
        var e = draft
        e.title = e.title.trimmingCharacters(in: .whitespaces)
        e.urls = urlsText.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        e.tags = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        e.customFields = e.customFields.filter { !$0.label.isEmpty || !$0.value.isEmpty }
            .map { f in var f = f; if f.label.isEmpty { f.label = "Field" }; return f }
        let old = original[field: "password"]
        if e.type == .login, !old.isEmpty, old != e[field: "password"] {
            e.previousPassword = PreviousValue(value: old, changedAt: Date())
        }
        if e.type != .secureNote { e.notesConcealed = false }
        return e
    }
}

struct FieldEditor: View {
    let label: String
    let placeholder: String
    let concealed: Bool
    @Binding var value: String
    var onGenerate: (() -> Void)?
    @State private var show = false

    var body: some View {
        HStack {
            if concealed && !show {
                SecureField(label, text: $value, prompt: Text(placeholder))
            } else {
                TextField(label, text: $value, prompt: Text(placeholder))
                    .font(concealed ? .body.monospaced() : .body)
            }
            if concealed {
                Button { show.toggle() } label: { Image(systemName: show ? "eye.slash" : "eye") }
                    .buttonStyle(.borderless)
            }
            if let onGenerate {
                Button { onGenerate() } label: { Image(systemName: "wand.and.stars") }
                    .buttonStyle(.borderless)
                    .help("Generate a password")
            }
        }
    }
}

struct GeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    var onUse: ((String) -> Void)?
    @State private var options = PasswordOptions()
    @State private var value = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Generate Password").font(.title2.bold())
            Text(value.isEmpty ? " " : value)
                .font(.system(.title3, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            if let problem { Text(problem).foregroundStyle(.orange) }
            HStack {
                Text("Length \(options.length)").frame(width: 80, alignment: .leading)
                Slider(value: Binding(get: { Double(options.length) }, set: { options.length = Int($0) }), in: 8...64, step: 1)
            }
            HStack(spacing: 18) {
                Toggle("a-z", isOn: $options.lowercase)
                Toggle("A-Z", isOn: $options.uppercase)
                Toggle("0-9", isOn: $options.digits)
                Toggle("Symbols", isOn: $options.symbols)
            }
            Toggle("Avoid look-alike characters (I, l, 1, O, 0)", isOn: $options.avoidLookAlikes)
            TextField("Never use these characters", text: $options.excluded)
                .textFieldStyle(.roundedBorder)
            Text("Saving a password here does not change it on the website. Change it there too.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Regenerate", action: regenerate)
                Button("Copy") { Clipboard.copy(value, concealed: true) }
                    .disabled(value.isEmpty)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if let onUse {
                    Button("Use Password") {
                        onUse(value)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(value.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear(perform: regenerate)
        .onChange(of: options) { regenerate() }
    }

    private func regenerate() {
        do {
            value = try PasswordGenerator.generate(options)
            problem = nil
        } catch {
            value = ""
            problem = error.localizedDescription
        }
    }
}
