//
//  InputFieldView.swift
//  v
//
//  Created by Anton Marini on 4/9/25.
//

import SwiftUI
import Satin

struct InputFieldView: View {
 
    @Bindable var parameter:StringParameter

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

struct FloatInputFieldView: View {
 
    @Bindable var parameter:GenericParameter<Float>

    let decimalFormatter: NumberFormatter = {
          let formatter = NumberFormatter()
          formatter.numberStyle = .decimal
          formatter.maximumFractionDigits = 3
          return formatter
      }()
    
    init(param:GenericParameter<Float>)
    {
        self.parameter = param
    }
    
    var body: some View
    {
        TextField(parameter.label, value: $parameter.value, formatter:decimalFormatter)
            .font(.system(size: 10))
            .textFieldStyle(.roundedBorder)
            .lineLimit(1)
            .padding()
        
    }
}
