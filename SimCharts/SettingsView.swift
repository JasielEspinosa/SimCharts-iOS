import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: CustomResource?
    @State private var editingIsNew = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    Picker("Theme", selection: $model.settings.theme) {
                        Text("Dark").tag("Dark")
                        Text("Light").tag("Light")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Charts folder") {
                    Text("Charts are saved in the SimCharts folder of the Files app (Files > On My iPhone > SimCharts), "
                        + "inside one folder per country and airport. You can also copy your own PDFs in there and they will show in the list.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Select which charts to download", isOn: $model.settings.selectWhichCharts)
                    Toggle("Add airport code to charts filename", isOn: $model.settings.addAirportCodeToFilename)
                    Toggle("Open the first chart after download", isOn: $model.settings.openAfterDownload)
                    Toggle("Wait 3 seconds between each airport", isOn: $model.settings.waitBetweenAirports)
                }

                Section {
                    Text("US airports (K..., PA.., PH.. etc.) use the FAA, Philippine airports (RP..) use VATPHIL and Hong Kong/Macao (VH.., VM..) "
                        + "use the Hong Kong eAIP automatically; a matching entry here overrides them. For any other country add a source: "
                        + "Prefix is the start of the ICAO code (e.g. EG or LFPG); the URL may contain {ICAO} / {icao}. "
                        + "'DirectPdf' = the URL is one PDF; 'ScanPage' = download every .pdf linked from that web page.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ForEach($model.settings.customResources) { $res in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(res.prefix.isEmpty ? "(no prefix)" : res.prefix) - \(res.label.isEmpty ? "(no label)" : res.label)")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(res.mode.rawValue): \(res.urlTemplate)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingIsNew = false
                                editing = res
                            }
                            Spacer()
                            Toggle("", isOn: $res.enabled).labelsHidden()
                        }
                    }
                    .onDelete { offsets in
                        model.settings.customResources.remove(atOffsets: offsets)
                    }

                    Button("Add resource") {
                        editingIsNew = true
                        editing = CustomResource(urlTemplate: "https://")
                    }
                } header: {
                    Text("Custom Resources")
                } footer: {
                    Text("Tap an entry to edit it, swipe left to delete it.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { res in
                ResourceEditor(initial: res) { saved in
                    if let i = model.settings.customResources.firstIndex(where: { $0.id == saved.id }) {
                        model.settings.customResources[i] = saved
                    } else {
                        model.settings.customResources.append(saved)
                    }
                    editing = nil
                } onCancel: {
                    editing = nil
                }
            }
        }
    }
}

private struct ResourceEditor: View {
    @State var draft: CustomResource
    let onSave: (CustomResource) -> Void
    let onCancel: () -> Void

    init(initial: CustomResource, onSave: @escaping (CustomResource) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: initial)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var valid: Bool {
        !draft.prefix.trimmed.isEmpty && draft.urlTemplate.trimmed.lowercased().hasPrefix("http")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ICAO prefix (e.g. EG)", text: $draft.prefix)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: draft.prefix) { _, new in
                            let cleaned = new.uppercased().trimmed
                            if cleaned != new { draft.prefix = cleaned }
                        }
                    TextField("Label", text: $draft.label)
                    TextField("URL template ({ICAO})", text: $draft.urlTemplate, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Picker("Mode", selection: $draft.mode) {
                        ForEach(SourceMode.allCases, id: \.self) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Custom resource")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        var d = draft
                        d.urlTemplate = d.urlTemplate.trimmed
                        onSave(d)
                    }
                    .disabled(!valid)
                }
            }
        }
    }
}
