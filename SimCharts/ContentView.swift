import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var text = ""
    @State private var showSettings = false
    @State private var showNotes = false
    @State private var showAbout = false
    @State private var deleteTarget: TreeNode?
    @FocusState private var icaoFocused: Bool
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                topRow
                chartsCard
                Text(model.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 10) {
                        Image("Mark")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        Text("SimCharts").font(.headline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Settings") { showSettings = true }
                        Button("Refresh list") { model.refreshTree() }
                        Button("Notes") { showNotes = true }
                        Button("About") { showAbout = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showNotes) { NotesView() }
        .sheet(isPresented: selectionBinding) {
            if let airports = model.selection {
                SelectChartsView(
                    airports: airports,
                    onConfirm: { model.confirmSelection($0) },
                    onCancel: { model.cancelSelection() }
                )
            }
        }
        .fullScreenCover(item: $model.openFile) { file in PDFViewerScreen(file: file) }
        .alert("SimCharts", isPresented: $showAbout) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Version v\(appVersion)\nCreated by 97Espi\n\nDownloads airport PDF charts for flight simulation use only. Not for real-world navigation.")
        }
        .alert("SimCharts", isPresented: problemsBinding) {
            Button("OK", role: .cancel) { model.clearProblems() }
        } message: {
            Text(model.problems.joined(separator: "\n\n"))
        }
        .alert("Delete folder?", isPresented: deleteBinding, presenting: deleteTarget) { node in
            Button("Delete", role: .destructive) { model.deleteFolder(node) }
            Button("Cancel", role: .cancel) {}
        } message: { node in
            Text("Delete \"\(node.name)\" and everything in it (\(countFiles(node)) file(s))? This cannot be undone.")
        }
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
    }

    private var selectionBinding: Binding<Bool> {
        Binding(
            get: { model.selection != nil },
            set: { shown in if !shown { model.cancelSelection() } }
        )
    }

    private var problemsBinding: Binding<Bool> {
        Binding(
            get: { !model.problems.isEmpty },
            set: { shown in if !shown { model.clearProblems() } }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { shown in if !shown { deleteTarget = nil } }
        )
    }

    // MARK: ICAO codes + Download button

    private var topRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("ICAO codes", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($icaoFocused)
                    .disabled(model.running)
                    .onChange(of: text) { _, new in
                        let up = new.uppercased()
                        if up != new { text = up }
                    }
                    .onSubmit { startOrCancel() }
                Text("Separate with spaces or commas")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button(action: startOrCancel) {
                Text(model.running ? "Cancel" : "Download\nCharts")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 72)
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 14)
        }
    }

    private func startOrCancel() {
        icaoFocused = false
        model.startDownload(text)
    }

    // MARK: Downloaded Charts card

    private var chartsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.isSearching ? "Downloaded Charts (\(model.matchCount) match)" : "Downloaded Charts")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()

            searchField
            Divider()

            if model.running { loadingBanner; Divider() }

            Group {
                if model.rows.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(model.rows) { row in
                            treeRow(row)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack(spacing: 8) {
                Button { model.collapseAll() } label: { Text("Collapse All").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Button { model.expandSelected() } label: { Text("Expand Selected").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
            .padding(8)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search charts (e.g. RJTT ILS 34)", text: $model.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var loadingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.status).font(.subheadline).lineLimit(2)
                    if model.progressTotal > 0 {
                        Text("\(model.progressDone) of \(model.progressTotal) files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if model.progressTotal > 0 {
                ProgressView(value: Double(model.progressDone), total: Double(model.progressTotal))
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if model.isSearching && !model.nodes.isEmpty {
                Text("No charts match \"\(model.appliedQuery.trimmed)\".")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("No charts yet.\nEnter ICAO codes above and press Download Charts.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func treeRow(_ row: TreeRow) -> some View {
        let n = row.node
        let selected = !n.isFile && model.selectedKey == n.key
        return HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(row.depth) * 18, height: 1)
            if n.isFile {
                Color.clear.frame(width: 14, height: 1)
            } else {
                Image(systemName: row.open ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .frame(width: 14)
            }
            Image(systemName: n.isFile ? "doc.text" : "folder.fill")
                .foregroundStyle(n.isFile ? Color.secondary : Color.yellow)
            Text(n.name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if n.isFile {
                model.openFile = OpenFile(url: n.url)
            } else {
                model.select(n.key)
                model.toggleExpanded(n.key)
            }
        }
        .contextMenu {
            if !n.isFile {
                Button("Expand All") { model.expandFolder(n) }
                Button("Delete Folder...", role: .destructive) { deleteTarget = n }
            }
        }
        .listRowBackground(selected ? Color.accentColor.opacity(0.2) : Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
    }
}
