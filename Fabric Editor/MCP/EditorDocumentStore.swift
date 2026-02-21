import Foundation

@MainActor
final class EditorDocumentStore {
    static let shared = EditorDocumentStore()

    private(set) weak var focusedDocument: FabricDocument?

    private init() {}

    func setFocusedDocument(_ document: FabricDocument) {
        self.focusedDocument = document
    }

    func clearFocusedDocumentIfMatching(_ document: FabricDocument) {
        guard self.focusedDocument === document else { return }
        self.focusedDocument = nil
    }
}
