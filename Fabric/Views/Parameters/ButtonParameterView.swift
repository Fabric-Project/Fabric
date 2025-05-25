//
//  ButtonParameterView.swift
//  Fabric
//
//  Created by Anton Marini on 5/24/25.
//

import SwiftUI
import Satin

struct ButtonParameterView: View, Equatable {
 
    static func == (lhs: ButtonParameterView, rhs: ButtonParameterView) -> Bool
    {
        return lhs.parameter.id == lhs.parameter.id
        && lhs.parameter.value == rhs.parameter.value
    }
    
    @Bindable var parameter:BoolParameter

    init(param:BoolParameter)
    {
        self.parameter = param
    }
    
    var body: some View
    {
        Toggle(self.parameter.label, isOn: self.$parameter.value)
            .controlSize( .mini )
    }
}
//#Preview {
//    ButtonParameterView()
//}
