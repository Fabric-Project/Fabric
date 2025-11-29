//
//  HDRTextureNode.swift
//  Fabric
//
//  Created by Anton Marini on 4/27/25.
//

import Foundation
import Satin
import simd
import Metal
import MetalKit

public class LUTProcessorNode : BaseEffectNode
{
    public override class var name:String { "Color LUT Correction" }
    public override class var nodeType:Node.NodeType { Node.NodeType.Image(imageType: .ColorAdjust) }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Processor }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Load an image LUT from disk, processing an Image"}
    
    // Auto load our LUT shader
    class override var sourceShaderName:String { "LUTShader" }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)
        
        return ports +
        [
            ("inputFilePathParam", ParameterPort(parameter: StringParameter("File Path", "", .filepicker))),
        ]
    }

    public var inputFilePathParam:ParameterPort<String>  { port(named: "inputFilePathParam") }

    @ObservationIgnored private var texture: (any MTLTexture)? = nil
    @ObservationIgnored private var url: URL? = nil
    
    public required init(context:Context, fileURL:URL? = nil)
    {
        super.init(context: context)
          
        self.loadLUTFromInputValue()
    }
    
    public required init(context:Context)
    {
        super.init(context: context)
          
        self.loadLUTFromInputValue()
    }
    
    public required init(from decoder: any Decoder) throws
    {
        guard let decodeContext = decoder.context else
        {
            fatalError("Required Decode Context Not set")
        }
        
        try super.init(from:decoder)
        
        self.loadLUTFromInputValue()
    }
    
    override public func execute(context:GraphExecutionContext,
                           renderPassDescriptor: MTLRenderPassDescriptor,
                           commandBuffer: MTLCommandBuffer)
    {
        if self.inputFilePathParam.valueDidChange
        {
            self.loadLUTFromInputValue()
        }

        if self.inputTexturePort.valueDidChange
        {
            if let inTex = self.inputTexturePort.value?.texture,
               let inTex2 = self.texture
            {
                self.postMaterial.set(inTex, index: FragmentTextureIndex.Custom0)
                self.postMaterial.set(inTex2, index: FragmentTextureIndex.Custom1)
                
                self.postProcessor.renderer.size.width = Float(inTex.width)
                self.postProcessor.renderer.size.height = Float(inTex.height)
                
                self.postProcessor.draw(renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer)
                
                if let outTex = self.postProcessor.renderer.colorTexture
                {
                    let outputTexture = EquatableTexture(texture: outTex)
                    self.outputTexturePort.send( outputTexture )
                }
            }
            else
            {
                self.outputTexturePort.send( nil )
            }
        }
        
     }
    
    private func loadLUTFromInputValue()
    {
        if let path = self.inputFilePathParam.value,
           path.isEmpty == false && self.url != URL(string: path)
        {
            self.url = URL(string: path)
            
            if FileManager.default.fileExists(atPath: self.url!.standardizedFileURL.path(percentEncoded: false) )
            {
                self.texture = Self.loadLUT(url: self.url!, device: self.context.device)
            }
        }
        else
        {
            self.texture = nil
        }
    }

    static func loadCubeLUT(fileURL: URL) throws -> ([Float], Int)
    {
        // Load the contents of the .cube file
        let fileContents = try String(contentsOf: fileURL, encoding: .utf8)
        
        var lutData = [Float]()  // To store the flattened RGB values
        var lutSize = 0          // To store the LUT size (e.g., 16 for 16x16x16 LUT)
        
        // Iterate through each line in the file
        for line in fileContents.components(separatedBy: .newlines)
        {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip comments or empty lines
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#")
            {
                continue
            }
            
            // Check for the LUT size definition
            if trimmedLine.hasPrefix("LUT_3D_SIZE")
            {
                let components = trimmedLine.components(separatedBy: " ")
                if let size = components.last.flatMap({ Int($0) })
                {
                    lutSize = size
                }
                continue
            }
            
            // Parse RGB float values for the LUT data
            let components = trimmedLine.components(separatedBy: " ")
            if components.count == 3
            {
                if let r = Float(components[0]),
                   let g = Float(components[1]),
                   let b = Float(components[2])
                {
                    // Add the RGB values to the LUT data
                    lutData.append(contentsOf: [r, g, b, 1.0]) // Append alpha 1.0 as well
                }
            }
        }
        
        // Validate that we have the correct number of entries
        let expectedEntries = lutSize * lutSize * lutSize
        if lutData.count != expectedEntries * 4
        { // 4 floats per entry (RGBA)
            throw NSError(domain: "CubeLUTLoader", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid LUT data size: expected \(expectedEntries), got \(lutData.count / 4)"
            ])
        }
        
        return (lutData, lutSize)
    }

    static func create3DLUTTexture(device: MTLDevice, lutData: [Float], lutSize: Int) -> MTLTexture?
    {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba32Float // Each LUT entry has an RGBA value
        descriptor.width = lutSize
        descriptor.height = lutSize
        descriptor.depth = lutSize
        descriptor.usage = .shaderRead

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        // Assume lutData contains the 3D LUT in flattened RGBA format
        let bytesPerPixel = 4 * MemoryLayout<Float>.size
        let bytesPerRow = lutSize * bytesPerPixel
        let bytesPerImage = bytesPerRow * lutSize

        texture.replace(region: MTLRegionMake3D(0, 0, 0, lutSize, lutSize, lutSize),
                        mipmapLevel: 0,
                        slice: 0,
                        withBytes: lutData,
                        bytesPerRow: bytesPerRow,
                        bytesPerImage: bytesPerImage)
        
        return texture
    }

   
    static func loadLUT(url:URL, device:MTLDevice) -> MTLTexture?
    {
        do
        {
            let (lutData, lutSize) = try Self.loadCubeLUT(fileURL: url)
            return Self.create3DLUTTexture(device: device, lutData: lutData, lutSize: lutSize)
        }
        catch
        {
            print("Unable to load LUT:\(url.lastPathComponent) \(error.localizedDescription)")
        }
        
        return nil
    }
}
