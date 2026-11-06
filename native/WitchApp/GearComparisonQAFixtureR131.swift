import Foundation

/// Explicit test-only setup for R131 UI coverage. These items and gate state are
/// synthetic and must never be described as earned progression.
enum GearComparisonQAFixtureR131 {
    static let flag = "--qa-r131-gear-comparison"
    static let unlockedFixture = "gear-comparison-r131-unlocked"
    static let lockedFixture = "gear-comparison-r131-locked"
    static let actorID = "C_WITCH"
    static let baselineGearIDString = "10000000-0000-4000-8000-000000000001"
    static let firstChoiceIDString = "13100000-0000-4000-8000-000000000001"
    static let secondChoiceIDString = "13100000-0000-4000-8000-000000000002"

    struct Request {
        let fixture: String
        let saveKey: String
        let contentSize: String?

        func comparisonIDs() throws -> [UUID] {
            try [GearComparisonQAFixtureR131.firstChoiceIDString,
                 GearComparisonQAFixtureR131.secondChoiceIDString].map(GearComparisonQAFixtureR131.uuid)
        }
        var actorID: String { GearComparisonQAFixtureR131.actorID }

        func makeInitialSnapshot(runtime: GameRuntimeConfigurationR098) throws -> GameSnapshot {
            var state = try runtime.makeNewSnapshot()
            let baselineID = try GearComparisonQAFixtureR131.uuid(GearComparisonQAFixtureR131.baselineGearIDString)
            guard let baseline = state.gear.first(where: { $0.id == baselineID }),
                  baseline.definitionID == "EQ_W_01",
                  state.equippedGearIDs[actorID + "|weapon"] == baseline.id else {
                throw CoreError.invalidCommand("R131 fixture needs the protected starter weapon as the third, equipped item")
            }
            let joinedActors = Set(state.partyActorIDs)
            for (id, definitionID) in [
                (try GearComparisonQAFixtureR131.uuid(GearComparisonQAFixtureR131.firstChoiceIDString), "EQ_W_P1"),
                (try GearComparisonQAFixtureR131.uuid(GearComparisonQAFixtureR131.secondChoiceIDString), "EQ_W_G1")
            ] {
                guard !state.gear.contains(where: { $0.id == id }),
                      let definition = runtime.catalog.gear.first(where: { $0.id == definitionID }),
                      definition.slot == "weapon",
                      definition.actorIDs.isEmpty || definition.actorIDs.contains(actorID) else {
                    throw CoreError.invalidCommand("R131 fixture catalog no longer has the expected distinct same-slot items")
                }
                let slots = try runtime.latentPolicy.generateNewInstanceSlots(
                    templateID: definitionID,
                    joinedActorIDs: joinedActors,
                    operationID: id,
                    domainSalt: "R131-SYNTHETIC-UI-FIXTURE-\(saveKey)-\(definitionID)")
                state.gear.append(GearInstance(id: id, definitionID: definitionID,
                    ownerID: nil, protected: true, candidateLatentSlots: slots, qualityID: "Q0"))
            }
            // Avoid a startup offline claim. The test performs no combat, gathering,
            // summon, craft, or reward command after fixture persistence.
            state.lastClaimAt = Date()
            if fixture == GearComparisonQAFixtureR131.unlockedFixture {
                // Synthetic unlock marker only; not earned campaign evidence.
                state.completedEncounterIDs.insert("B_R05_B")
            }
            return state
        }
    }

    static func request(arguments: [String], isolated: Bool, fixture: String?, saveKey: String?) throws -> Request? {
        let fixtureNames = [unlockedFixture, lockedFixture]
        let mentionsR131 = arguments.contains(flag) || fixtureNames.contains(fixture ?? "")
        guard mentionsR131 else { return nil }
        guard isolated,
              arguments.filter({ $0 == flag }).count == 1,
              let fixture, fixtureNames.contains(fixture),
              let saveKey, saveKey.hasPrefix("r131-gear-"),
              UUID(uuidString: String(saveKey.dropFirst("r131-gear-".count))) != nil,
              arguments.filter({ $0.hasPrefix("--qa-fixture=") }).count == 1,
              arguments.contains("--qa-fixture=" + fixture),
              arguments.filter({ $0.hasPrefix("--qa-save-key=") }).count == 1,
              arguments.contains("--qa-save-key=" + saveKey),
              arguments.filter({ $0 == "--qa-persist-fixture" }).count == 1,
              arguments.filter({ $0 == "--qa-readback-save" }).count == 1 else {
            throw CoreError.invalidCommand("R131 comparison fixture requires the exact isolated, fresh-key, persisted/readback gate")
        }
        var allowed: Set<String> = ["--qa-isolated", flag, "--qa-fixture=" + fixture,
            "--qa-save-key=" + saveKey, "--qa-persist-fixture", "--qa-readback-save"]
        let contentFlag = "-UIPreferredContentSizeCategoryName"
        let contentIndices = arguments.indices.filter { arguments[$0] == contentFlag }
        guard contentIndices.count <= 1 else { throw CoreError.invalidCommand("Duplicate R131 content-size override") }
        var contentSize: String?
        if let index = contentIndices.first {
            guard arguments.indices.contains(index + 1),
                  ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"].contains(arguments[index + 1]) else {
                throw CoreError.invalidCommand("Unsupported R131 content-size override")
            }
            allowed.insert(contentFlag)
            allowed.insert(arguments[index + 1])
            contentSize = arguments[index + 1]
        }
        guard arguments.allSatisfy({ allowed.contains($0) }) else {
            throw CoreError.invalidCommand("R131 comparison fixture received an unapproved launch argument")
        }
        return Request(fixture: fixture, saveKey: saveKey, contentSize: contentSize)
    }

    private static func uuid(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else {
            throw CoreError.invalidCommand("R131 fixture contains an invalid fixed UUID")
        }
        return id
    }
}
