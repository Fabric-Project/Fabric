//
//  HIDNode.swift
//  Fabric
//
//  Created by Claude Code on 1/26/26.
//

import Foundation
import SwiftUI
import Metal
import IOKit
import IOKit.hid

// MARK: - HID Device Info

/// Represents a connected HID device
public struct HIDDeviceInfo: Codable, Equatable, Identifiable, Hashable
{
    public let id: String // Unique identifier (vendor:product:location)
    public let vendorID: Int
    public let productID: Int
    public let productName: String
    public let manufacturer: String

    public var displayName: String
    {
        if !productName.isEmpty
        {
            return productName
        }
        else if !manufacturer.isEmpty
        {
            return "\(manufacturer) Device"
        }
        else
        {
            return "HID Device (\(String(format: "%04X:%04X", vendorID, productID)))"
        }
    }

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(id)
    }
}

/// Represents an element (input/output) on an HID device
public struct HIDElementInfo: Codable, Equatable, Identifiable
{
    public let id: String
    public let cookie: Int
    public let usagePage: Int
    public let usage: Int
    public let displayName: String
    public let min: Int
    public let max: Int
    public let isRelative: Bool

    public var isButton: Bool
    {
        usagePage == kHIDPage_Button || (min == 0 && max == 1)
    }
}

// MARK: - HID Usage Names

struct HIDUsageNames
{
    static func nameForUsage(page: Int, usage: Int) -> String
    {
        switch page
        {
        case kHIDPage_GenericDesktop:
            return genericDesktopName(usage: usage)
        case kHIDPage_Button:
            return "Btn\(usage)"
        case kHIDPage_KeyboardOrKeypad:
            return keyboardName(usage: usage)
        case kHIDPage_Consumer:
            return consumerName(usage: usage)
        case kHIDPage_Digitizer:
            return digitizerName(usage: usage)
        case kHIDPage_Simulation:
            return simulationName(usage: usage)
        case kHIDPage_Game:
            return gameName(usage: usage)
        default:
            return "Input_\(page)_\(usage)"
        }
    }

    private static func genericDesktopName(usage: Int) -> String
    {
        switch usage
        {
        case kHIDUsage_GD_Pointer: return "Pointer"
        case kHIDUsage_GD_Mouse: return "Mouse"
        case kHIDUsage_GD_Joystick: return "Joystick"
        case kHIDUsage_GD_GamePad: return "Gamepad"
        case kHIDUsage_GD_Keyboard: return "Keyboard"
        case kHIDUsage_GD_Keypad: return "Keypad"
        case kHIDUsage_GD_X: return "X"
        case kHIDUsage_GD_Y: return "Y"
        case kHIDUsage_GD_Z: return "Z"
        case kHIDUsage_GD_Rx: return "Rx"
        case kHIDUsage_GD_Ry: return "Ry"
        case kHIDUsage_GD_Rz: return "Rz"
        case kHIDUsage_GD_Slider: return "Slider"
        case kHIDUsage_GD_Dial: return "Dial"
        case kHIDUsage_GD_Wheel: return "Wheel"
        case kHIDUsage_GD_Hatswitch: return "Hat"
        case kHIDUsage_GD_DPadUp: return "DPad Up"
        case kHIDUsage_GD_DPadDown: return "DPad Down"
        case kHIDUsage_GD_DPadRight: return "DPad Right"
        case kHIDUsage_GD_DPadLeft: return "DPad Left"
        case kHIDUsage_GD_Vx: return "Vx"
        case kHIDUsage_GD_Vy: return "Vy"
        case kHIDUsage_GD_Vz: return "Vz"
        case kHIDUsage_GD_Vbrx: return "VRx"
        case kHIDUsage_GD_Vbry: return "VRy"
        case kHIDUsage_GD_Vbrz: return "VRz"
        case kHIDUsage_GD_SystemControl: return "System"
        case kHIDUsage_GD_CountedBuffer: return "Buffer"
        default: return "Axis\(usage)"
        }
    }

    private static func simulationName(usage: Int) -> String
    {
        switch usage
        {
        case 0xB0: return "Rudder"
        case 0xB1: return "Throttle"
        case 0xB2: return "Accelerator"
        case 0xB3: return "Brake"
        case 0xB4: return "Clutch"
        case 0xB5: return "Shifter"
        case 0xB6: return "Steering"
        case 0xBA: return "Aileron"
        case 0xBB: return "Elevator"
        default: return "Sim\(usage)"
        }
    }

    private static func gameName(usage: Int) -> String
    {
        switch usage
        {
        case 0x20: return "Turn"
        case 0x21: return "Pitch"
        case 0x22: return "Roll"
        case 0x23: return "Move Right/Left"
        case 0x24: return "Move Forward/Back"
        case 0x25: return "Move Up/Down"
        case 0x26: return "Lean Right/Left"
        case 0x27: return "Lean Forward/Back"
        default: return "Game\(usage)"
        }
    }

    private static func keyboardName(usage: Int) -> String
    {
        switch usage
        {
        case 0x04...0x1D: return "Key\(Character(UnicodeScalar(usage - 0x04 + 65)!))"
        case 0x1E...0x27:
            let num = (usage - 0x1E + 1) % 10
            return "Key\(num)"
        case 0x28: return "Return"
        case 0x29: return "Esc"
        case 0x2A: return "Backspace"
        case 0x2B: return "Tab"
        case 0x2C: return "Space"
        case 0x4F: return "Right"
        case 0x50: return "Left"
        case 0x51: return "Down"
        case 0x52: return "Up"
        default: return "Key\(usage)"
        }
    }

    private static func consumerName(usage: Int) -> String
    {
        switch usage
        {
        case 0xE0: return "Volume"
        case 0xE2: return "Mute"
        case 0xE9: return "Vol+"
        case 0xEA: return "Vol-"
        case 0xB0: return "Play"
        case 0xB1: return "Pause"
        case 0xB5: return "Next"
        case 0xB6: return "Prev"
        case 0xB7: return "Stop"
        case 0xCD: return "Play/Pause"
        default: return "Media\(usage)"
        }
    }

    private static func digitizerName(usage: Int) -> String
    {
        switch usage
        {
        case 0x30: return "Pressure"
        case 0x31: return "Barrel Pressure"
        case 0x32: return "InRange"
        case 0x33: return "Touch"
        case 0x42: return "Tip"
        case 0x44: return "Barrel"
        case 0x45: return "Eraser"
        case 0x46: return "Picker"
        case 0x47: return "TouchValid"
        case 0x48: return "Width"
        case 0x49: return "Height"
        default: return "Pen\(usage)"
        }
    }
}

// MARK: - HID Manager Wrapper

class HIDManager
{
    private var manager: IOHIDManager?
    private var connectedDevices: [String: IOHIDDevice] = [:]
    private var deviceInfoCache: [String: HIDDeviceInfo] = [:]

    var onDevicesChanged: (() -> Void)?
    var onValueChanged: ((String, HIDElementInfo, Int) -> Void)?

    init()
    {
        setupManager()
    }

    deinit
    {
        if let manager = manager
        {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    private func setupManager()
    {
        print("[HIDManager] Setting up HID manager...")

        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let manager = manager else
        {
            print("[HIDManager] ERROR: Failed to create IOHIDManager")
            return
        }

        print("[HIDManager] IOHIDManager created successfully")

        // Match all HID devices
        IOHIDManagerSetDeviceMatching(manager, nil)

        // Set up callbacks
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let this = Unmanaged<HIDManager>.fromOpaque(context).takeUnretainedValue()
            this.deviceConnected(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let this = Unmanaged<HIDManager>.fromOpaque(context).takeUnretainedValue()
            this.deviceDisconnected(device)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        if openResult == kIOReturnSuccess
        {
            print("[HIDManager] IOHIDManager opened successfully")
        }
        else
        {
            print("[HIDManager] ERROR: Failed to open IOHIDManager. Error code: \(openResult)")
            print("[HIDManager] This may indicate missing Input Monitoring permission.")
            print("[HIDManager] Go to System Settings → Privacy & Security → Input Monitoring and add this app.")
        }

        // Enumerate already-connected devices
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
        {
            print("[HIDManager] Found \(devices.count) already-connected HID devices")
            for device in devices
            {
                deviceConnected(device)
            }
        }
        else
        {
            print("[HIDManager] No devices found or failed to enumerate devices")
        }
    }

    private func deviceConnected(_ device: IOHIDDevice)
    {
        let info = getDeviceInfo(device)
        print("[HIDManager] Device connected: \(info.displayName) (VID:\(String(format: "%04X", info.vendorID)) PID:\(String(format: "%04X", info.productID)))")
        connectedDevices[info.id] = device
        deviceInfoCache[info.id] = info
        onDevicesChanged?()
    }

    private func deviceDisconnected(_ device: IOHIDDevice)
    {
        let info = getDeviceInfo(device)
        print("[HIDManager] Device disconnected: \(info.displayName)")
        connectedDevices.removeValue(forKey: info.id)
        deviceInfoCache.removeValue(forKey: info.id)
        onDevicesChanged?()
    }

    func getAvailableDevices() -> [HIDDeviceInfo]
    {
        return Array(deviceInfoCache.values).sorted { $0.displayName < $1.displayName }
    }

    func getDeviceInfo(_ device: IOHIDDevice) -> HIDDeviceInfo
    {
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let locationID = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
        let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        let manufacturer = IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String ?? ""

        let id = "\(vendorID):\(productID):\(locationID)"

        return HIDDeviceInfo(
            id: id,
            vendorID: vendorID,
            productID: productID,
            productName: productName,
            manufacturer: manufacturer
        )
    }

    func getElements(for deviceID: String) -> [HIDElementInfo]
    {
        guard let device = connectedDevices[deviceID] else { return [] }

        guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else
        {
            return []
        }

        var result: [HIDElementInfo] = []

        for element in elements
        {
            let type = IOHIDElementGetType(element)

            // Only include input elements
            guard type == kIOHIDElementTypeInput_Misc ||
                  type == kIOHIDElementTypeInput_Button ||
                  type == kIOHIDElementTypeInput_Axis else
            {
                continue
            }

            let cookie = Int(IOHIDElementGetCookie(element))
            let usagePage = Int(IOHIDElementGetUsagePage(element))
            let usage = Int(IOHIDElementGetUsage(element))
            let min = Int(IOHIDElementGetLogicalMin(element))
            let max = Int(IOHIDElementGetLogicalMax(element))
            let isRelative = IOHIDElementIsRelative(element)

            let displayName = HIDUsageNames.nameForUsage(page: usagePage, usage: usage)
            let id = "\(cookie)_\(usagePage)_\(usage)"

            let info = HIDElementInfo(
                id: id,
                cookie: cookie,
                usagePage: usagePage,
                usage: usage,
                displayName: displayName,
                min: min,
                max: max,
                isRelative: isRelative
            )

            result.append(info)
        }

        return result.sorted { $0.displayName < $1.displayName }
    }

    func startMonitoring(deviceID: String, elements: [HIDElementInfo])
    {
        guard let device = connectedDevices[deviceID] else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDDeviceRegisterInputValueCallback(device, { context, result, sender, value in
            guard let context = context else { return }
            let this = Unmanaged<HIDManager>.fromOpaque(context).takeUnretainedValue()
            this.handleInputValue(value)
        }, context)
    }

    func stopMonitoring(deviceID: String)
    {
        guard let device = connectedDevices[deviceID] else { return }
        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
    }

    private func handleInputValue(_ value: IOHIDValue)
    {
        let element = IOHIDValueGetElement(value)
        let cookie = Int(IOHIDElementGetCookie(element))
        let usagePage = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let intValue = Int(IOHIDValueGetIntegerValue(value))

        let min = Int(IOHIDElementGetLogicalMin(element))
        let max = Int(IOHIDElementGetLogicalMax(element))
        let isRelative = IOHIDElementIsRelative(element)
        let displayName = HIDUsageNames.nameForUsage(page: usagePage, usage: usage)
        let id = "\(cookie)_\(usagePage)_\(usage)"

        let info = HIDElementInfo(
            id: id,
            cookie: cookie,
            usagePage: usagePage,
            usage: usage,
            displayName: displayName,
            min: min,
            max: max,
            isRelative: isRelative
        )

        // Find which device this came from
        let device = IOHIDValueGetElement(value)
        let deviceRef = IOHIDElementGetDevice(device)

        for (deviceID, connectedDevice) in connectedDevices
        {
            if connectedDevice == deviceRef
            {
                onValueChanged?(deviceID, info, intValue)
                break
            }
        }
    }
}

// MARK: - Settings View

struct HIDNodeView: View
{
    @Bindable var node: HIDNode

    var body: some View
    {
        VStack(alignment: .leading, spacing: 8)
        {
            Text("HID Device Configuration")
                .font(.system(size: 10))
                .bold()

            HStack
            {
                Text("Device:")
                    .font(.system(size: 10))

                Picker("", selection: $node.selectedDeviceID)
                {
                    Text("None").tag(String?.none)

                    ForEach(node.availableDevices) { device in
                        Text(device.displayName).tag(Optional(device.id))
                    }
                }
                .pickerStyle(.menu)

                Button("Refresh")
                {
                    node.refreshDevices()
                }
                .controlSize(.small)
            }

            if let deviceID = node.selectedDeviceID,
               !node.deviceElements.isEmpty
            {
                Divider()

                Text("Device Elements (\(node.deviceElements.count)):")
                    .font(.system(size: 10))

                ScrollView
                {
                    VStack(alignment: .leading, spacing: 2)
                    {
                        ForEach(node.deviceElements) { element in
                            HStack
                            {
                                Text(element.displayName)
                                    .font(.system(size: 9))

                                Spacer()

                                Text(element.isButton ? "Button" : "Axis")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
            }

            Spacer()
        }
        .padding(4)
    }
}

// MARK: - HID Node

@Observable public class HIDNode: Node
{
    override public static var name: String { "HID Device" }
    override public static var nodeType: Node.NodeType { .Parameter(parameterType: .IO) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Read input from HID devices (gamepads, joysticks, etc.)" }

    // MARK: - Codable

    private enum HIDCodingKeys: String, CodingKey
    {
        case selectedDeviceID
        case selectedDeviceInfo
        case deviceElements
    }

    public required init(from decoder: any Decoder) throws
    {
        try super.init(from: decoder)

        let container = try decoder.container(keyedBy: HIDCodingKeys.self)

        self.selectedDeviceID = try container.decodeIfPresent(String.self, forKey: .selectedDeviceID)
        self.savedDeviceInfo = try container.decodeIfPresent(HIDDeviceInfo.self, forKey: .selectedDeviceInfo)
        self.deviceElements = try container.decodeIfPresent([HIDElementInfo].self, forKey: .deviceElements) ?? []

        // Rebuild ports based on restored elements
        self.rebuildPorts()
    }

    public override func encode(to encoder: Encoder) throws
    {
        try super.encode(to: encoder)

        var container = encoder.container(keyedBy: HIDCodingKeys.self)
        try container.encodeIfPresent(self.selectedDeviceID, forKey: .selectedDeviceID)

        // Save device info so we can try to reconnect later
        if let deviceID = selectedDeviceID,
           let deviceInfo = availableDevices.first(where: { $0.id == deviceID })
        {
            try container.encode(deviceInfo, forKey: .selectedDeviceInfo)
        }

        try container.encode(self.deviceElements, forKey: .deviceElements)
    }

    public required init(context: Context)
    {
        super.init(context: context)
    }

    // MARK: - Properties

    @ObservationIgnored private var hidManager: HIDManager?
    @ObservationIgnored private var savedDeviceInfo: HIDDeviceInfo?

    @ObservationIgnored fileprivate var selectedDeviceID: String?
    {
        didSet
        {
            if let oldValue = oldValue
            {
                hidManager?.stopMonitoring(deviceID: oldValue)
            }

            if let deviceID = selectedDeviceID
            {
                deviceElements = hidManager?.getElements(for: deviceID) ?? []
                rebuildPorts()
                hidManager?.startMonitoring(deviceID: deviceID, elements: deviceElements)
            }
            else
            {
                deviceElements = []
                rebuildPorts()
            }
        }
    }

    @ObservationIgnored fileprivate var availableDevices: [HIDDeviceInfo] = []
    @ObservationIgnored fileprivate var deviceElements: [HIDElementInfo] = []

    // Store latest values for each element
    @ObservationIgnored private var latestValues: [String: Int] = [:]

    // MARK: - Settings View

    override public func providesSettingsView() -> Bool
    {
        true
    }

    override public func settingsView() -> AnyView
    {
        AnyView(HIDNodeView(node: self))
    }

    override public var settingsSize: SettingsViewSize { .Medium }

    // MARK: - Lifecycle

    public override func enableExecution(context: GraphExecutionContext)
    {
        setupHIDManager()
    }

    public override func disableExecution(context: GraphExecutionContext)
    {
        if let deviceID = selectedDeviceID
        {
            hidManager?.stopMonitoring(deviceID: deviceID)
        }
        hidManager = nil
    }

    private func setupHIDManager()
    {
        hidManager = HIDManager()

        hidManager?.onDevicesChanged = { [weak self] in
            DispatchQueue.main.async
            {
                self?.refreshDevices()
            }
        }

        hidManager?.onValueChanged = { [weak self] deviceID, element, value in
            self?.handleValueChange(deviceID: deviceID, element: element, value: value)
        }

        refreshDevices()

        // Try to reconnect to previously selected device
        if let savedInfo = savedDeviceInfo
        {
            // Look for a device with matching vendor/product ID
            if let matchingDevice = availableDevices.first(where: {
                $0.vendorID == savedInfo.vendorID && $0.productID == savedInfo.productID
            })
            {
                selectedDeviceID = matchingDevice.id
            }
        }
    }

    fileprivate func refreshDevices()
    {
        availableDevices = hidManager?.getAvailableDevices() ?? []
    }

    private func handleValueChange(deviceID: String, element: HIDElementInfo, value: Int)
    {
        guard deviceID == selectedDeviceID else { return }

        latestValues[element.id] = value
        self.markDirty()
    }

    // MARK: - Execution

    public override func execute(context: GraphExecutionContext,
                                  renderPassDescriptor: MTLRenderPassDescriptor,
                                  commandBuffer: MTLCommandBuffer)
    {
        for element in deviceElements
        {
            guard let portName = portNameForElement(element),
                  let value = latestValues[element.id] else { continue }

            if element.isButton
            {
                if let port = self.findPort(named: portName) as? NodePort<Bool>
                {
                    port.send(value != 0)
                }
            }
            else
            {
                if let port = self.findPort(named: portName) as? NodePort<Float>
                {
                    // Normalize axis values to 0.0 - 1.0
                    let range = element.max - element.min
                    let normalized = range > 0 ? Float(value - element.min) / Float(range) : 0.0
                    port.send(normalized)
                }
            }
        }
    }

    // MARK: - Port Management

    // Cache for current port names mapping
    @ObservationIgnored private var currentPortNames: [String: String] = [:]

    private func rebuildPorts()
    {
        // Build unique port names, adding suffix only when needed for duplicates
        currentPortNames = buildUniquePortNames(for: deviceElements)

        let portNamesWeNeed = Set(currentPortNames.values)
        let existingPortNames = Set(self.outputPorts().map { $0.name })

        let portsNamesToRemove = existingPortNames.subtracting(portNamesWeNeed)

        // Remove ports that are no longer needed
        for portName in portsNamesToRemove
        {
            if let port = self.findPort(named: portName)
            {
                self.removePort(port)
            }
        }

        // Add ports for each element
        for element in deviceElements
        {
            guard let portName = currentPortNames[element.id] else { continue }

            if self.findPort(named: portName) != nil
            {
                continue // Port already exists
            }

            let port: Port
            if element.isButton
            {
                port = NodePort<Bool>(name: portName, kind: .Outlet, description: "HID button state (true when pressed)")
            }
            else
            {
                port = NodePort<Float>(name: portName, kind: .Outlet, description: "HID axis value normalized from 0 to 1")
            }

            self.addDynamicPort(port)
            print("Added HID port: \(portName)")
        }
    }

    /// Build unique port names, only adding numeric suffix when there are duplicates
    private func buildUniquePortNames(for elements: [HIDElementInfo]) -> [String: String]
    {
        var result: [String: String] = [:]

        // First pass: count base names
        var baseCounts: [String: Int] = [:]
        for element in elements
        {
            let baseName = sanitizeName(element.displayName)
            baseCounts[baseName, default: 0] += 1
        }

        // Second pass: assign unique names
        var usedCounts: [String: Int] = [:]
        for element in elements
        {
            let baseName = sanitizeName(element.displayName)

            if baseCounts[baseName] == 1
            {
                // Unique name, no suffix needed
                result[element.id] = baseName
            }
            else
            {
                // Duplicate name, add numeric suffix
                let index = usedCounts[baseName, default: 0] + 1
                usedCounts[baseName] = index
                result[element.id] = "\(baseName)\(index)"
            }
        }

        return result
    }

    private func sanitizeName(_ name: String) -> String
    {
        var result = name
        result = result.replacingOccurrences(of: " ", with: "")
        result = result.replacingOccurrences(of: "/", with: "")
        result = result.replacingOccurrences(of: "-", with: "")
        return result
    }

    /// Get port name for an element using the cached mapping
    private func portNameForElement(_ element: HIDElementInfo) -> String?
    {
        return currentPortNames[element.id]
    }
}
