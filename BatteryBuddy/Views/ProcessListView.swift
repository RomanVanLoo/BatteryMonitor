import SwiftUI

struct ProcessListView: View {
    let processes: [EnergyProcess]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Energy Impact")
                .font(.headline)
                .padding(.bottom, 8)

            if processes.isEmpty {
                Text("Collecting data...")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(processes) { process in
                    ProcessRow(process: process)
                    if process.id != processes.last?.id {
                        Divider()
                            .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

private struct ProcessRow: View {
    let process: EnergyProcess

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: resizedIcon)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(process.displayName)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(1)

                    if process.processCount > 1 {
                        Text("(\(process.processCount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(process.formattedPower)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ImpactBadge(label: process.impactLabel, isHeavy: process.isHeavy)
        }
        .padding(.vertical, 4)
    }

    private var resizedIcon: NSImage {
        let img = process.icon
        img.size = NSSize(width: 20, height: 20)
        return img
    }
}

private struct ImpactBadge: View {
    let label: String
    let isHeavy: Bool

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        if isHeavy { return .red }
        if label == "Moderate" { return .orange }
        return .green
    }
}
