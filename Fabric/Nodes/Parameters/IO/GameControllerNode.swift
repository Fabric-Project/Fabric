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

/// A controller output port as persisted: the port set derives from a live
/// controller's profile, so the document carries these descriptors and decode
/// rebuilds the ports from them before any hardware is discovered.
public struct GameControllerPortDescriptor: Codable, Equatable
{
    public let name: String
    public let isButton: Bool
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
    override public static var name: String { "Game Controller" }
    override public static var nodeType: Node.NodeType { .Parameter(parameterType: .IO) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Read input from game controllers with semantic button names" }

    // Dynamic node name based on selected controller
    override public var displayName: String?
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
        let descriptors = try container.decodeIfPresent([GameControllerPortDescriptor].self, forKey: .portDescriptors) ?? []
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
    private var currentController: GCController?

    fileprivate var selectedControllerID: String?
    {
        didSet
        {
            setupController()
            _settingsModelStorage?.selectedControllerID = selectedControllerID
            _settingsModelStorage?.outputPortCount = outputPorts().count
            // `displayName` is derived from the selected controller; notify so the title refreshes.
            self.nameSubject.send()
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

    // Latest input values
    private var axisValues: [String: Float] = [:]
    private var buttonValues: [String: Bool] = [:]

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

        private weak var node: GameControllerNode?

        init(node: GameControllerNode)
        {
            self.node = node
            self.selectedControllerID = node.selectedControllerID
            self.availableControllers = node.availableControllers
            self.outputPortCount = node.outputPorts().count
        }

        func refreshControllers() { node?.refreshControllers() }
    }

    private var _settingsModelStorage: SettingsModel? = nil

    // MARK: - Lifecycle

    public override func enableExecution(renderer:GraphRenderer)
    throws
    {
        setupNotifications()
        refreshControllers()

        // Try to reconnect to saved controller
        if let savedInfo = savedControllerInfo
        {
            if let matching = availableControllers.first(where: {
                $0.vendorName == savedInfo.vendorName && $0.productCategory == savedInfo.productCategory
            })
            {
                selectedControllerID = matching.id
            }
        }
    }

    public override func disableExecution(renderer:GraphRenderer)
    throws
    {
        NotificationCenter.default.removeObserver(self)
        currentController = nil
    }

    private func setupNotifications()
    {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshControllers()
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let controller = notification.object as? GCController,
               self?.currentController == controller
            {
                self?.currentController = nil
            }
            self?.refreshControllers()
        }

        // Start wireless controller discovery
        GCController.startWirelessControllerDiscovery { }
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

        print("[GameController] Found \(availableControllers.count) controllers:")
        for info in availableControllers
        {
            print("  - \(info.displayName) (\(info.productCategory))")
        }
    }

    private func setupController()
    {
        // Remove handlers from old controller
        currentController?.extendedGamepad?.valueChangedHandler = nil
        currentController?.microGamepad?.valueChangedHandler = nil
        currentController = nil

        axisValues.removeAll()
        buttonValues.removeAll()

        guard let controllerID = selectedControllerID,
              let controller = GCController.controllers().first(where: { $0.uniqueID == controllerID })
        else
        {
            self.synchronizePorts(to: [])
            _settingsModelStorage?.outputPortCount = outputPorts().count
            return
        }

        currentController = controller
        self.savedControllerInfo = self.liveControllerInfo() ?? self.savedControllerInfo
        print("[GameController] Selected: \(controller.vendorName ?? "Unknown")")

        // Setup based on profile
        let descriptors: [GameControllerPortDescriptor]
        if let gamepad = controller.extendedGamepad
        {
            descriptors = Self.extendedGamepadPortDescriptors(gamepad)
            gamepad.valueChangedHandler = { [weak self] gamepad, element in
                self?.handleExtendedGamepadChange(gamepad, element: element)
            }
        }
        else if let microGamepad = controller.microGamepad
        {
            descriptors = Self.microGamepadPortDescriptors()
            microGamepad.valueChangedHandler = { [weak self] gamepad, element in
                self?.handleMicroGamepadChange(gamepad, element: element)
            }
        }
        else
        {
            descriptors = []
        }

        self.synchronizePorts(to: descriptors)
        _settingsModelStorage?.outputPortCount = outputPorts().count
    }

    // MARK: - Extended Gamepad Setup

    private static func extendedGamepadPortDescriptors(_ gamepad: GCExtendedGamepad) -> [GameControllerPortDescriptor]
    {
        var descriptors: [GameControllerPortDescriptor] = [
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

    private func handleExtendedGamepadChange(_ gamepad: GCExtendedGamepad, element: GCControllerElement)
    {
        // Thumbsticks
        axisValues["Left Stick X"] = gamepad.leftThumbstick.xAxis.value
        axisValues["Left Stick Y"] = gamepad.leftThumbstick.yAxis.value
        buttonValues["Left Stick Press"] = gamepad.leftThumbstickButton?.isPressed ?? false

        axisValues["Right Stick X"] = gamepad.rightThumbstick.xAxis.value
        axisValues["Right Stick Y"] = gamepad.rightThumbstick.yAxis.value
        buttonValues["Right Stick Press"] = gamepad.rightThumbstickButton?.isPressed ?? false

        // D-Pad
        buttonValues["D-Pad Up"] = gamepad.dpad.up.isPressed
        buttonValues["D-Pad Down"] = gamepad.dpad.down.isPressed
        buttonValues["D-Pad Left"] = gamepad.dpad.left.isPressed
        buttonValues["D-Pad Right"] = gamepad.dpad.right.isPressed

        // Face buttons
        buttonValues["A"] = gamepad.buttonA.isPressed
        buttonValues["B"] = gamepad.buttonB.isPressed
        buttonValues["X"] = gamepad.buttonX.isPressed
        buttonValues["Y"] = gamepad.buttonY.isPressed

        // Shoulders and triggers
        buttonValues["Left Bumper"] = gamepad.leftShoulder.isPressed
        buttonValues["Right Bumper"] = gamepad.rightShoulder.isPressed
        axisValues["Left Trigger"] = gamepad.leftTrigger.value
        axisValues["Right Trigger"] = gamepad.rightTrigger.value

        // Menu buttons
        buttonValues["Menu"] = gamepad.buttonMenu.isPressed
        buttonValues["Options"] = gamepad.buttonOptions?.isPressed ?? false
        buttonValues["Home"] = gamepad.buttonHome?.isPressed ?? false

        self.markDirty()
    }

    // MARK: - Micro Gamepad Setup (Siri Remote, etc.)

    private static func microGamepadPortDescriptors() -> [GameControllerPortDescriptor]
    {
        [
            .init(name: "D-Pad X", isButton: false),
            .init(name: "D-Pad Y", isButton: false),
            .init(name: "A", isButton: true),
            .init(name: "X", isButton: true),
            .init(name: "Menu", isButton: true),
        ]
    }

    private func handleMicroGamepadChange(_ gamepad: GCMicroGamepad, element: GCControllerElement)
    {
        axisValues["D-Pad X"] = gamepad.dpad.xAxis.value
        axisValues["D-Pad Y"] = gamepad.dpad.yAxis.value
        buttonValues["A"] = gamepad.buttonA.isPressed
        buttonValues["X"] = gamepad.buttonX.isPressed
        buttonValues["Menu"] = gamepad.buttonMenu.isPressed

        self.markDirty()
    }

    // MARK: - Port Creation

    /// The persisted projection of the port set: encode derives it from the
    /// live ports rather than storing a parallel list that could drift.
    private func currentPortDescriptors() -> [GameControllerPortDescriptor]
    {
        outputPorts().map { port in
            GameControllerPortDescriptor(name: port.name, isButton: port is NodePort<Bool>)
        }
    }

    /// Syncs the registered output ports to `descriptors` by name and type,
    /// HIDNode-style: matching ports survive (a reconnecting controller must
    /// not replace decoded ports, or their restored wires die with them),
    /// stale ones are removed, missing ones created.
    private func synchronizePorts(to descriptors: [GameControllerPortDescriptor])
    {
        let descriptorsByName = Dictionary(descriptors.map { ($0.name, $0) },
                                           uniquingKeysWith: { first, _ in first })

        for port in outputPorts()
        {
            if let descriptor = descriptorsByName[port.name],
               descriptor.isButton == (port is NodePort<Bool>)
            {
                continue
            }

            removePort(port)
        }

        for descriptor in descriptors
        {
            if descriptor.isButton
            {
                buttonValues[descriptor.name] = buttonValues[descriptor.name] ?? false
                if (findPort(named: descriptor.name) as Port?) == nil
                {
                    addDynamicPort(NodePort<Bool>(name: descriptor.name, kind: .Outlet,
                                                  description: "Controller button state (true when pressed)"))
                }
            }
            else
            {
                axisValues[descriptor.name] = axisValues[descriptor.name] ?? 0.0
                if (findPort(named: descriptor.name) as Port?) == nil
                {
                    addDynamicPort(NodePort<Float>(name: descriptor.name, kind: .Outlet,
                                                   description: "Controller axis value normalized from -1 to 1"))
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
        // Send axis values
        for (name, value) in axisValues
        {
            if let port = findPort(named: name) as? NodePort<Float>
            {
                port.send(value)
            }
        }

        // Send button values
        for (name, value) in buttonValues
        {
            if let port = findPort(named: name) as? NodePort<Bool>
            {
                port.send(value)
            }
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
