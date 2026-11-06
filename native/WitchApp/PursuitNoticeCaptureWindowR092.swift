import Foundation

/// Small lifecycle contract shared by the opt-in render observer and host tests.
/// Scene rebuilds before the first installed notice are preparation; after a cue,
/// generation changes invalidate the capture. Normal battle cleanup closes it.
struct PursuitNoticeCaptureWindowR092 {
    private(set) var firstCueGeneration: Int?
    private(set) var cueRoots: Set<String> = []
    private(set) var removalFrameByRoot: [String: Int] = [:]
    private(set) var lastPostRemovalSampleFrame: Int?
    private(set) var preCueGenerationChanges = 0
    private(set) var status = "WAITING_FOR_FIRST_NOTICE_CUE"
    private(set) var generationMismatch: [String: Int]?
    private var finishRequested = false
    private var battleEndFrame: Int?
    private var lastPreCueGeneration: Int?

    var receipt: [String: Any] {
        [
            "status": status,
            "firstCueGeneration": firstCueGeneration as Any? ?? NSNull(),
            "preCueGenerationChanges": preCueGenerationChanges,
            "cueRootIDs": cueRoots.sorted(),
            "removalRootIDs": removalFrameByRoot.keys.sorted(),
            "lastPostRemovalSampleFrame": lastPostRemovalSampleFrame as Any? ?? NSNull(),
            "postRemovalFrameObserved": lastPostRemovalSampleFrame != nil,
            "generationMismatch": generationMismatch as Any? ?? NSNull(),
            "finishRequested": finishRequested,
            "battleEndSceneFrame": battleEndFrame as Any? ?? NSNull()
        ]
    }

    mutating func recordInstall(rootID: String, generation: Int) {
        guard !isTerminal else { return }
        if firstCueGeneration == nil {
            firstCueGeneration = generation
            status = "TRACKING_NOTICE_CUES"
        } else if firstCueGeneration != generation {
            markGenerationMismatch(generation)
        }
        cueRoots.insert(rootID)
    }

    mutating func recordRemoval(rootID: String, sceneFrame: Int) {
        guard !isTerminal, cueRoots.contains(rootID) else { return }
        removalFrameByRoot[rootID] = max(removalFrameByRoot[rootID] ?? Int.min, sceneFrame)
    }

    mutating func observe(sceneFrame: Int, generation: Int, activeRootIDs: Set<String>) {
        guard !isTerminal else { return }
        guard let firstCueGeneration else {
            if let lastPreCueGeneration, lastPreCueGeneration != generation {
                preCueGenerationChanges += 1
            }
            lastPreCueGeneration = generation
            return
        }
        guard generation == firstCueGeneration else {
            markGenerationMismatch(generation)
            return
        }
        guard activeRootIDs.isEmpty,
              removalFrameByRoot.count == cueRoots.count,
              let latestRemoval = removalFrameByRoot.values.max(),
              sceneFrame > latestRemoval else { return }
        lastPostRemovalSampleFrame = sceneFrame
        if finishRequested { status = "CAPTURED_BATTLE_END_PENDING_VISUAL_REVIEW" }
    }

    mutating func requestBattleEnd(sceneFrame: Int, generation: Int, activeRootIDs: Set<String>) {
        guard !isTerminal else { return }
        guard let firstCueGeneration else {
            status = "NO_NOTICE_CUE_CAPTURED"
            return
        }
        guard generation == firstCueGeneration else {
            markGenerationMismatch(generation)
            return
        }
        finishRequested = true
        battleEndFrame = sceneFrame
        guard activeRootIDs.isEmpty else {
            status = "INCOMPLETE_NOTICE_ACTIVE_AT_BATTLE_END"
            return
        }
        guard removalFrameByRoot.count == cueRoots.count else {
            status = "INCOMPLETE_NOTICE_REMOVAL_MISSING_AT_BATTLE_END"
            return
        }
        guard let lastPostRemovalSampleFrame,
              lastPostRemovalSampleFrame > (removalFrameByRoot.values.max() ?? Int.max) else {
            status = "INCOMPLETE_POST_REMOVAL_RENDER_NOT_OBSERVED"
            return
        }
        status = "CAPTURED_BATTLE_END_PENDING_VISUAL_REVIEW"
    }

    private var isTerminal: Bool {
        status.hasPrefix("CAPTURED_") || status.hasPrefix("INCOMPLETE_") || status == "NO_NOTICE_CUE_CAPTURED"
    }

    private mutating func markGenerationMismatch(_ generation: Int) {
        guard let firstCueGeneration else { return }
        generationMismatch = ["firstCueGeneration": firstCueGeneration, "observedGeneration": generation]
        status = "INCOMPLETE_SCENE_GENERATION_CHANGED_AFTER_FIRST_CUE"
    }
}
