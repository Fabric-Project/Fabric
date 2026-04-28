import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

// MARK: - Helpers

private func makeContext() -> Context? {
    guard let device = MTLCreateSystemDefaultDevice() else { return nil }
    return Context(
        device: device,
        sampleCount: 1,
        colorPixelFormat: .bgra8Unorm,
        depthPixelFormat: .invalid,
        stencilPixelFormat: .invalid
    )
}

private func makeNode(context: Context) -> TestCardProviderNode {
    TestCardProviderNode(context: context)
}

/// Connect output texture of `from` → inputWidth of `to`.
private func connect(_ from: TestCardProviderNode, to: TestCardProviderNode) {
    from.outputTexturePort.connect(to: to.inputWidth)
}

/// Look up a node's computed position from layout results.
private func position(of node: Node, in layout: [(Node, CGSize)]) -> CGSize? {
    layout.first(where: { $0.0.id == node.id })?.1
}

private func xPosition(of node: Node, in layout: [(Node, CGSize)]) -> CGFloat? {
    position(of: node, in: layout)?.width
}

/// Top edge Y of a node given its centre-Y position.
private func topEdge(of node: Node, in layout: [(Node, CGSize)]) -> CGFloat? {
    guard let pos = position(of: node, in: layout) else { return nil }
    return pos.height - node.nodeSize.height / 2
}

/// Group layout results by column (x position).
private func columns(from layout: [(Node, CGSize)]) -> [[Node]] {
    var byX: [CGFloat: [Node]] = [:]
    for (node, pos) in layout {
        byX[pos.width, default: []].append(node)
    }
    return byX.keys.sorted().map { byX[$0]! }
}

// MARK: - Tests

@Suite("GraphAutoLayout")
struct GraphAutoLayoutTests {

    @Test("Empty graph produces no layout")
    func emptyGraph() {
        let layout = GraphAutoLayout.compute(nodes: [])
        #expect(layout.isEmpty)
    }

    @Test("Single node is placed at column 0")
    func singleNode() {
        guard let ctx = makeContext() else { return }
        let node = makeNode(context: ctx)
        let layout = GraphAutoLayout.compute(nodes: [node])
        #expect(layout.count == 1)
        #expect(xPosition(of: node, in: layout) == 0)
    }

    @Test("Two connected nodes: provider left of consumer")
    func twoConnected() {
        guard let ctx = makeContext() else { return }
        let provider = makeNode(context: ctx)
        let consumer = makeNode(context: ctx)
        connect(provider, to: consumer)

        let layout = GraphAutoLayout.compute(nodes: [provider, consumer])
        #expect(xPosition(of: consumer, in: layout)! > xPosition(of: provider, in: layout)!)
    }

    @Test("Three-node chain: columns increase leftward")
    func threeNodeChain() {
        guard let ctx = makeContext() else { return }
        let a = makeNode(context: ctx)
        let b = makeNode(context: ctx)
        let c = makeNode(context: ctx)
        connect(a, to: b)
        connect(b, to: c)

        let layout = GraphAutoLayout.compute(nodes: [a, b, c])
        let xA = xPosition(of: a, in: layout)!
        let xB = xPosition(of: b, in: layout)!
        let xC = xPosition(of: c, in: layout)!
        #expect(xC > xB)
        #expect(xB > xA)
    }

    @Test("Disconnected nodes all placed at column 0")
    func disconnectedNodes() {
        guard let ctx = makeContext() else { return }
        let a = makeNode(context: ctx)
        let b = makeNode(context: ctx)
        let c = makeNode(context: ctx)

        let layout = GraphAutoLayout.compute(nodes: [a, b, c])
        #expect(layout.allSatisfy { $0.1.width == 0 })
    }

    @Test("Column spacing matches constant")
    func columnSpacing() {
        guard let ctx = makeContext() else { return }
        let a = makeNode(context: ctx)
        let b = makeNode(context: ctx)
        connect(a, to: b)

        let layout = GraphAutoLayout.compute(nodes: [a, b])
        let dx = xPosition(of: b, in: layout)! - xPosition(of: a, in: layout)!
        #expect(dx == GraphAutoLayout.columnSpacing + GraphAutoLayout.nodeWidth)
    }

    @Test("Fan-in: two providers at same column, left of consumer")
    func fanIn() {
        guard let ctx = makeContext() else { return }
        let p1 = makeNode(context: ctx)
        let p2 = makeNode(context: ctx)
        let consumer = makeNode(context: ctx)
        connect(p1, to: consumer)
        p2.outputTexturePort.connect(to: consumer.inputHeight)

        let layout = GraphAutoLayout.compute(nodes: [p1, p2, consumer])
        let xP1 = xPosition(of: p1, in: layout)!
        let xP2 = xPosition(of: p2, in: layout)!
        let xC = xPosition(of: consumer, in: layout)!
        #expect(xP1 == xP2, "Both providers should be in the same column")
        #expect(xP1 < xC, "Providers should be left of consumer")
    }

    // MARK: - Column top-alignment

    @Test("Column anchors to topmost downstream node, not first sorted node")
    func columnAnchorsToTopmostDownstream() {
        guard let ctx = makeContext() else { return }

        let d = makeNode(context: ctx) // consumer (col 0)
        let b = makeNode(context: ctx) // col 1, top
        let f = makeNode(context: ctx) // col 1, bottom
        let a = makeNode(context: ctx) // col 2, feeds B
        let c = makeNode(context: ctx) // col 2, feeds B (2nd port)
        let e = makeNode(context: ctx) // col 2, feeds F

        b.outputTexturePort.connect(to: d.inputWidth)
        f.outputTexturePort.connect(to: d.inputHeight)
        a.outputTexturePort.connect(to: b.inputWidth)
        c.outputTexturePort.connect(to: b.inputHeight)
        e.outputTexturePort.connect(to: f.inputWidth)

        let layout = GraphAutoLayout.compute(nodes: [d, b, f, a, c, e])

        let topCol1 = [b, f].compactMap { topEdge(of: $0, in: layout) }.min()!
        let topCol2 = [a, c, e].compactMap { topEdge(of: $0, in: layout) }.min()!

        #expect(topCol2 <= topCol1,
                "Column 2 top (\(topCol2)) should be at or above column 1 top (\(topCol1))")
    }

    // MARK: - Per-node downstream alignment

    /// Each node should top-align with its topmost downstream connected node,
    /// unless pushed down by nodes above it in the column.
    ///
    ///   Col 1       Col 0
    ///   A ────────→ C.port0     (A top-aligns with C)
    ///   B ────────→ C.port1     (B should top-align with its downstream — but C
    ///                            only has one row, so B stacks below A)
    ///
    /// More interesting case with gap:
    ///   Col 2       Col 1       Col 0
    ///   X ────────→ A ────────→ D.port0     (X top-aligns with A)
    ///   Y ────────→ B ────────→ D.port1     (Y should top-align with B,
    ///                                        not just stack below X)
    @Test("Nodes top-align with their downstream target, not just stacked")
    func perNodeDownstreamAlignment() {
        guard let ctx = makeContext() else { return }

        let d = makeNode(context: ctx) // col 0
        let a = makeNode(context: ctx) // col 1, row 0
        let b = makeNode(context: ctx) // col 1, row 1
        let x = makeNode(context: ctx) // col 2, feeds A
        let y = makeNode(context: ctx) // col 2, feeds B

        a.outputTexturePort.connect(to: d.inputWidth)
        b.outputTexturePort.connect(to: d.inputHeight)
        x.outputTexturePort.connect(to: a.inputWidth)
        y.outputTexturePort.connect(to: b.inputWidth)

        let layout = GraphAutoLayout.compute(nodes: [d, a, b, x, y])

        // Y should top-align with B, not just stack below X
        let topB = topEdge(of: b, in: layout)!
        let topY = topEdge(of: y, in: layout)!
        #expect(topY == topB,
                "Y (top \(topY)) should top-align with B (top \(topB))")
    }

    /// Non-trivial case: extra nodes in column 1 push B down. Y should
    /// skip the gap to top-align with B, not just stack below X.
    ///
    ///   Col 2       Col 1       Col 0
    ///   X ────────→ A ────────→ D.port0
    ///               S1 ─────→ D.port1   (spacer, pushes B down)
    ///               S2 ─────→ D.port2   (spacer)
    ///   Y ────────→ B          (B has no downstream — disconnected leaf in col 1)
    ///
    /// Actually, B needs to be in column 1 with a downstream to D. But
    /// TestCardProviderNode has only 3 ports. So: use a different topology.
    ///
    ///   Col 1       Col 0
    ///   A ────────→ C.port0
    ///   B ────────→ C.port1
    ///   D ────────→ C.port2
    ///
    ///   Col 2       Col 1
    ///   X ────────→ A           (should top-align with A)
    ///   Y ────────→ D           (should top-align with D, skipping past B)
    ///
    @Test("Nodes skip gap to align with downstream target")
    func nodesSkipGapToAlignWithDownstream() {
        guard let ctx = makeContext() else { return }

        let c = makeNode(context: ctx) // col 0
        let a = makeNode(context: ctx) // col 1, row 0
        let b = makeNode(context: ctx) // col 1, row 1 (no upstream — gap creator)
        let d = makeNode(context: ctx) // col 1, row 2
        let x = makeNode(context: ctx) // col 2, feeds A
        let y = makeNode(context: ctx) // col 2, feeds D

        a.outputTexturePort.connect(to: c.inputWidth)
        b.outputTexturePort.connect(to: c.inputHeight)
        d.outputTexturePort.connect(to: c.inputTextString)
        x.outputTexturePort.connect(to: a.inputWidth)
        y.outputTexturePort.connect(to: d.inputWidth)

        let layout = GraphAutoLayout.compute(nodes: [c, a, b, d, x, y])

        let topA = topEdge(of: a, in: layout)!
        let topD = topEdge(of: d, in: layout)!
        let topX = topEdge(of: x, in: layout)!
        let topY = topEdge(of: y, in: layout)!

        #expect(topX == topA, "X should top-align with A")
        #expect(topY == topD,
                "Y (top \(topY)) should top-align with D (top \(topD)), not just stack below X")
    }

    /// Same principle applied to the Offstage Left Box: secs*speed should
    /// top-align with Euler Orientation (its downstream target).
    @Test("Offstage Left Box: secs*speed top-aligns with Euler Orientation")
    func offstageLeftBoxSecsTimesSpeedAlignment() {
        guard let ctx = makeContext() else { return }

        let mesh = makeNode(context: ctx)
        let vector3 = makeNode(context: ctx)
        let eulerOrientation = makeNode(context: ctx)
        let physicalMaterial = makeNode(context: ctx)
        vector3.outputTexturePort.connect(to: mesh.inputWidth)
        eulerOrientation.outputTexturePort.connect(to: mesh.inputHeight)
        physicalMaterial.outputTexturePort.connect(to: mesh.inputTextString)

        let twoMinusActive = makeNode(context: ctx)
        let secsTimesSpeed = makeNode(context: ctx)
        let colorTween = makeNode(context: ctx)
        twoMinusActive.outputTexturePort.connect(to: vector3.inputWidth)
        secsTimesSpeed.outputTexturePort.connect(to: eulerOrientation.inputWidth)
        colorTween.outputTexturePort.connect(to: physicalMaterial.inputWidth)

        let allNodes: [Node] = [mesh, vector3, eulerOrientation, physicalMaterial,
                                twoMinusActive, secsTimesSpeed, colorTween]

        let layout = GraphAutoLayout.compute(nodes: allNodes)

        let topEuler = topEdge(of: eulerOrientation, in: layout)!
        let topSecs = topEdge(of: secsTimesSpeed, in: layout)!
        #expect(topSecs == topEuler,
                "secs*speed (top \(topSecs)) should top-align with Euler Orientation (top \(topEuler))")
    }

    // MARK: - Fan-out alignment

    /// When a node's single Outlet connects to multiple downstream
    /// nodes, that source should top-align with the *topmost*
    /// downstream — the one at the smallest centre-Y in the layout —
    /// regardless of the order the connections were made.
    ///
    /// The bug: `downstreamTopEdgeY` returns the first entry in
    /// `outputNodes`, which is connection-order. The matching sort
    /// (`downstreamSortKey`) already picks the lowest-row downstream;
    /// positioning has to use the same rule for the result to be
    /// stable.
    @Test("Fan-out source top-aligns with topmost downstream, not first-connected")
    func fanOutTopAlignsWithTopmostDownstream() {
        guard let ctx = makeContext() else { return }

        let sink = makeNode(context: ctx)         // col 0
        let topConsumer = makeNode(context: ctx)  // col 1, row 0
        let midConsumer = makeNode(context: ctx)  // col 1, row 1
        let botConsumer = makeNode(context: ctx)  // col 1, row 2
        let source = makeNode(context: ctx)       // col 2 — fan-out

        topConsumer.outputTexturePort.connect(to: sink.inputWidth)
        midConsumer.outputTexturePort.connect(to: sink.inputHeight)
        botConsumer.outputTexturePort.connect(to: sink.inputTextString)

        // Connect source to BOTTOM, MIDDLE, TOP in that order.
        // `outputNodes` ends up [bot, mid, top] — so a positioning
        // path that picks the first connection ends up aligning with
        // `bot` rather than the topmost layout neighbour `top`.
        source.outputTexturePort.connect(to: botConsumer.inputWidth)
        source.outputTexturePort.connect(to: midConsumer.inputWidth)
        source.outputTexturePort.connect(to: topConsumer.inputWidth)

        let layout = GraphAutoLayout.compute(
            nodes: [sink, topConsumer, midConsumer, botConsumer, source]
        )

        let topOfTopConsumer = topEdge(of: topConsumer, in: layout)!
        let topOfSource = topEdge(of: source, in: layout)!

        #expect(topOfSource == topOfTopConsumer,
                "Source (top \(topOfSource)) should top-align with topmost downstream `topConsumer` (top \(topOfTopConsumer)), regardless of connection order")
    }

    // MARK: - Cross-column vertical ordering

    /// Nodes in column N should be ordered by the row of their downstream
    /// node in column N-1, not just by port index on that downstream node.
    ///
    ///   Col 2       Col 1       Col 0
    ///   X ────────→ A ────────→ C      (A is row 0 in col 1)
    ///   Y ────────→ B ────────→ C      (B is row 1 in col 1)
    ///
    /// X feeds A (row 0), Y feeds B (row 1) → X should be above Y.
    @Test("Column sorted by downstream node row, not just port index")
    func crossColumnOrdering() {
        guard let ctx = makeContext() else { return }

        let c = makeNode(context: ctx) // consumer (col 0)
        let a = makeNode(context: ctx) // col 1, row 0
        let b = makeNode(context: ctx) // col 1, row 1
        let x = makeNode(context: ctx) // col 2, feeds A
        let y = makeNode(context: ctx) // col 2, feeds B

        a.outputTexturePort.connect(to: c.inputWidth)  // A is row 0 (port 0 on C)
        b.outputTexturePort.connect(to: c.inputHeight)  // B is row 1 (port 1 on C)
        x.outputTexturePort.connect(to: a.inputWidth)
        y.outputTexturePort.connect(to: b.inputWidth)

        let layout = GraphAutoLayout.compute(nodes: [c, a, b, x, y])

        let yX = position(of: x, in: layout)!.height
        let yY = position(of: y, in: layout)!.height
        #expect(yX < yY, "X (feeds row 0) should be above Y (feeds row 1)")
    }

    // MARK: - Real-world: Offstage Left Box topology

    /// Reproduces the "Offstage Left Box" StateSubgraphNode graph.
    ///
    ///   Col 3        Col 2              Col 1                    Col 0
    ///   StateInfo → 2-(act*2) ───→ Vector3 ──────────────────→ Mesh
    ///   PatchTime → secs*speed ──→ EulerOrientation ─────────→ Mesh
    ///   Number ──↗                 PhysicalMaterial ──────────→ Mesh
    ///   Vector4 ──→ ColorTween ──↗
    ///
    /// (BoxGeometry omitted — TestCardProviderNode has only 3 input ports.)
    @Test("Offstage Left Box: column ordering and top-alignment")
    func offstageLeftBox() {
        guard let ctx = makeContext() else { return }

        // Column 0: consumer
        let mesh = makeNode(context: ctx)

        // Column 1: all connect to mesh
        let vector3 = makeNode(context: ctx)
        let eulerOrientation = makeNode(context: ctx)
        let physicalMaterial = makeNode(context: ctx)
        vector3.outputTexturePort.connect(to: mesh.inputWidth)              // Position (port 0)
        eulerOrientation.outputTexturePort.connect(to: mesh.inputHeight)    // Orientation (port 1)
        physicalMaterial.outputTexturePort.connect(to: mesh.inputTextString) // Material (port 2)

        // Column 2
        let twoMinusActive = makeNode(context: ctx) // feeds vector3
        let secsTimesSpeed = makeNode(context: ctx)  // feeds eulerOrientation
        let colorTween = makeNode(context: ctx)      // feeds physicalMaterial
        twoMinusActive.outputTexturePort.connect(to: vector3.inputWidth)          // → X
        secsTimesSpeed.outputTexturePort.connect(to: eulerOrientation.inputWidth) // → Pitch
        colorTween.outputTexturePort.connect(to: physicalMaterial.inputWidth)     // → Base Color

        // Column 3
        let stateInfo = makeNode(context: ctx)  // feeds twoMinusActive
        let patchTime = makeNode(context: ctx)  // feeds secsTimesSpeed
        let number = makeNode(context: ctx)     // feeds secsTimesSpeed (2nd port)
        let vector4 = makeNode(context: ctx)    // feeds colorTween
        stateInfo.outputTexturePort.connect(to: twoMinusActive.inputWidth)    // → active
        patchTime.outputTexturePort.connect(to: secsTimesSpeed.inputWidth)    // → secs
        number.outputTexturePort.connect(to: secsTimesSpeed.inputHeight)      // → speed
        vector4.outputTexturePort.connect(to: colorTween.inputWidth)          // → Target

        let allNodes: [Node] = [
            mesh, vector3, eulerOrientation, physicalMaterial,
            twoMinusActive, secsTimesSpeed, colorTween,
            stateInfo, patchTime, number, vector4,
        ]

        let layout = GraphAutoLayout.compute(nodes: allNodes)
        let cols = columns(from: layout)
        #expect(cols.count == 4, "Expected 4 columns, got \(cols.count)")

        // Top-alignment: no column should sag below the previous one
        for i in 0..<(cols.count - 1) {
            let leftTop = cols[i].compactMap { topEdge(of: $0, in: layout) }.min()!
            let rightTop = cols[i + 1].compactMap { topEdge(of: $0, in: layout) }.min()!
            #expect(leftTop <= rightTop,
                    "Column \(i) top (\(leftTop)) should be at or above column \(i+1) top (\(rightTop))")
        }

        // Column 1 order: vector3 (port 0), eulerOrientation (port 1), physicalMaterial (port 2)
        let col1Y = [vector3, eulerOrientation, physicalMaterial].map { position(of: $0, in: layout)!.height }
        #expect(col1Y[0] < col1Y[1] && col1Y[1] < col1Y[2], "Col 1 should be sorted by Mesh port index")

        // Column 2 order: twoMinusActive (feeds row 0), secsTimesSpeed (feeds row 1), colorTween (feeds row 2)
        let col2Y = [twoMinusActive, secsTimesSpeed, colorTween].map { position(of: $0, in: layout)!.height }
        #expect(col2Y[0] < col2Y[1] && col2Y[1] < col2Y[2], "Col 2 should be sorted by downstream row")

        // Column 3 order: stateInfo (feeds row 0), patchTime (feeds row 1), number (feeds row 1, port 1), vector4 (feeds row 2)
        let col3Y = [stateInfo, patchTime, number, vector4].map { position(of: $0, in: layout)!.height }
        #expect(col3Y[0] < col3Y[1], "stateInfo should be above patchTime")
        #expect(col3Y[1] < col3Y[2], "patchTime should be above number")
        #expect(col3Y[2] < col3Y[3], "number should be above vector4")
    }
}
