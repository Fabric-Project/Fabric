//
//  InputFieldView.swift
//  v
//
//  Created by Anton Marini on 4/9/25.
//

import SwiftUI
import Satin

struct InputFieldView: View {
 
    @ObservedObject var parameter:StringParameter

    init(param:StringParameter)
    {
        self.parameter = param
    }
    
    var body: some View
    {
        TextField(parameter.label, text: $parameter.value)
            .font(.system(size: 10))
            .textFieldStyle(.roundedBorder)
            .lineLimit(1)
            .padding()
        
    }

}
