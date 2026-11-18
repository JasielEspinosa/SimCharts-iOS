import SwiftUI

/// Chart sources and usage notes, opened on demand from the menu.
struct NotesView: View {
    @Environment(\.dismiss) private var dismiss

    private let sources: [String] = [
        "US: FAA d-TPP",
        "Philippines: VATPHIL (vatphil.com)",
        "Hong Kong and Macao (SID/STAR): Hong Kong eAIP (ais.gov.hk)",
        "Taiwan: Taiwan eAIP (ais.caa.gov.tw)",
        "Korea: Korea eAIP (aim.koca.go.kr)",
        "Viet Nam: Viet Nam eAIP (aim.vatm.vn)",
        "Japan: unofficial AIP Japan mirror (nagodede.github.io); the AIRAC date is shown in the download log and it may be out of date.",
        "Indonesia: the official AIP needs a free login (aimindonesia.kemenhub.go.id), so it cannot be downloaded here; save its PDFs into the SimCharts folder of the Files app yourself.",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("For flight simulation use only - not for real-world navigation.")
                    Text("Chart sources:").fontWeight(.semibold)
                    ForEach(sources, id: \.self) { Text($0) }
                    Text("Other countries: add your own source in Settings > Custom Resources.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Keep SimCharts open while charts download: iPhone pauses apps in the background. "
                        + "Downloaded charts are in Files > On My iPhone > SimCharts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
