//
//  FileGridView.swift
//  v
//
//  Created by Anton Marini on 7/13/24.
//


import SwiftUI
import Satin
import UniformTypeIdentifiers

struct FileImportParameterView: View, Equatable
{
    static func == (lhs: FileImportParameterView, rhs: FileImportParameterView) -> Bool {
        return lhs.stringParameter.id == rhs.stringParameter.id
    }
    
    @Bindable var stringParameter:StringParameter

    let allowedContentTypes:[UTType] = [.image, .jpeg, .tiff, .heic, .heif, .png,]
    
    @State private var isImporting: Bool = false
    @State private var selectedOption: String? = nil

    var columns:[GridItem] = [ GridItem(.flexible(minimum: 50, maximum: 250), spacing: 3),
//                               GridItem(.flexible(minimum: 50, maximum: 250), spacing: 3),
                               GridItem(.flexible(minimum: 50, maximum: 250), spacing: 3)]
    
    var body: some View
    {
        VStack {
            
            Menu(self.selectedOption ?? "No File Selected")
            {
                ForEach(self.stringParameter.options, id:\.self) { option in
                    Button(option, action: {
                        selectedOption = option
                        self.stringParameter.value = option
                    })
                }
            }
            
            Button(action: {
                isImporting = true
            }, label: {
                Text("Load Videos")
            })
            .fileImporter(isPresented: $isImporting,
                          allowedContentTypes: self.allowedContentTypes,
                          allowsMultipleSelection: false,
                          onCompletion: { result in
                
                switch result {
                case .success(let urls):
                    self.stringParameter.options = urls.map( { $0.standardizedFileURL.absoluteString } )
//                    self.thumbnailModels = urls.map({ FileAndThumbnailModel(fileURL: $0, selected: false) } )
                case .failure(let error):
                    print(error)
                }
            })
        }
    }
    
//    private func createImageThumbsFromURL(urls:[URL])
//    {
//        ThumbnailGenerator.shared.generateThumbnails(for: urls,
//                                                     size: CGSize(width: 100, height: 60)) { urlImageDict in
//            self.fileThumbModels = urlImageDict.map( {
//                let selected = ($0.key.standardizedFileURL.absoluteString == self.currentURL?.standardizedFileURL.absoluteString)
//                return FileAndThumbnailModel(fileURL: $0.key, thumbnail: $0.value, selected:selected )
//            } )
//        }
//    }
}
