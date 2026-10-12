import SpriteKit

/// Removes only child layers owned by LunaBookSpriteMotion. Shared action keys
/// are cancelled only when one of those owned nodes proves this body had a book
/// presentation, protecting unrelated character motion on a normal body.
@MainActor enum LunaBookPresentationCleanupR004 {
    private static let actionKeys = ["party_walk_clip", "party_rest_clip", "party_cast_clip"]

    @discardableResult
    static func clearOwnedPresentation(on body: SKSpriteNode) -> Bool {
        let book = body.childNode(withName: "luna_book")
        let palm = body.childNode(withName: "luna_book_palm")
        guard book != nil || palm != nil else { return false }
        book?.removeFromParent()
        palm?.removeFromParent()
        for key in actionKeys { body.removeAction(forKey: key) }
        return true
    }
}
