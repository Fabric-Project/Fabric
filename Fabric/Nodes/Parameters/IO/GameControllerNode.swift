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
    @Bindable var node: GameControllerNode

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

                Picker("", selection: $node.selectedControllerID)
                {
                    Text("None").tag(String?.none)

                    ForEach(node.availableControllers) { controller in
                        Text(controller.displayName).tag(Optional(controller.id))
                    }
                }
                .pickerStyle(.menu)

                Button("Refresh")
                {
                    node.refreshControllers()
                }
                .controlSize(.small)
            }

            if let controllerID = node.selectedControllerID,
               let controller = node.availableControllers.first(where: { $0.id == controllerID })
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

                    Text("Outputs: \(node.outputPorts().count)")
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

@Observable public class GameControllerNode: Node
{
    override public static var name: String { "Game Controller" }
    override public static var nodeType: Node.NodeType { .Parameter(parameterType: .IO) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Read input from game controllers with semantic button names" }

    // MARK: - Codable

    private enum GameControllerCodingKeys: String, CodingKey
    {
        case selectedControllerID
        case savedControllerInfo
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: GameControllerCodingKeys.self)

        self.selectedControllerID = try container.decodeIfPresent(String.self, forKey: .selectedControllerID)
        self.savedControllerInfo = try container.decodeIfPresent(GameControllerInfo.self, forKey: .savedControllerInfo)
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: GameControllerCodingKeys.self)
        try container.encodeIfPresent(self.selectedControllerID, forKey: .selectedControllerID)

        if let controllerID = selectedControllerID,
           let info = availableControllers.first(where: { $0.id == controllerID })
        {
            try container.encode(info, forKey: .savedControllerInfo)
        }
    }

    public required init(context: Context)
    {
        super.init(context: context)
    }

    // MARK: - Properties

    @ObservationIgnored private var savedControllerInfo: GameControllerInfo?
    @ObservationIgnored private var currentController: GCController?

    @ObservationIgnored fileprivate var selectedControllerID: String?
    {
        didSet
        {
            setupController()
        }
    }

    @ObservationIgnored fileprivate var availableControllers: [GameControllerInfo] = []

    // Latest input values
    @ObservationIgnored private var axisValues: [String: Float] = [:]
    @ObservationIgnored private var buttonValues: [String: Bool] = [:]

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool
    {
        true
    }

    override public func settingsView() -> AnyView
    {
        AnyView(GameControllerNodeView(node: self))
    }

    override public var settingsSize: SettingsViewSize { .Small }

    // MARK: - Lifecycle

    public override func enableExecution(context: GraphExecutionContext)
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

    public override func disableExecution(context: GraphExecutionContext)
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

        // Clear all ports
        for port in outputPorts()
        {
            removePort(port)
        }
        axisValues.removeAll()
        buttonValues.removeAll()

        guard let controllerID = selectedControllerID,
              let controller = GCController.controllers().first(where: { $0.uniqueID == controllerID })
        else { return }

        currentController = controller
        print("[GameController] Selected: \(controller.vendorName ?? "Unknown")")

        // Setup based on profile
        if let gamepad = controller.extendedGamepad
        {
            setupExtendedGamepad(gamepad)
        }
        else if let microGamepad = controller.microGamepad
        {
            setupMicroGamepad(microGamepad)
        }
    }

    // MARK: - Extended Gamepad Setup

    private func setupExtendedGamepad(_ gamepad: GCExtendedGamepad)
    {
        print("[GameController] Setting up extended gamepad profile")

        // Thumbsticks
        createAxisPort("Left Stick X")
        createAxisPort("Left Stick Y")
        createButtonPort("Left Stick Press")
        createAxisPort("Right Stick X")
        createAxisPort("Right Stick Y")
        createButtonPort("Right Stick Press")

        // D-Pad
        createButtonPort("D-Pad Up")
        createButtonPort("D-Pad Down")
        createButtonPort("D-Pad Left")
        createButtonPort("D-Pad Right")

        // Face buttons
        createButtonPort("A")
        createButtonPort("B")
        createButtonPort("X")
        createButtonPort("Y")

        // Shoulders and triggers
        createButtonPort("Left Bumper")
        createButtonPort("Right Bumper")
        createAxisPort("Left Trigger")
        createAxisPort("Right Trigger")

        // Menu buttons
        createButtonPort("Menu")
        createButtonPort("Options")

        // Additional buttons (if available)
        if gamepad.buttonHome != nil
        {
            createButtonPort("Home")
        }

        // Touchpad (DualShock/DualSense)
        if gamepad.responds(to: Selector(("touchpadButton")))
        {
            createButtonPort("Touchpad")
        }

        // Set up value changed handler
        gamepad.valueChangedHandler = { [weak self] gamepad, element in
            self?.handleExtendedGamepadChange(gamepad, element: element)
        }
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

    private func setupMicroGamepad(_ gamepad: GCMicroGamepad)
    {
        print("[GameController] Setting up micro gamepad profile")

        createAxisPort("D-Pad X")
        createAxisPort("D-Pad Y")
        createButtonPort("A")
        createButtonPort("X")
        createButtonPort("Menu")

        gamepad.valueChangedHandler = { [weak self] gamepad, element in
            self?.handleMicroGamepadChange(gamepad, element: element)
        }
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

    private func createAxisPort(_ name: String)
    {
        let port = NodePort<Float>(name: name, kind: .Outlet)
        addDynamicPort(port)
        axisValues[name] = 0.0
    }

    private func createButtonPort(_ name: String)
    {
        let port = NodePort<Bool>(name: name, kind: .Outlet)
        addDynamicPort(port)
        buttonValues[name] = false
    }

    // MARK: - Execution

    public override func execute(context: GraphExecutionContext,
                                  renderPassDescriptor: MTLRenderPassDescriptor,
                                  commandBuffer: MTLCommandBuffer)
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
