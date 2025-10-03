//
//  ArrayHelperExtensions.swift
//  Fabric
//
//  Created by Anton Marini on 9/19/25.
//

import Foundation
import simd

public protocol FabricDescription
{
    static var fabricDescription: String { get }
}

extension SIMD4<Float> : FabricDescription
{
    public static var fabricDescription: String {
        return "Vector 4"
    }
}

extension SIMD3<Float> : FabricDescription
{
     public static var fabricDescription: String {
        return "Vector 3"
    }
}

extension SIMD2<Float> : FabricDescription
{
     public static var fabricDescription: String {
        return "Vector 2"
    }
}

extension Float : FabricDescription
{
     public static var fabricDescription: String {
        return "Number"
    }
}

extension Bool : FabricDescription
{
    public  static var fabricDescription: String {
        return "Boolean"
    }
}

extension Int : FabricDescription
{
    public static var fabricDescription: String {
        return "Index"
    }
}

extension String : FabricDescription
{
    public static var fabricDescription: String {
        return "String"
    }    
}
