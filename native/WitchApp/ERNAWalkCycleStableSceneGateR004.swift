import Foundation

/// Small pure gate used only by the isolated ERNA walk observer. It starts
/// observation after the SpriteKit view and viewport have stayed stable for
/// consecutive rendered callbacks; a rebuild or resize restarts the count.
struct ERNAWalkCycleStableSceneGateR004 {
    let requiredRenderedFrames: Int
    private(set) var lastGeneration: Int?
    private(set) var lastWidth: CGFloat?
    private(set) var lastHeight: CGFloat?
    private(set) var stableRenderedFrames = 0

    init(requiredRenderedFrames: Int = 4) {
        self.requiredRenderedFrames = max(1, requiredRenderedFrames)
    }

    mutating func observe(viewAttached: Bool, size: CGSize, generation: Int) -> Bool {
        guard viewAttached, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else {
            lastGeneration = nil
            lastWidth = nil
            lastHeight = nil
            stableRenderedFrames = 0
            return false
        }
        if lastGeneration == generation, lastWidth == size.width, lastHeight == size.height {
            stableRenderedFrames += 1
        } else {
            lastGeneration = generation
            lastWidth = size.width
            lastHeight = size.height
            stableRenderedFrames = 1
        }
        return stableRenderedFrames >= requiredRenderedFrames
    }
}
