import Foundation

/// Isolated fallback policy for the LUNA equipped-book walk path.
enum LunaBookWalkFallbackR009 {
    static func handAfterAttempt(loaded: Bool, previous: CGPoint?) -> CGPoint? {
        loaded ? previous : nil
    }

    static func play(bookAttempt: () -> Bool, bodyFallback: () -> Bool) -> Bool {
        guard !bookAttempt() else { return true }
        return bodyFallback()
    }
}
