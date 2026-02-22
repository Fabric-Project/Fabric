import Foundation
import Fabric

@MainActor
final class EditorDocumentStore {
    static let shared = EditorDocumentStore()

    private(set) weak var focusedDocument: FabricDocument?
    private var documentsByGraphID: [UUID: FabricDocument] = [:]

    private init() {}

    func setFocusedDocument(_ document: FabricDocument) {
        self.focusedDocument = document
        self.documentsByGraphID[document.graph.id] = document
    }

    func clearFocusedDocumentIfMatching(_ document: FabricDocument) {
        guard self.focusedDocument === document else { return }
        self.focusedDocument = nil
    }

    func createNewDocument() -> FabricDocument {
        let document = FabricDocument()
        self.documentsByGraphID[document.graph.id] = document
        self.focusedDocument = document
        return document
    }

    func graph(for graphID: UUID) -> Graph? {
        if let focusedDocument, focusedDocument.graph.id == graphID {
            return focusedDocument.graph.activeSubGraph ?? focusedDocument.graph
        }

        guard let document = self.documentsByGraphID[graphID] else {
            return nil
        }

        return document.graph.activeSubGraph ?? document.graph
    }
}
