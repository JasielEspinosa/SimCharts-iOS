import SwiftUI

/// The countries SimCharts can download charts for, with the ICAO codes and source of each.
struct SupportedCountriesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SupportedCountries.supported) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(c.country).font(.headline)
                                Spacer()
                                Text(c.kind.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                            }
                            Text("ICAO: \(c.codes)").font(.subheadline)
                            Text(c.source).font(.subheadline)
                            Text(c.coverage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                } header: {
                    Text("\(SupportedCountries.supported.count) sources built in")
                } footer: {
                    Text("Type an ICAO code of any of these and press Download Charts.")
                }

                Section("Not available") {
                    ForEach(SupportedCountries.notAvailable) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.country).font(.headline)
                            Text("ICAO: \(c.codes)").font(.subheadline)
                            Text(c.reason)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }

                Section {
                    Text(SupportedCountries.otherCountries)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Supported countries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
