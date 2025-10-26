//
//  NodeOutlet.swift
//  v
//
//  Created by Anton Marini on 5/20/24.
//

import SwiftUI

struct NodeOutletView: View
{
    let port: Port

    var body: some View 
    {
        HStack
        {
            Text(self.port.name)
                .foregroundStyle(Color.secondary)
                .font(.system(size: 9))
                .lineLimit(1)
            
            Circle()
                .fill(port.color)
                .frame(width: 15)
            //            .help( "\(port.name): \(port.valueType())")
                .anchorPreference(
                    key: PortAnchorKey.self,
                    value: .center,
                    transform: {  anchor in
                        
                        [  port.id : anchor ]
                    })
                .draggable(
                    
                    OutletData(portID: self.port.id)
                    
                )
        }
        .frame(height: 15)

//            .contextMenu {
//                
//                Toggle("Publish Port", isOn: Binding<Bool>.init(get: { return self.port.isPublished() },
//                                                                set: { val in
//                    self.port.setPublished(val)
//                }))
//            }
    }
}
