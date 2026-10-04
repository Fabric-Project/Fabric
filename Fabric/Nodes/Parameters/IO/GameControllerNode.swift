//
//  GameControllerNode.swift
//  Fabric
//
//  Created by Claude Code on 1/27/26.
//

import Foundation
import SwiftUI
import Metal
import GameController
import Satin
import simd
import Synchronization
import os

// MARK: - Controller Info

public struct GameControllerInfo: Codable, Equatable, Identifiable, Hashable
{
    public let id: String
    public let displayName: String
    public let vendorName: String?
    public let productCategory: String

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
    }
}

// MARK: - Settings View

struct GameControllerNodeView: View
{
    @Bindable var model: GameControllerNode.SettingsModel

    var body: some View
    {
        VStack(alignment: .leading, spacing: 8)
        {
            Text("Game Controller")
                .font(.system(size: 10))
                .bold()

            HStack
            {
                Text("Controller:")
                    .font(.system(size: 10))

                Picker("", selection: $model.selectedControllerID)
                {
                    Text("None").tag(String?.none)

                    ForEach(model.availableControllers) { controller in
                        Text(controller.displayName).tag(Optional(controller.id))
                    }
                }
                .pickerStyle(.menu)

                Button("Refresh")
                {
                    model.refreshControllers()
                }
                .controlSize(.small)
            }

            if let controllerFailure = model.controllerFailure
            {
                Text(controllerFailure)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }

            if let controllerID = model.selectedControllerID,
               let controller = model.availableControllers.first(where: { $0.id == controllerID })
            {
                Divider()

                VStack(alignment: .leading, spacing: 4)
                {
                    if let vendor = controller.vendorName
                    {
                        Text("Vendor: \(vendor)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }

                    Text("Type: \(controller.productCategory)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    Text("Outputs: \(model.outputPortCount)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(4)
    }
}

// MARK: - Game Controller Node

public class GameControllerNode: Node
{
    fileprivate static let log = Logger(subsystem: "graphics.fabric", category: "GameControllerNode")

    override public static var name: String { "Game Controller" }
    override public static var nodeType: Node.NodeType { .Parameter(parameterType: .IO) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Read input from game controllers with semantic button names" }

    // Dynamic node name based on selected controller
    override public func deriveSubtitle() -> String?
    {
        if let controllerID = selectedControllerID,
           let controller = availableControllers.first(where: { $0.id == controllerID })
        {
            return controller.displayName
        }
        return nil
    }

    // MARK: - Codable

    private enum GameControllerCodingKeys: String, CodingKey
    {
        case selectedControllerID
        case savedControllerInfo
        case portDescriptors
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: GameControllerCodingKeys.self)

        self.selectedControllerID = try container.decodeIfPresent(String.self, forKey: .selectedControllerID)
        self.savedControllerInfo = try container.decodeIfPresent(GameControllerInfo.self, forKey: .savedControllerInfo)

        // The port set derives from a controller profile that is not present
        // at decode time, so it persists as descriptors and rebuilds here;
        // each recreated port adopts its persisted identity and state by
        // registry key as it registers, before the graph's connection restore
        // runs. When the saved controller reconnects, setupController syncs
        // against these same ports by name instead of recreating them.
        let descriptors = try container.decodeIfPresent([DeviceOutputPortDescriptor].self, forKey: .portDescriptors) ?? []
        self.synchronizePorts(to: descriptors)
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: GameControllerCodingKeys.self)
        try container.encodeIfPresent(self.selectedControllerID, forKey: .selectedControllerID)
        try container.encode(self.currentPortDescriptors(), forKey: .portDescriptors)

        // The reconnect record has to outlive the hardware: saving with the
        // controller unplugged — or before enableExecution has ever discovered
        // one — must not erase what the document already knew.
        try container.encodeIfPresent(self.liveControllerInfo() ?? self.savedControllerInfo,
                                      forKey: .savedControllerInfo)
    }

    public required init(context: Context)
    {
        super.init(context: context)
    }

    // MARK: - Properties

    private var savedControllerInfo: GameControllerInfo?
    // Controller state is main-thread state: the controller's handler, the
    // notifications and the settings view all use main. Lifecycle calls, which
    // can run on the render thread, hand over to main; the main queue keeps
    // them in order.
    private var currentController: GCController?
    private var controllerObservers: [any NSObjectProtocol] = []
    /// Whether the node is started. It receives from its controller only while started.
    private var isRunning = false
    private var subscribedController: GCController?

    fileprivate var selectedControllerID: String?
    {
        didSet
        {
            setupController()
            _settingsModelStorage?.selectedControllerID = selectedControllerID
            _settingsModelStorage?.outputPortCount = outputPorts().count
            // `subtitle` is derived from the selected controller; notify so the title refreshes.
            self.subtitleSubject.send()
        }
    }

    fileprivate var availableControllers: [GameControllerInfo] = []

    /// The selected controller as the last discovery pass saw it, or nil when
    /// nothing is plugged in.
    private func liveControllerInfo() -> GameControllerInfo?
    {
        guard let controllerID = selectedControllerID else { return nil }
        return availableControllers.first { $0.id == controllerID }
    }

    // Latest input values: written on the main queue, read by execute on the render thread.
    private struct ControllerValues
    {
        var axisValues: [String: Float] = [:]
        var buttonValues: [String: Bool] = [:]
    }
    private let controllerValues = Mutex(ControllerValues())

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool { true }

    override public func settingsView() -> AnyView
    {
        if _settingsModelStorage == nil { _settingsModelStorage = SettingsModel(node: self) }
        return AnyView(GameControllerNodeView(model: _settingsModelStorage!))
    }

    override public var settingsSize: SettingsViewSize { .Small }

    // MARK: - Settings Model

    @Observable final class SettingsModel
    {
        var selectedControllerID: String?
        {
            didSet
            {
                guard selectedControllerID != node?.selectedControllerID else { return }
                node?.selectedControllerID = selectedControllerID
            }
        }
        var availableControllers: [GameControllerInfo] = []
        var outputPortCount: Int = 0
        /// Why the node cannot receive although it is started, or nil.
        var controllerFailure: String?

        private weak var node: GameControllerNode?

        init(node: GameControllerNode)
        {
            self.node = node
            self.selectedControllerID = node.selectedControllerID
            self.availableControllers = node.availableControllers
            self.outputPortCount = node.outputPorts().count
            self.controllerFailure = node.controllerStatus?.message
        }

        func refreshControllers() { node?.refreshControllers() }
    }

    private var _settingsModelStorage: SettingsModel? = nil

    // MARK: - Lifecycle

    // Enabled, the node lists controllers and has the selected controller's
    // ports; started, it receives from the controller.
    public override func enableExecution(renderer:GraphRenderer)
    throws
    {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setupNotifications()
            self.refreshControllers()

            // Try to reconnect to saved controller
            if let savedInfo = self.savedControllerInfo
            {
                if let matching = self.availableControllers.first(where: {
                    $0.vendorName == savedInfo.vendorName && $0.productCategory == savedInfo.productCategory
                })
                {
                    self.selectedControllerID = matching.id
                }
            }
        }
        try super.enableExecution(renderer: renderer)
    }

    public override func startExecution(renderer:GraphRenderer)
    throws
    {
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = true
            self?.updateSubscription()
            self?.updateControllerStatus()
        }
        try super.startExecution(renderer: renderer)
    }

    public override func stopExecution(renderer:GraphRenderer)
    throws
    {
        // Holds the node: a deleted node can be freed before this runs, and its
        // subscription must still go.
        DispatchQueue.main.async {
            self.isRunning = false
            self.updateSubscription()
            self.updateControllerStatus()
        }
        try super.stopExecution(renderer: renderer)
    }

    public override func disableExecution(renderer:GraphRenderer)
    throws
    {
        DispatchQueue.main.async { self.removeNotifications() }
        try super.disableExecution(renderer: renderer)
    }

    private func setupNotifications()
    {
        controllerObservers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.controllerDidConnect()
        })

        controllerObservers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let controller = notification.object as? GCController,
               self?.currentController == controller
            {
                self?.currentController = nil
                self?.updateSubscription()
            }
            self?.refreshControllers()
            self?.updateControllerStatus()
        })

        // Start wireless controller discovery
        GCController.startWirelessControllerDiscovery { }
    }

    // Block-based observers are removed by their tokens; removeObserver(self) does not reach them.
    private func removeNotifications()
    {
        controllerObservers.forEach(NotificationCenter.default.removeObserver)
        controllerObservers.removeAll()
    }

    fileprivate func refreshControllers()
    {
        availableControllers = GCController.controllers().map { controller in
            GameControllerInfo(
                id: controller.uniqueID,
                displayName: controller.vendorName ?? "Controller",
                vendorName: controller.vendorName,
                productCategory: controller.productCategory
            )
        }

        _settingsModelStorage?.availableControllers = availableControllers
        // `subtitle` resolves against the controller list; notify so the title refreshes.
        self.subtitleSubject.send()

        print("[GameController] Found \(availableControllers.count) controllers:")
        for info in availableControllers
        {
            print("  - \(info.displayName) (\(info.productCategory))")
        }
    }

    private func updateSubscription()
    {
        let wantedController = isRunning ? currentController : nil
        guard wantedController !== subscribedController else { return }

        if let subscribedController
        {
            GameControllerSubscriptions.shared.unsubscribe(self, from: subscribedController)
        }
        if let wantedController
        {
            GameControllerSubscriptions.shared.subscribe(self, to: wantedController)
        }
        subscribedController = wantedController
    }

    private func setupController()
    {
        currentController = nil
        controllerValues.withLock { $0 = ControllerValues() }

        guard let controllerID = selectedControllerID,
              let controller = GCController.controllers().first(where: { $0.uniqueID == controllerID })
        else
        {
            // Choosing none forgets the controller, so a controller connecting does not bring it back.
            if selectedControllerID == nil
            {
                savedControllerInfo = nil
            }
            self.synchronizePorts(to: [])
            _settingsModelStorage?.outputPortCount = outputPorts().count
            updateSubscription()
            updateControllerStatus()
            return
        }

        currentController = controller
        self.savedControllerInfo = self.liveControllerInfo() ?? self.savedControllerInfo
        print("[GameController] Selected: \(controller.vendorName ?? "Unknown")")

        // Setup based on profile
        let descriptors: [DeviceOutputPortDescriptor]
        if let gamepad = controller.extendedGamepad
        {
            descriptors = Self.extendedGamepadPortDescriptors(gamepad)
        }
        else if controller.microGamepad != nil
        {
            descriptors = Self.microGamepadPortDescriptors()
        }
        else
        {
            descriptors = []
        }

        self.synchronizePorts(to: descriptors)
        _settingsModelStorage?.outputPortCount = outputPorts().count
        updateSubscription()
        updateControllerStatus()
    }

    /// The selected controller may be back, with a new id, as the id carries its
    /// index among connected controllers: match it as enable does.
    private func controllerDidConnect()
    {
        refreshControllers()

        if currentController == nil,
           let savedInfo = savedControllerInfo,
           let matching = availableControllers.first(where: {
               $0.vendorName == savedInfo.vendorName && $0.productCategory == savedInfo.productCategory
           })
        {
            selectedControllerID = matching.id
        }
        updateControllerStatus()
    }

    // MARK: - Controller Status

    /// Set while the node is started but has no controller to receive from.
    /// Worded once, in updateControllerStatus(), so the glyph, the settings view
    /// and the log agree.
    private var controllerStatus: NodeStatus?
    {
        didSet
        {
            guard controllerStatus != oldValue else { return }
            if let controllerStatus
            {
                Self.log.error("\(controllerStatus.message, privacy: .public)")
            }
            _settingsModelStorage?.controllerFailure = controllerStatus?.message
            self.subtitleSubject.send()
        }
    }

    override public func deriveStatuses() -> [NodeStatus] { controllerStatus.map { [$0] } ?? [] }

    // No Retry: a controller connecting reconnects itself.
    private func updateControllerStatus()
    {
        if !isRunning
        {
            controllerStatus = nil
        }
        else if selectedControllerID == nil
        {
            controllerStatus = .warning("No game controller is selected.")
        }
        else if currentController == nil
        {
            controllerStatus = .warning("\(savedControllerInfo?.displayName ?? "The selected game controller") is not connected.")
        }
        else
        {
            controllerStatus = nil
        }
    }

    /// Called by GameControllerSubscriptions, on main, for each change on the subscribed controller.
    fileprivate func receiveChange(from controller: GCController)
    {
        controllerValues.withLock { values in
            if let gamepad = controller.extendedGamepad
            {
                Self.read(gamepad, into: &values)
            }
            else if let microGamepad = controller.microGamepad
            {
                Self.read(microGamepad, into: &values)
            }
        }
        self.markDirty()
    }

    // MARK: - Extended Gamepad Setup

    private static func extendedGamepadPortDescriptors(_ gamepad: GCExtendedGamepad) -> [DeviceOutputPortDescriptor]
    {
        var descriptors: [DeviceOutputPortDescriptor] = [
            // Thumbsticks
            .init(name: "Left Stick X", isButton: false),
            .init(name: "Left Stick Y", isButton: false),
            .init(name: "Left Stick Press", isButton: true),
            .init(name: "Right Stick X", isButton: false),
            .init(name: "Right Stick Y", isButton: false),
            .init(name: "Right Stick Press", isButton: true),

            // D-Pad
            .init(name: "D-Pad Up", isButton: true),
            .init(name: "D-Pad Down", isButton: true),
            .init(name: "D-Pad Left", isButton: true),
            .init(name: "D-Pad Right", isButton: true),

            // Face buttons
            .init(name: "A", isButton: true),
            .init(name: "B", isButton: true),
            .init(name: "X", isButton: true),
            .init(name: "Y", isButton: true),

            // Shoulders and triggers
            .init(name: "Left Bumper", isButton: true),
            .init(name: "Right Bumper", isButton: true),
            .init(name: "Left Trigger", isButton: false),
            .init(name: "Right Trigger", isButton: false),

            // Menu buttons
            .init(name: "Menu", isButton: true),
            .init(name: "Options", isButton: true),
        ]

        if gamepad.buttonHome != nil
        {
            descriptors.append(.init(name: "Home", isButton: true))
        }

        // Touchpad (DualShock/DualSense)
        if gamepad.responds(to: Selector(("touchpadButton")))
        {
            descriptors.append(.init(name: "Touchpad", isButton: true))
        }

        return descriptors
    }

    private static func read(_ gamepad: GCExtendedGamepad, into values: inout ControllerValues)
    {
        // Thumbsticks
        values.axisValues["Left Stick X"] = gamepad.leftThumbstick.xAxis.value
        values.axisValues["Left Stick Y"] = gamepad.leftThumbstick.yAxis.value
        values.buttonValues["Left Stick Press"] = gamepad.leftThumbstickButton?.isPressed ?? false

        values.axisValues["Right Stick X"] = gamepad.rightThumbstick.xAxis.value
        values.axisValues["Right Stick Y"] = gamepad.rightThumbstick.yAxis.value
        values.buttonValues["Right Stick Press"] = gamepad.rightThumbstickButton?.isPressed ?? false

        // D-Pad
        values.buttonValues["D-Pad Up"] = gamepad.dpad.up.isPressed
        values.buttonValues["D-Pad Down"] = gamepad.dpad.down.isPressed
        values.buttonValues["D-Pad Left"] = gamepad.dpad.left.isPressed
        values.buttonValues["D-Pad Right"] = gamepad.dpad.right.isPressed

        // Face buttons
        values.buttonValues["A"] = gamepad.buttonA.isPressed
        values.buttonValues["B"] = gamepad.buttonB.isPressed
        values.buttonValues["X"] = gamepad.buttonX.isPressed
        values.buttonValues["Y"] = gamepad.buttonY.isPressed

        // Shoulders and triggers
        values.buttonValues["Left Bumper"] = gamepad.leftShoulder.isPressed
        values.buttonValues["Right Bumper"] = gamepad.rightShoulder.isPressed
        values.axisValues["Left Trigger"] = gamepad.leftTrigger.value
        values.axisValues["Right Trigger"] = gamepad.rightTrigger.value

        // Menu buttons
        values.buttonValues["Menu"] = gamepad.buttonMenu.isPressed
        values.buttonValues["Options"] = gamepad.buttonOptions?.isPressed ?? false
        values.buttonValues["Home"] = gamepad.buttonHome?.isPressed ?? false
    }

    // MARK: - Micro Gamepad Setup (Siri Remote, etc.)

    private static func microGamepadPortDescriptors() -> [DeviceOutputPortDescriptor]
    {
        [
            .init(name: "D-Pad X", isButton: false),
            .init(name: "D-Pad Y", isButton: false),
            .init(name: "A", isButton: true),
            .init(name: "X", isButton: true),
            .init(name: "Menu", isButton: true),
        ]
    }

    private static func read(_ gamepad: GCMicroGamepad, into values: inout ControllerValues)
    {
        values.axisValues["D-Pad X"] = gamepad.dpad.xAxis.value
        values.axisValues["D-Pad Y"] = gamepad.dpad.yAxis.value
        values.buttonValues["A"] = gamepad.buttonA.isPressed
        values.buttonValues["X"] = gamepad.buttonX.isPressed
        values.buttonValues["Menu"] = gamepad.buttonMenu.isPressed
    }

    // MARK: - Port Creation

    /// The persisted projection of the port set: encode derives it from the
    /// live ports rather than storing a parallel list that could drift.
    private func currentPortDescriptors() -> [DeviceOutputPortDescriptor]
    {
        outputPorts().map { port in
            DeviceOutputPortDescriptor(name: port.name, isButton: port is NodePort<Bool>)
        }
    }

    private func synchronizePorts(to descriptors: [DeviceOutputPortDescriptor])
    {
        synchronizeDeviceOutputPorts(to: descriptors,
                                     buttonDescription: "Controller button state (true when pressed)",
                                     axisDescription: "Controller axis value normalized from -1 to 1")

        controllerValues.withLock { values in
            for descriptor in descriptors
            {
                if descriptor.isButton
                {
                    values.buttonValues[descriptor.name] = values.buttonValues[descriptor.name] ?? false
                }
                else
                {
                    values.axisValues[descriptor.name] = values.axisValues[descriptor.name] ?? 0.0
                }
            }
        }
    }

    // MARK: - Execution

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        let currentValues = controllerValues.withLock { $0 }

        // Send axis values
        for (name, value) in currentValues.axisValues
        {
            if let port = findPort(named: name) as? NodePort<Float>
            {
                port.send(value)
            }
        }

        // Send button values
        for (name, value) in currentValues.buttonValues
        {
            if let port = findPort(named: name) as? NodePort<Bool>
            {
                port.send(value)
            }
        }
    }
}

// MARK: - Controller Subscriptions

/// A controller's value handler is one property on an object the whole process
/// shares, so nodes never set it: one handler per controller passes each change
/// to every node subscribed to that controller. Main thread only, as are the
/// controller's handlers.
private final class GameControllerSubscriptions
{
    static let shared = GameControllerSubscriptions()

    private struct Subscriber
    {
        weak var node: GameControllerNode?
    }

    private var subscribers: [ObjectIdentifier: [Subscriber]] = [:]

    func subscribe(_ node: GameControllerNode, to controller: GCController)
    {
        let controllerKey = ObjectIdentifier(controller)
        if subscribers[controllerKey] == nil
        {
            installHandler(on: controller)
        }
        subscribers[controllerKey, default: []].append(Subscriber(node: node))
    }

    func unsubscribe(_ node: GameControllerNode, from controller: GCController)
    {
        let controllerKey = ObjectIdentifier(controller)
        subscribers[controllerKey]?.removeAll { $0.node == nil || $0.node === node }

        guard let remaining = subscribers[controllerKey], remaining.isEmpty else { return }
        subscribers[controllerKey] = nil
        controller.extendedGamepad?.valueChangedHandler = nil
        controller.microGamepad?.valueChangedHandler = nil
    }

    private func installHandler(on controller: GCController)
    {
        let controllerKey = ObjectIdentifier(controller)
        let deliverChange = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.subscribers[controllerKey]?.forEach { $0.node?.receiveChange(from: controller) }
        }

        if let gamepad = controller.extendedGamepad
        {
            gamepad.valueChangedHandler = { _, _ in deliverChange() }
        }
        else if let microGamepad = controller.microGamepad
        {
            microGamepad.valueChangedHandler = { _, _ in deliverChange() }
        }
    }
}

// MARK: - GCController Extension

extension GCController
{
    /// Unique identifier for the controller
    var uniqueID: String
    {
        // Use a combination of vendor name and product category as a semi-stable ID
        // Note: GCController doesn't have a truly unique persistent ID
        let vendor = vendorName ?? "Unknown"
        let category = productCategory
        let index = GCController.controllers().firstIndex(of: self) ?? 0
        return "\(vendor)_\(category)_\(index)"
    }
}
