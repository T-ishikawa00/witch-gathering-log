import Foundation

/// Player-facing copy for the isolated R059 recipient-identification candidate.
/// Reuses the four current GameModel.actorNames labels. This does not change
/// their provisional creative-approval status. Unknown IDs stay out of player copy.
enum PursuitNoticeCopyR059 {
    static let panelWidth: Double = 44
    static let fontSize: Double = 8.5
    static let horizontalInset: Double = 4

    static let title = "追撃"

    static func recipientName(targetID: String) -> String {
        switch targetID {
        case "AIRA", "C_SMITH": return "アイラ"
        case "ERNA", "C_WITCH": return "エルナ"
        case "LUNA", "C_APPRENTICE": return "ルナ"
        case "NOIR", "C_FAMILIAR": return "ノワール"
        default: return "対象"
        }
    }

    /// Conservative monospaced CJK estimate used by the host test. The native
    /// scene still requires a visual review because the chosen font is not fixed
    /// width and SpriteKit's rendered metrics are authoritative.
    static func estimatedWidth(targetID: String) -> Double {
        Double(max(title.count, recipientName(targetID: targetID).count)) * fontSize
    }

    static func fitsPanel(targetID: String) -> Bool {
        estimatedWidth(targetID: targetID) + horizontalInset * 2 <= panelWidth
    }
}
