//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Charts
import SwiftUI

struct ChartPoint: Identifiable {
    let time: Int
    let usage: Double

    var id: Int { time }
}

extension ChartPoint {
    static func series(from history: [Double], limit: Int) -> [ChartPoint] {
        guard limit > 0, history.count > limit else {
            return history.enumerated().map { ChartPoint(time: $0.offset, usage: $0.element) }
        }

        let bucket = Int((Double(history.count) / Double(limit)).rounded(.up))
        return stride(from: 0, to: history.count, by: bucket).enumerated().map { index, start in
            let end = min(start + bucket, history.count)
            return ChartPoint(time: index, usage: history[start ..< end].max() ?? 0)
        }
    }
}

struct ProcessRow: Identifiable {
    let pid: Int
    let icon: NSImage
    let name: String
    let usage: String

    var id: Int { pid }
}

@Observable class ChartDataModel {
    var chartPoints: [ChartPoint] = []
    var tablePoints: [ProcessRow] = []
    var title: String = ""
}

struct ChartContentView: View {
    var chartItems: ChartDataModel

    var body: some View {
        VStack(alignment: .leading) {
            Text(chartItems.title)
                .font(.headline)
                .fontWeight(.heavy)
            Chart(chartItems.chartPoints) { item in
                AreaMark(
                    x: .value("Name", item.time),
                    y: .value("Usage", item.usage)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            .blue.opacity(1),
                            .blue.opacity(0.4)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .frame(height: 100)
            .chartYScale(domain: 0...100)
            .chartXScale(domain: 0...max(1, chartItems.chartPoints.count - 1))
            .chartXAxis { AxisMarks() { _ in
                AxisGridLine()
                AxisTick()
            }}
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 0) {
                GridRow {
                    Text(localizedString("PID"))
                        .bold()
                        .frame(width: 38, alignment: .leading)
                    Text(localizedString("Name"))
                        .bold()
                        .frame(minWidth: 140, alignment: .leading)
                    Spacer()
                    Text(localizedString("Usage"))
                        .bold()
                        .frame(width: 120, alignment: .trailing)
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 5, verticalSpacing: 1) {
                    ForEach(chartItems.tablePoints) { item in
                        Divider()
                        GridRow {
                            Text(String(item.pid))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .leading)

                            HStack(spacing: 6) {
                                Image(nsImage: item.icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)

                                Text(item.name)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(minWidth: 150, alignment: .leading)

                            Spacer()

                            Text(item.usage)
                                .frame(width: 100, alignment: .trailing)
                        }
                        .font(.system(size: 11))
                        .padding(.vertical, 2)
                    }
                    Divider()
                }
            }
            .frame(height: 230)
        }
        .padding()
    }
}
