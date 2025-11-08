import SwiftUI

/// An item within a column that is either a rendered node or an intentional gap.
enum FabricColumnItem {
    case gap
    case node
}

extension FabricColumnItem {
    /// Indicates whether this column item represents a rendered node square.
    var isNode: Bool {
        if case .node = self { return true }
        return false
    }
}

/// Collection of column items representing a vertical stack for a glyph column.
struct FabricColumn {
    var items: [FabricColumnItem]
}

/// Describes a connector line joining index positions between two columns.
struct FabricConnector {
    var leftIndex: Int
    var rightIndex: Int
}

struct FabricLogoView: View {
    var spacing: CGFloat = 0.5
    var cornerRadiusRatio: CGFloat = 0.2
    var letterSpacingHoriz: CGFloat = 0.2
    var letterSpacingVert: CGFloat = 0.2
    var aspectRatio: CGFloat = 0.125
    var spacingBetweenNodesOnly: Bool = true
    var showInterLetterConnector: Bool = true
    var showEdgeConnectors: Bool = true

    private var singleColumnFillRatio: CGFloat { 1.0 }

    #if os(macOS)
    private var backgroundColor: Color { Color(nsColor: .windowBackgroundColor) }
    #else
    private var backgroundColor: Color { Color(uiColor: .systemBackground) }
    #endif
    private var nodeColor: Color { .black }

    var body: some View {
        GeometryReader { geometry in
            lettersView(in: geometry.size)
        }
    }

    private struct LetterMetrics {
        var widthUnits: CGFloat
        var hasRightColumn: Bool
    }

    private struct LayoutMetrics {
        var scale: CGFloat
        var letterWidths: [CGFloat]
        var letterSpacing: CGFloat
        var columnSpacing: CGFloat
        var contentHeight: CGFloat
        var contentWidth: CGFloat
    }

    private struct LetterGeometry {
        var leftColumnLeading: CGFloat
        var leftColumnTrailing: CGFloat
        var rightColumnLeading: CGFloat?
        var rightColumnTrailing: CGFloat?
    }

    private func layoutMetrics(for letters: [FabricLetterSpec], available size: CGSize) -> LayoutMetrics {
        let metrics = letters.map(letterMetrics)
        let letterCount = CGFloat(max(letters.count, 1))
        let columnSpacingRatio = letterSpacingHoriz
        let widthUnitsSum = metrics.reduce(CGFloat.zero) { total, metric in
            total + metric.widthUnits + (metric.hasRightColumn ? columnSpacingRatio : 0)
        }

        let averageWidthUnits = widthUnitsSum / letterCount
        let letterSpacingRatio = spacing
        let totalSpacingUnits = letterSpacingRatio * averageWidthUnits * CGFloat(max(letters.count - 1, 0))
        let denominator = widthUnitsSum + totalSpacingUnits
        let scale = denominator > 0 ? size.width / denominator : 0

        let columnSpacingValue = columnSpacingRatio * scale
        let letterSpacingValue = letterSpacingRatio * averageWidthUnits * scale
        let letterWidths = metrics.map { metric in
            scale * metric.widthUnits + (metric.hasRightColumn ? columnSpacingValue : 0)
        }

        let desiredHeight = size.width * aspectRatio
        let contentHeight = min(size.height, max(0, desiredHeight))
        let totalLetterSpacing = letterSpacingValue * CGFloat(max(letters.count - 1, 0))
        let contentWidth = letterWidths.reduce(0, +) + totalLetterSpacing

        return LayoutMetrics(scale: scale,
                             letterWidths: letterWidths,
                             letterSpacing: letterSpacingValue,
                             columnSpacing: columnSpacingValue,
                             contentHeight: contentHeight,
                             contentWidth: contentWidth)
    }

    private func letterMetrics(for letter: FabricLetterSpec) -> LetterMetrics {
        let hasRightColumn = letter.rightColumn != nil
        let widthUnits: CGFloat = hasRightColumn ? 2 : singleColumnFillRatio
        return LetterMetrics(widthUnits: widthUnits, hasRightColumn: hasRightColumn)
    }


    private func lettersView(in size: CGSize) -> some View {
        let letters = FabricLetterSpec.all
        let layout = layoutMetrics(for: letters, available: size)
        let letterHeight = layout.contentHeight
        let edgeMargin = showEdgeConnectors ? max(layout.letterSpacing, layout.scale) : 0
        let totalWidth = layout.contentWidth + edgeMargin * 2
        let geometries = letterGeometries(for: letters,
                                          layout: layout,
                                          edgeMargin: edgeMargin)
        let lineWidth = max(letterHeight / 25.0, 1)
        let interLetterSegments = showInterLetterConnector ? self.interLetterSegments(for: geometries,
                                                                                      letterHeight: letterHeight,
                                                                                      lineWidth: lineWidth) : []
        let edgeSegments = showEdgeConnectors ? self.edgeSegments(for: geometries,
                                                                  totalWidth: totalWidth,
                                                                  letterHeight: letterHeight,
                                                                  lineWidth: lineWidth) : []
        let combinedSegments = interLetterSegments + edgeSegments

        return ZStack(alignment: .topLeading) {
            HStack(spacing: layout.letterSpacing) {
                ForEach(letters.indices, id: \.self) { index in
                    letterView(for: letters[index],
                               scale: layout.scale,
                               letterHeight: letterHeight,
                               columnSpacing: layout.columnSpacing)
                        .frame(width: layout.letterWidths[index],
                               height: letterHeight,
                               alignment: .topLeading)
                }
            }
            .frame(width: layout.contentWidth,
                   height: letterHeight,
                   alignment: .topLeading)
            .offset(x: edgeMargin)

            if !combinedSegments.isEmpty {
                connectorOutlineView(segments: combinedSegments,
                                     lineWidth: lineWidth,
                                     letterHeight: letterHeight,
                                     overlayWidth: totalWidth)
                    .allowsHitTesting(false)
                connectorStrokeView(segments: combinedSegments,
                                    lineWidth: lineWidth,
                                    letterHeight: letterHeight,
                                    overlayWidth: totalWidth)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: totalWidth,
               height: letterHeight,
               alignment: .topLeading)
        .frame(width: size.width,
               height: letterHeight,
               alignment: .center)
    }

    private func letterGeometries(for letters: [FabricLetterSpec],
                                  layout: LayoutMetrics,
                                  edgeMargin: CGFloat) -> [LetterGeometry] {
        guard !letters.isEmpty else { return [] }
        var currentX = edgeMargin
        return letters.enumerated().map { index, spec in
            let hasRightColumn = spec.rightColumn != nil
            let fillRatio = hasRightColumn ? 1.0 : singleColumnFillRatio
            let leftColumnWidth = layout.scale * fillRatio
            let rightColumnWidth = hasRightColumn ? layout.scale : 0
            let columnSpacingValue = hasRightColumn ? layout.columnSpacing : 0
            let letterWidth = layout.letterWidths[index]
            let leftLeading = currentX
            let leftTrailing = currentX + leftColumnWidth
            let rightLeading = hasRightColumn ? currentX + leftColumnWidth + columnSpacingValue : nil
            let rightTrailing = rightLeading.map { $0 + rightColumnWidth }
            let geometry = LetterGeometry(leftColumnLeading: leftLeading,
                                          leftColumnTrailing: leftTrailing,
                                          rightColumnLeading: rightLeading,
                                          rightColumnTrailing: rightTrailing)
            currentX += letterWidth
            if index < letters.count - 1 {
                currentX += layout.letterSpacing
            }
            return geometry
        }
    }

    private func interLetterSegments(for geometries: [LetterGeometry],
                                     letterHeight: CGFloat,
                                     lineWidth: CGFloat) -> [ConnectorSegment] {
        guard geometries.count > 1 else { return [] }
        let y = attachmentY(for: 0, in: letterHeight)
        let inset = lineWidth * 2
        return geometries.indices.dropLast().map { index in
            let current = geometries[index]
            let next = geometries[index + 1]
            let startLeading = current.rightColumnLeading ?? current.leftColumnLeading
            let startTrailing = current.rightColumnTrailing ?? current.leftColumnTrailing
            let startX = max(startLeading, startTrailing - inset)
            let endLeading = next.leftColumnLeading
            let endTrailing = next.leftColumnTrailing
            let endX = min(endTrailing, endLeading + inset)
            return ConnectorSegment(start: CGPoint(x: startX, y: y),
                                    end: CGPoint(x: endX, y: y))
        }
    }

    private func edgeSegments(for geometries: [LetterGeometry],
                              totalWidth: CGFloat,
                              letterHeight: CGFloat,
                              lineWidth: CGFloat) -> [ConnectorSegment] {
        guard let first = geometries.first,
              let last = geometries.last else { return [] }
        let y = attachmentY(for: 0, in: letterHeight)
        let inset = lineWidth * 2
        let incomingEndLeading = first.leftColumnLeading
        let incomingEndTrailing = first.leftColumnTrailing
        let incomingEndX = min(incomingEndTrailing, incomingEndLeading + inset)
        let incoming = ConnectorSegment(start: CGPoint(x: 0, y: y),
                                         end: CGPoint(x: incomingEndX, y: y))
        let outgoingStartLeading = last.rightColumnLeading ?? last.leftColumnLeading
        let outgoingStartTrailing = last.rightColumnTrailing ?? last.leftColumnTrailing
        let outgoingStartX = max(outgoingStartLeading, outgoingStartTrailing - inset)
        let outgoing = ConnectorSegment(start: CGPoint(x: outgoingStartX, y: y),
                                         end: CGPoint(x: totalWidth, y: y))
        return [incoming, outgoing]
    }

    private func letterView(for spec: FabricLetterSpec,
                            scale: CGFloat,
                            letterHeight: CGFloat,
                            columnSpacing: CGFloat) -> some View {
        let hasRightColumn = spec.rightColumn != nil
        let fillRatio = hasRightColumn ? 1.0 : singleColumnFillRatio
        let leftColumnWidth = scale * fillRatio
        let rightColumnWidth = hasRightColumn ? scale : 0

        let columnSpacingValue = hasRightColumn ? columnSpacing : 0

        let columns = HStack(alignment: .top,
                             spacing: columnSpacingValue) {
            columnView(spec.leftColumn,
                       unitScale: scale,
                       letterHeight: letterHeight,
                       fillRatio: fillRatio,
                       spacingBetweenNodesOnly: spacingBetweenNodesOnly)
            if let rightColumn = spec.rightColumn {
                columnView(rightColumn,
                           unitScale: scale,
                           letterHeight: letterHeight,
                           fillRatio: 1.0,
                           spacingBetweenNodesOnly: spacingBetweenNodesOnly)
            }
        }
        .frame(height: letterHeight, alignment: .top)

        return Group {
            if hasRightColumn,
               let rightColumn = spec.rightColumn,
               rightColumn.items.count > 0,
               !spec.connectors.isEmpty {
                let overlayWidth = leftColumnWidth + columnSpacingValue + rightColumnWidth
                let lineWidth = max(letterHeight / 25.0, 1)
                let inset = lineWidth * 2
                let startX = max(0, leftColumnWidth - inset)
                let endX = min(overlayWidth, leftColumnWidth + columnSpacingValue + inset)
                let segments = spec.connectors.map { connector in
                    ConnectorSegment(start: CGPoint(x: startX, y: attachmentY(for: connector.leftIndex, in: letterHeight)),
                                     end: CGPoint(x: endX, y: attachmentY(for: connector.rightIndex, in: letterHeight)))
                }

                columns
                    .overlay(alignment: .topLeading) {
                        connectorOutlineView(segments: segments,
                                             lineWidth: lineWidth,
                                             letterHeight: letterHeight,
                                             overlayWidth: overlayWidth)
                    }
                    .overlay(alignment: .topLeading) {
                        connectorStrokeView(segments: segments,
                                             lineWidth: lineWidth,
                                             letterHeight: letterHeight,
                                             overlayWidth: overlayWidth)
                    }
            } else {
                columns
            }
        }
    }

    private func columnView(_ column: FabricColumn,
                            unitScale: CGFloat,
                            letterHeight: CGFloat,
                            fillRatio: CGFloat,
                            spacingBetweenNodesOnly: Bool) -> some View {
        let items = column.items
        let columnWidth = unitScale * fillRatio

        let itemCount = items.count
        let spacingCount: Int
        if spacingBetweenNodesOnly {
            spacingCount = max(0, items.indices.dropLast().reduce(0) { partial, index in
                let nextIndex = index + 1
                guard nextIndex < items.count else { return partial }
                return partial + (items[index].isNode && items[nextIndex].isNode ? 1 : 0)
            })
        } else {
            spacingCount = max(0, itemCount - 1)
        }
        let maxSpacingPerGap = letterHeight / 5.0
        let spacingHeight = letterSpacingVert * maxSpacingPerGap
        let totalSpacing = CGFloat(spacingCount) * spacingHeight
        let availableForItems = max(letterHeight - totalSpacing, 0)
        let itemHeight = itemCount > 0 ? availableForItems / CGFloat(itemCount) : 0
        let actualCornerRadius = min(columnWidth, itemHeight) * cornerRadiusRatio

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                switch item {
                case .gap:
                    Color.clear
                        .frame(width: columnWidth,
                               height: itemHeight,
                               alignment: .leading)
                case .node:
                    RoundedRectangle(cornerRadius: actualCornerRadius)
                        .fill(nodeColor)
                        .frame(width: columnWidth,
                               height: itemHeight)
                }
                
                if index < items.count - 1 {
                    let nextItem = items[index + 1]
                    let shouldInsertSpacing = spacingBetweenNodesOnly ? (item.isNode && nextItem.isNode) : true
                    if shouldInsertSpacing {
                        Color.clear
                            .frame(width: columnWidth,
                                   height: spacingHeight)
                    }
                }
            }
        }
        .frame(width: columnWidth, height: letterHeight, alignment: .topLeading)
    }

    private func attachmentY(for index: Int, in height: CGFloat) -> CGFloat {
        let clamped = max(0, min(4, index))
        return height * (CGFloat(clamped) + 0.5) / 5.0
    }

    private struct ConnectorSegment: Identifiable {
        let id = UUID()
        let start: CGPoint
        let end: CGPoint
    }

    private struct ConnectorLine: Shape {
        var segment: ConnectorSegment

        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: segment.start)
            path.addLine(to: segment.end)
            return path
        }
    }

    private func connectorOutlineView(segments: [ConnectorSegment],
                                      lineWidth: CGFloat,
                                      letterHeight: CGFloat,
                                      overlayWidth: CGFloat) -> some View {
        ZStack {
            if !segments.isEmpty {
                ForEach(segments) { segment in
                    ConnectorLine(segment: segment)
                        .stroke(backgroundColor,
                                style: StrokeStyle(lineWidth: lineWidth * 3, lineCap: .round))
                }
            }
        }
        .frame(width: overlayWidth, height: letterHeight, alignment: .topLeading)
    }

    private func connectorStrokeView(segments: [ConnectorSegment],
                                     lineWidth: CGFloat,
                                     letterHeight: CGFloat,
                                     overlayWidth: CGFloat) -> some View {
        ZStack {
            if !segments.isEmpty {
                ForEach(segments) { segment in
                    ConnectorLine(segment: segment)
                        .stroke(nodeColor,
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }
        }
        .frame(width: overlayWidth, height: letterHeight, alignment: .topLeading)
    }
}