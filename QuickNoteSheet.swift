import SwiftUI

/// Change the project, note and hashtags between shots without opening Settings.
struct QuickNoteSheet: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var newProject = ""

    private var trimmedNew: String { newProject.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !settings.cfg.projects.isEmpty {
                        Picker("Project", selection: $settings.cfg.project) {
                            Text("None").tag("")
                            ForEach(settings.cfg.projects, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    HStack {
                        TextField("New project name", text: $newProject)
                        Button("Add") {
                            if !settings.cfg.projects.contains(trimmedNew) {
                                settings.cfg.projects.append(trimmedNew)
                            }
                            settings.cfg.project = trimmedNew
                            newProject = ""
                        }
                        .disabled(trimmedNew.isEmpty)
                    }
                } header: {
                    Text("Project")
                } footer: {
                    Text("Project, note and hashtags are shown on photos with the Advanced template.")
                }

                Section("Note") {
                    TextField("Note for the next photos", text: $settings.cfg.note, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section("Hashtags") {
                    TextField("site1, inspection", text: $settings.cfg.hashtags)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Quick note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
