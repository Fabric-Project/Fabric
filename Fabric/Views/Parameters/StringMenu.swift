//
//  StringMenu.swift
//  v
//
//  Created by Anton Marini on 6/21/24.
//


import SwiftUI

struct StringMenu: View
{
    @Binding var value:String
    var options:[String]

    @State var valueName:String

    var body: some View
    {
        Menu {
            ForEach(self.options.sorted(), id: \.self) { option in
                Button {
                    self.value = option
                    print("Selected Option \(option)")
                } label: {
                    Text(option)
                }
                Divider()
            }
        } label: {
            Text(self.$value.wrappedValue)
        }
        .menuStyle(.button)

    }

}
