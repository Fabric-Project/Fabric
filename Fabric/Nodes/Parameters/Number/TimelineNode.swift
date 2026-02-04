//
//  TimelineNode.swift
//  Fabric
//
//  Created by Claude Code on 1/27/26.
//

import Foundation
import SwiftUI
import Metal

// MARK: - Data Model

/// A single keyframe on a timeline track
public struct TimelineKeyframe: Codable, Identifiable, Equatable
{
    public let id: UUID
    public var time: Float      // 0 to duration
    public var value: Float     // 0 to 1 (strictly clamped)

    // Handle offset in time/value units (right handle; left handle is mirrored)
    public var handleTime: Float   // Time offset of right handle (always positive)
    public var handleValue: Float  // Value offset of right handle (can be positive or negative)

    public init(time: Float, value: Float, handleTime: Float = 0.1, handleValue: Float = 0)
    {
        self.id = UUID()
        self.time = time
        self.value = max(0, min(1, value)) // Clamp to 0-1
        self.handleTime = max(0.01, handleTime) // Minimum handle length
        self.handleValue = handleValue
    }
}

/// A timeline track with keyframes
public struct TimelineTrack: Codable, Identifiable, Equatable
{
    public let id: UUID
    public var name: String
    public var keyframes: [TimelineKeyframe]

    public init(name: String, duration: Float)
    {
        self.id = UUID()
        self.name = name
        // Default: linear ramp from 0 to 1
        self.keyframes = [
            TimelineKeyframe(time: 0, value: 0),
            TimelineKeyframe(time: duration, value: 1)
        ]
    }

    /// Sort keyframes by time
    public mutating func sortKeyframes()
    {
        keyframes.sort { $0.time < $1.time }
    }

    /// Evaluate track value at given time using cubic bezier interpolation
    public func evaluate(at time: Float, duration: Float) -> Float
    {
        guard !keyframes.isEmpty else { return 0 }

        // Clamp time to valid range
        let clampedTime = max(0, min(duration, time))

        // Find surrounding keyframes
        let sortedKeyframes = keyframes.sorted { $0.time < $1.time }

        // Before first keyframe
        if clampedTime <= sortedKeyframes.first!.time
        {
            return sortedKeyframes.first!.value
        }

        // After last keyframe
        if clampedTime >= sortedKeyframes.last!.time
        {
            return sortedKeyframes.last!.value
        }

        // Find the two keyframes we're between
        var k0: TimelineKeyframe = sortedKeyframes[0]
        var k1: TimelineKeyframe = sortedKeyframes[1]

        for i in 0..<(sortedKeyframes.count - 1)
        {
            if clampedTime >= sortedKeyframes[i].time && clampedTime <= sortedKeyframes[i + 1].time
            {
                k0 = sortedKeyframes[i]
                k1 = sortedKeyframes[i + 1]
                break
            }
        }

        // Interpolate using cubic bezier
        return cubicBezierInterpolate(k0: k0, k1: k1, time: clampedTime)
    }

    /// Cubic bezier interpolation between two keyframes
    private func cubicBezierInterpolate(k0: TimelineKeyframe, k1: TimelineKeyframe, time: Float) -> Float
    {
        let dt = k1.time - k0.time
        guard dt > 0 else { return k0.value }

        // Normalized time within segment (0 to 1)
        let t = (time - k0.time) / dt

        // P0 = start point value
        let p0 = k0.value

        // P1 = first control point (k0's right handle value offset)
        let p1 = k0.value + k0.handleValue

        // P2 = second control point (k1's left handle, which is mirrored)
        let p2 = k1.value - k1.handleValue

        // P3 = end point value
        let p3 = k1.value

        // Cubic bezier formula: B(t) = (1-t)³P0 + 3(1-t)²tP1 + 3(1-t)t²P2 + t³P3
        let oneMinusT = 1.0 - t
        let oneMinusT2 = oneMinusT * oneMinusT
        let oneMinusT3 = oneMinusT2 * oneMinusT
        let t2 = t * t
        let t3 = t2 * t

        let value = oneMinusT3 * p0 +
                    3.0 * oneMinusT2 * t * p1 +
                    3.0 * oneMinusT * t2 * p2 +
                    t3 * p3

        return value
    }

    // MARK: - Keyframe Management

    public mutating func addKeyframe(at time: Float, value: Float)
    {
        let keyframe = TimelineKeyframe(time: time, value: value)
        keyframes.append(keyframe)
        sortKeyframes()
    }

    public mutating func removeKeyframe(id: UUID)
    {
        keyframes.removeAll { $0.id == id }
    }

    public mutating func updateKeyframe(id: UUID, time: Float? = nil, value: Float? = nil, handleTime: Float? = nil, handleValue: Float? = nil)
    {
        guard let index = keyframes.firstIndex(where: { $0.id == id }) else { return }

        if let t = time
        {
            keyframes[index].time = max(0, t)
        }
        if let v = value
        {
            keyframes[index].value = max(0, min(1, v)) // Clamp to 0-1
        }
        if let ht = handleTime
        {
            keyframes[index].handleTime = max(0.01, ht) // Minimum handle length
        }
        if let hv = handleValue
        {
            keyframes[index].handleValue = hv
        }

        sortKeyframes()
    }
}

// MARK: - Settings View

struct TimelineTrackView: View
{
    @Bindable var node: TimelineNode
    let trackID: UUID
    let trackHeight: CGFloat = 100

    // Interaction state
    @State private var draggingKeyframe: UUID? = nil
    @State private var draggingTangent: UUID? = nil
    @State private var dragStartLocation: CGPoint? = nil
    @State private var didDrag: Bool = false
    @State private var lastTapTime: Date = .distantPast
    @State private var lastTapLocation: CGPoint? = nil

    private var trackIndex: Int?
    {
        node.tracks.firstIndex(where: { $0.id == trackID })
    }

    private var track: TimelineTrack?
    {
        guard let index = trackIndex else { return nil }
        return node.tracks[index]
    }

    // Coordinate conversion
    private func timeToX(_ time: Float, width: CGFloat) -> CGFloat
    {
        let padding: CGFloat = 20
        let usableWidth = width - 2 * padding
        return padding + CGFloat(time / node.duration) * usableWidth
    }

    private func xToTime(_ x: CGFloat, width: CGFloat) -> Float
    {
        let padding: CGFloat = 20
        let usableWidth = width - 2 * padding
        let normalizedX = (x - padding) / usableWidth
        return Float(normalizedX) * node.duration
    }

    private func valueToY(_ value: Float, height: CGFloat) -> CGFloat
    {
        let padding: CGFloat = 10
        let usableHeight = height - 2 * padding
        // Invert Y (0 at bottom, 1 at top), allow some overshoot display
        let displayValue = (value + 0.1) / 1.2 // Map -0.1...1.1 to 0...1
        return padding + (1.0 - CGFloat(displayValue)) * usableHeight
    }

    private func yToValue(_ y: CGFloat, height: CGFloat) -> Float
    {
        let padding: CGFloat = 10
        let usableHeight = height - 2 * padding
        let normalizedY = (y - padding) / usableHeight
        let displayValue = 1.0 - Float(normalizedY)
        return displayValue * 1.2 - 0.1
    }

    var body: some View
    {
        guard let track = track, let trackIndex = trackIndex else
        {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 2)
            {
                HStack
                {
                    TextField("Track Name", text: Binding(
                        get: { node.tracks[trackIndex].name },
                        set: { node.tracks[trackIndex].name = $0; node.rebuildPorts() }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 120)
                    .font(.system(size: 10))

                    Spacer()

                    Button(action: {
                        node.removeTrack(id: trackID)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .disabled(node.tracks.count <= 1)
                }

                // Keyframe editor canvas
                GeometryReader { geo in
                    ZStack
                    {
                        // Background
                        Rectangle()
                            .fill(Color.black.opacity(0.3))

                        // Grid lines
                        gridLines(width: geo.size.width, height: geo.size.height)

                        // Bezier curve
                        bezierCurve(track: track, width: geo.size.width, height: geo.size.height)

                        // Playhead
                        playhead(width: geo.size.width, height: geo.size.height)

                        // Keyframes and handles
                        keyframeViews(track: track, trackIndex: trackIndex, width: geo.size.width, height: geo.size.height)
                    }
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStartLocation == nil
                                {
                                    dragStartLocation = value.startLocation
                                    didDrag = false
                                }

                                // Check if we've moved enough to consider it a drag
                                let dragDistance = sqrt(pow(value.location.x - value.startLocation.x, 2) +
                                                       pow(value.location.y - value.startLocation.y, 2))
                                if dragDistance > 5
                                {
                                    didDrag = true
                                }

                                handleDrag(value: value, width: geo.size.width, height: geo.size.height, trackIndex: trackIndex)
                            }
                            .onEnded { value in
                                let location = value.startLocation

                                if !didDrag
                                {
                                    // This was a click, not a drag
                                    let now = Date()
                                    let timeSinceLastTap = now.timeIntervalSince(lastTapTime)

                                    // Check if this is a double-click (within 0.3 seconds and near last tap)
                                    if let lastLoc = lastTapLocation, timeSinceLastTap < 0.3
                                    {
                                        let tapDistance = sqrt(pow(location.x - lastLoc.x, 2) + pow(location.y - lastLoc.y, 2))
                                        if tapDistance < 20
                                        {
                                            handleDoubleClick(at: location, width: geo.size.width, height: geo.size.height, trackIndex: trackIndex)
                                            lastTapTime = .distantPast
                                            lastTapLocation = nil
                                        }
                                        else
                                        {
                                            handleSingleClick(at: location, width: geo.size.width, height: geo.size.height, trackIndex: trackIndex)
                                            lastTapTime = now
                                            lastTapLocation = location
                                        }
                                    }
                                    else
                                    {
                                        handleSingleClick(at: location, width: geo.size.width, height: geo.size.height, trackIndex: trackIndex)
                                        lastTapTime = now
                                        lastTapLocation = location
                                    }
                                }

                                draggingKeyframe = nil
                                draggingTangent = nil
                                dragStartLocation = nil
                                didDrag = false
                            }
                    )
                }
                .frame(height: trackHeight)
                .border(Color.gray.opacity(0.5), width: 1)
            }
        )
    }

    @ViewBuilder
    private func gridLines(width: CGFloat, height: CGFloat) -> some View
    {
        Canvas { context, size in
            // Horizontal lines at 0, 0.5, 1
            for v in [0.0, 0.5, 1.0] as [Float]
            {
                let y = valueToY(v, height: height)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
                context.stroke(path, with: .color(.gray.opacity(0.3)), lineWidth: v == 0 || v == 1 ? 1 : 0.5)
            }

            // Vertical time markers
            let numMarkers = max(2, Int(node.duration))
            for i in 0...numMarkers
            {
                let t = Float(i) / Float(numMarkers) * node.duration
                let x = timeToX(t, width: width)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
            }
        }
    }

    @ViewBuilder
    private func bezierCurve(track: TimelineTrack, width: CGFloat, height: CGFloat) -> some View
    {
        Canvas { context, size in
            guard track.keyframes.count >= 2 else { return }

            var path = Path()

            // Sample the curve
            let numSamples = 200
            for i in 0...numSamples
            {
                let t = Float(i) / Float(numSamples) * node.duration
                let value = track.evaluate(at: t, duration: node.duration)
                let x = timeToX(t, width: width)
                let y = valueToY(value, height: height)

                if i == 0
                {
                    path.move(to: CGPoint(x: x, y: y))
                }
                else
                {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(path, with: .color(.green), lineWidth: 2)
        }
    }

    @ViewBuilder
    private func playhead(width: CGFloat, height: CGFloat) -> some View
    {
        let clampedTime = max(0, min(node.duration, node.currentTime))
        let x = timeToX(clampedTime, width: width)

        Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: height))
        }
        .stroke(Color.red, lineWidth: 2)
    }

    // Convert handle time/value offset to pixel offset
    private func handleToPixel(handleTime: Float, handleValue: Float, width: CGFloat, height: CGFloat) -> (dx: CGFloat, dy: CGFloat)
    {
        let padding: CGFloat = 20
        let usableWidth = width - 2 * padding
        let vertPadding: CGFloat = 10
        let usableHeight = height - 2 * vertPadding

        // Convert time offset to pixel offset
        let dx = CGFloat(handleTime / node.duration) * usableWidth

        // Convert value offset to pixel offset (inverted Y, scaled for display range)
        let dy = -CGFloat(handleValue / 1.2) * usableHeight

        return (dx, dy)
    }

    // Convert pixel offset to handle time/value offset
    private func pixelToHandle(dx: CGFloat, dy: CGFloat, width: CGFloat, height: CGFloat) -> (handleTime: Float, handleValue: Float)
    {
        let padding: CGFloat = 20
        let usableWidth = width - 2 * padding
        let vertPadding: CGFloat = 10
        let usableHeight = height - 2 * vertPadding

        let handleTime = Float(dx / usableWidth) * node.duration
        let handleValue = Float(-dy / usableHeight) * 1.2

        return (max(0.01, handleTime), handleValue)
    }

    @ViewBuilder
    private func keyframeViews(track: TimelineTrack, trackIndex: Int, width: CGFloat, height: CGFloat) -> some View
    {
        ForEach(track.keyframes) { keyframe in
            let x = timeToX(keyframe.time, width: width)
            let y = valueToY(keyframe.value, height: height)

            // Convert handle offset to pixels
            let (handleDx, handleDy) = handleToPixel(handleTime: keyframe.handleTime, handleValue: keyframe.handleValue, width: width, height: height)

            Group
            {
                // Tangent handle lines (both directions for symmetric)
                Path { path in
                    path.move(to: CGPoint(x: x - handleDx, y: y - handleDy))
                    path.addLine(to: CGPoint(x: x + handleDx, y: y + handleDy))
                }
                .stroke(Color.orange.opacity(0.7), lineWidth: 1)

                // Tangent handle dots (right handle)
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .position(x: x + handleDx, y: y + handleDy)

                // Left handle (mirrored)
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .position(x: x - handleDx, y: y - handleDy)

                // Keyframe dot
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .position(x: x, y: y)

                Circle()
                    .stroke(Color.green, lineWidth: 2)
                    .frame(width: 12, height: 12)
                    .position(x: x, y: y)
            }
        }
    }

    private func handleSingleClick(at location: CGPoint, width: CGFloat, height: CGFloat, trackIndex: Int)
    {
        // Check if clicking on existing keyframe
        let track = node.tracks[trackIndex]
        for keyframe in track.keyframes
        {
            let kx = timeToX(keyframe.time, width: width)
            let ky = valueToY(keyframe.value, height: height)
            let dist = sqrt(pow(location.x - kx, 2) + pow(location.y - ky, 2))

            if dist < 15
            {
                // Clicked on keyframe - don't add new one
                return
            }
        }

        // Add new keyframe at click position
        let time = max(0, min(node.duration, xToTime(location.x, width: width)))
        let value = max(0, min(1, yToValue(location.y, height: height)))
        node.tracks[trackIndex].addKeyframe(at: time, value: value)
    }

    private func handleDoubleClick(at location: CGPoint, width: CGFloat, height: CGFloat, trackIndex: Int)
    {
        let track = node.tracks[trackIndex]

        // Find keyframe near click
        for keyframe in track.keyframes
        {
            let kx = timeToX(keyframe.time, width: width)
            let ky = valueToY(keyframe.value, height: height)
            let dist = sqrt(pow(location.x - kx, 2) + pow(location.y - ky, 2))

            if dist < 15
            {
                // Don't delete if it's the only keyframe or one of two
                if track.keyframes.count > 2
                {
                    node.tracks[trackIndex].removeKeyframe(id: keyframe.id)
                }
                return
            }
        }
    }

    private func handleDrag(value: DragGesture.Value, width: CGFloat, height: CGFloat, trackIndex: Int)
    {
        let location = value.location
        let track = node.tracks[trackIndex]

        // If already dragging something, continue
        if let keyframeID = draggingKeyframe
        {
            let time = max(0, min(node.duration, xToTime(location.x, width: width)))
            let val = max(0, min(1, yToValue(location.y, height: height)))
            node.tracks[trackIndex].updateKeyframe(id: keyframeID, time: time, value: val)
            return
        }

        if let tangentID = draggingTangent
        {
            // Calculate handle position from mouse position relative to keyframe
            if let keyframe = track.keyframes.first(where: { $0.id == tangentID })
            {
                let kx = timeToX(keyframe.time, width: width)
                let ky = valueToY(keyframe.value, height: height)

                // Mouse offset from keyframe in pixels
                var dx = location.x - kx
                var dy = location.y - ky

                // Ensure we're dragging the right handle (positive dx)
                // If user is on the left side, mirror to right side
                if dx < 0
                {
                    dx = -dx
                    dy = -dy
                }

                // Minimum handle distance
                dx = max(10, dx)

                // Convert pixel offset to handle time/value
                let (handleTime, handleValue) = pixelToHandle(dx: dx, dy: dy, width: width, height: height)
                node.tracks[trackIndex].updateKeyframe(id: tangentID, handleTime: handleTime, handleValue: handleValue)
            }
            return
        }

        // Check what we're starting to drag
        for keyframe in track.keyframes
        {
            let kx = timeToX(keyframe.time, width: width)
            let ky = valueToY(keyframe.value, height: height)

            // Check tangent handles first - convert handle to pixels
            let (handleDx, handleDy) = handleToPixel(handleTime: keyframe.handleTime, handleValue: keyframe.handleValue, width: width, height: height)

            let rightHandleX = kx + handleDx
            let rightHandleY = ky + handleDy
            let leftHandleX = kx - handleDx
            let leftHandleY = ky - handleDy

            let rightDist = sqrt(pow(location.x - rightHandleX, 2) + pow(location.y - rightHandleY, 2))
            let leftDist = sqrt(pow(location.x - leftHandleX, 2) + pow(location.y - leftHandleY, 2))

            if rightDist < 12 || leftDist < 12
            {
                draggingTangent = keyframe.id
                return
            }

            // Check keyframe
            let dist = sqrt(pow(location.x - kx, 2) + pow(location.y - ky, 2))
            if dist < 15
            {
                draggingKeyframe = keyframe.id
                return
            }
        }
    }
}

struct TimelineNodeView: View
{
    @Bindable var node: TimelineNode

    var body: some View
    {
        VStack(alignment: .leading, spacing: 8)
        {
            // Header
            HStack
            {
                Text("Timeline")
                    .font(.system(size: 12))
                    .bold()

                Spacer()

                Text("Duration:")
                    .font(.system(size: 10))

                TextField("", value: $node.duration, format: .number)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 60)
                    .font(.system(size: 10))

                Button("+Track")
                {
                    node.addTrack()
                }
                .controlSize(.small)
            }

            Divider()

            // Tracks
            ScrollView
            {
                VStack(alignment: .leading, spacing: 12)
                {
                    ForEach(node.tracks) { track in
                        TimelineTrackView(node: node, trackID: track.id)
                    }
                }
            }
        }
        .padding(8)
    }
}

// MARK: - Timeline Node

@Observable public class TimelineNode: Node
{
    override public static var name: String { "Timeline" }
    override public static var nodeType: Node.NodeType { .Parameter(parameterType: .Number) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Multi-track timeline with keyframe animation" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputTime", ParameterPort(parameter: FloatParameter("Time", 0.0, .inputfield, "Current playback time for evaluating the timeline"))),
        ]
    }
    
    // Port Proxy
    public var inputTime:ParameterPort<Float> { port(named: "inputTime") }
    
    // MARK: - Codable

    private enum TimelineCodingKeys: String, CodingKey
    {
        case duration
        case tracks
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: TimelineCodingKeys.self)
        self.duration = try container.decodeIfPresent(Float.self, forKey: .duration) ?? 1.0
        self.tracks = try container.decodeIfPresent([TimelineTrack].self, forKey: .tracks) ?? []

        if tracks.isEmpty
        {
            tracks.append(TimelineTrack(name: "Track 1", duration: duration))
        }

        // Use sync instead of rebuild to preserve ports decoded by super.init
        // This maintains connection IDs across serialization
        syncPortsToTracks()
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: TimelineCodingKeys.self)
        try container.encode(self.duration, forKey: .duration)
        try container.encode(self.tracks, forKey: .tracks)
    }

    public required init(context: Context)
    {
        super.init(context: context)

        // Add default track
        tracks.append(TimelineTrack(name: "Track 1", duration: duration))
        rebuildPorts()
    }

    // MARK: - Properties

    fileprivate var duration: Float = 1.0
    {
        didSet
        {
            // Update last keyframe of each track to match new duration
            for i in 0..<tracks.count
            {
                if let lastIndex = tracks[i].keyframes.indices.last,
                   tracks[i].keyframes[lastIndex].time == oldValue
                {
                    tracks[i].keyframes[lastIndex].time = duration
                }
            }
        }
    }

    fileprivate var tracks: [TimelineTrack] = []

    // Current time for playhead display (updated during execution)
    fileprivate var currentTime: Float = 0

    // MARK: - Ports

    /// Synchronize ports to tracks, preserving existing ports when possible
    /// This is important for maintaining connections across serialization
    fileprivate func syncPortsToTracks()
    {
        let trackNames = Set(tracks.map { $0.name })
        let existingOutputs = outputPorts()
        let existingPortNames = Set(existingOutputs.map { $0.name })

        // Remove ports that no longer have matching tracks
        for port in existingOutputs
        {
            if !trackNames.contains(port.name)
            {
                removePort(port)
            }
        }

        // Add ports for tracks that don't have matching ports
        for track in tracks
        {
            if !existingPortNames.contains(track.name)
            {
                let port = NodePort<Float>(name: track.name, kind: .Outlet, description: "Animated value from timeline track")
                addDynamicPort(port)
            }
        }
    }

    /// Force rebuild all ports (used when track names change)
    fileprivate func rebuildPorts()
    {
        // Remove all existing output ports
        let existingOutputs = outputPorts()
        for port in existingOutputs
        {
            removePort(port)
        }

        // Create output port for each track
        for track in tracks
        {
            let port = NodePort<Float>(name: track.name, kind: .Outlet, description: "Animated value from timeline track")
            addDynamicPort(port)
        }
    }

    // MARK: - Track Management

    fileprivate func addTrack()
    {
        let trackNum = tracks.count + 1
        let track = TimelineTrack(name: "Track \(trackNum)", duration: duration)
        tracks.append(track)
        syncPortsToTracks()
    }

    fileprivate func removeTrack(id: UUID)
    {
        guard tracks.count > 1 else { return }
        tracks.removeAll { $0.id == id }
        syncPortsToTracks()
    }

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool
    {
        true
    }

    override public func settingsView() -> AnyView
    {
        AnyView(TimelineNodeView(node: self))
    }

    override public var settingsSize: SettingsViewSize { .Custom(size: CGSize(width: 800, height: 500)) }
    // MARK: - Execution

    public override func execute(context: GraphExecutionContext,
                                  renderPassDescriptor: MTLRenderPassDescriptor,
                                  commandBuffer: MTLCommandBuffer)
    {
        let time = self.inputTime.value ?? Float(context.timing.time)
        
        // Clamp time for display
        currentTime = max(0, min(duration, time))

        // Evaluate each track and send to corresponding port
        for track in tracks
        {
            let value = track.evaluate(at: time, duration: duration)

            if let port = findPort(named: track.name) as? NodePort<Float>
            {
                port.send(value)
            }
        }
    }
}
