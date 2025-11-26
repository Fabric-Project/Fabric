//
//  StringMenu.swift
//  v
//
//  Created by Anton Marini on 6/21/24.
//


import SwiftUI

struct StringMenu: View
{
//    @Binding var value:String
//    var options:[String]

    @Bindable var vm: ParameterObservableModel<String>
    @Bindable var optionsVm: ParameterObservableModel<[String]>

    @State private var selectedOption: String? = nil

    init(parameter: StringParameter)
    {
        self.vm = ParameterObservableModel(label: parameter.label,
                                           get: { parameter.value },
                                           set: { parameter.value = $0 },
                                           publisher: parameter.valuePublisher )
        
        self.optionsVm = ParameterObservableModel(label: parameter.label,
                                           get: { parameter.options },
                                           set: { parameter.options = $0 },
                                           publisher: parameter.optionsPublisher )
    }
    
    var body: some View
    {
        HStack(spacing: ParameterConfig.horizontalStackSpacing)
        {
            InputFieldLabelView(label: self.vm.label)

            Menu
            {
                ForEach(self.optionsVm.uiValue, id: \.self) { option in
                    Button {
                        selectedOption = option
                        vm.uiValue = option
                        print("Selected Option \(option)")
                    } label: {
                        Text(option)
                    }
                    Divider()
                }
            } label: {
                Text( vm.uiValue )
            }
            .menuStyle(.borderedButton)
            .frame(width:ParameterConfig.paramWidth)

        }
    }

}
