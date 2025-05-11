//
//  NodeOutlet.swift
//  v
//
//  Created by Anton Marini on 5/20/24.
//

import SwiftUI

struct NodeOutletView: View
{
    let port: (any NodePortProtocol)

    var body: some View 
    {
        Circle()
            .fill(port.color)
            .frame(width: 15)
            .draggable<OutletData>(
                
                OutletData(portID: self.port.id)
                            
            )
            .help( "\(port.name): \(port.valueType())")
            .anchorPreference(
                key: PortAnchorKey.self,
                value: .center,
                transform: {  anchor in
                   
                    [  port.id : anchor ]
                })
    }
}
