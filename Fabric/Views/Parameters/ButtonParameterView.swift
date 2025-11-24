//
//  ButtonParameterView.swift
//  Fabric
//
//  Created by Anton Marini on 5/24/25.
//

import SwiftUI
import Satin
import Combine

struct ButtonParameterView: View, Equatable {
 
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.vm === rhs.vm }

    @Bindable var vm: ParameterObservableModel<Bool>
    
    init(param: BoolParameter)
    {
        self.vm = ParameterObservableModel(label: param.label,
                                           get: { param.value },
                                           set: { param.value = $0 },
                                           publisher:param.valuePublisher )
    }
    
    var body: some View
    {
        HStack(spacing: ParameterConfig.horizontalStackSpacing)
        {
            InputFieldLabelView(label: self.vm.label)

            Toggle("", isOn: $vm.uiValue)
                .labelsHidden()
                .toggleStyle(.switch)
                .frame(width: ParameterConfig.paramWidth, alignment: .leading)
        }
    }
}
//#Preview {
//    ButtonParameterView()
//}
