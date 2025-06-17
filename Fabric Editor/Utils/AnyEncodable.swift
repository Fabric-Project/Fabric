//
//  AnyEncodable.swift
//  v
//
//  Created by Anton Marini on 2/9/25.
//

// https://stackoverflow.com/questions/78277809/encode-an-array-of-items-conforming-to-an-encodable-protocol
// https://martiancraft.com/blog/2020/03/going-deep-with-decodable/

import Foundation
import AnyCodable
import Satin

// Custom Read Write content in our UserInfo we leverage
class DecoderContext
{
    static let decoderContextKey = CodingUserInfoKey(rawValue: "decoderCntextKey")!
    
    let documentContext:Context
    
    var currentGraph:Graph?
    var currentGraphNodes:[Node]?
    
    init(documentContext: Context, currentGraph: Graph? = nil, currentGraphNodes: [Node]? = nil) {
        self.documentContext = documentContext
        self.currentGraph = currentGraph
        self.currentGraphNodes = currentGraphNodes
    }
}

extension JSONDecoder
{
    var context: DecoderContext? {
        get { return userInfo[DecoderContext.decoderContextKey] as? DecoderContext }
        set { userInfo[DecoderContext.decoderContextKey] = newValue }
     }
}

extension Decoder {
    var context: DecoderContext? {
        return userInfo[DecoderContext.decoderContextKey] as? DecoderContext
    }
}

struct AnyCodableMap : Codable
{
    let type: String
    let value: AnyCodable
    
    enum CodingKeys : String, CodingKey
    {
        case type
        case value
    }
}

//struct AnyEncodable: Encodable {
//    
//    let item: any Encodable
//    
//    func encode(to encoder: any Encoder) throws
//    {
//        var container = encoder.singleValueContainer()
//        try container.encode(self.item)
//    }
//}






