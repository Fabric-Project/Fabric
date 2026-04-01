//
//  DirectoryScannerNode.swift
//  Fabric
//

import Foundation
import Satin
import Metal

public class DirectoryScannerNode: Node {
    override public class var name: String { "Directory Scanner" }
    override public class var nodeType: Node.NodeType { .Parameter(parameterType: .String) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Scan a directory and output file paths as an Array of Strings" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports + [
            ("inputPath", ParameterPort(parameter: StringParameter("Directory", "", .filepicker, "Path to the directory to scan"))),
            ("inputExtension", ParameterPort(parameter: StringParameter("Extension", "", .inputfield, "File extension filter (e.g. png), leave empty for all files"))),
            ("inputRescan", NodePort<Bool>(name: "Rescan", kind: .Inlet, description: "Signal to rescan the directory")),
            ("outputPaths", NodePort<ContiguousArray<String>>(name: "Paths", kind: .Outlet, description: "Array of file paths found in the directory")),
            ("outputCount", NodePort<Int>(name: "Count", kind: .Outlet, description: "Number of files found")),
        ]
    }

    // Port proxies
    public var inputPath: ParameterPort<String> { port(named: "inputPath") }
    public var inputExtension: ParameterPort<String> { port(named: "inputExtension") }
    public var inputRescan: NodePort<Bool> { port(named: "inputRescan") }
    public var outputPaths: NodePort<ContiguousArray<String>> { port(named: "outputPaths") }
    public var outputCount: NodePort<Int> { port(named: "outputCount") }

    @ObservationIgnored private var lastRescan: Bool = false

    public override func execute(context: GraphExecutionContext,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer) {
        let rescanTriggered: Bool
        if let rescan = inputRescan.value, inputRescan.valueDidChange {
            rescanTriggered = rescan && !lastRescan
            lastRescan = rescan
        } else {
            rescanTriggered = false
        }

        if inputPath.valueDidChange || inputExtension.valueDidChange || rescanTriggered,
           let path = inputPath.value,
           !path.isEmpty {
            scanDirectory(path: path)
        }
    }

    private func scanDirectory(path: String) {
        guard let url = URL(string: path) else { return }
        let dirPath = url.standardizedFileURL.path(percentEncoded: false)
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dirPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }

        guard let contents = try? fileManager.contentsOfDirectory(atPath: dirPath) else {
            return
        }

        let ext = inputExtension.value ?? ""
        let paths: [String]

        if ext.isEmpty {
            paths = contents.map { url.appendingPathComponent($0).path }
        } else {
            paths = contents
                .filter { ($0 as NSString).pathExtension.caseInsensitiveCompare(ext) == .orderedSame }
                .map { url.appendingPathComponent($0).path }
        }

        outputPaths.send(ContiguousArray<String>(paths.sorted()))
        outputCount.send(paths.count)
    }
}
