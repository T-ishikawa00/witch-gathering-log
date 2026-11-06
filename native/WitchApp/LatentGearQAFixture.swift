import Foundation

/// Explicit isolated visual/interaction fixture. It is not an earned loadout.
enum LatentGearQAFixture {
    static let lowItemID = UUID(uuid: (0x07, 0x3d, 0x86, 0x5a, 0x04, 0x7c, 0x47, 0xd0, 0x90, 0xc0, 0x24, 0xc4, 0x6f, 0x36, 0x7c, 0x00))
    static let highItemID = UUID(uuid: (0x07, 0x3d, 0x86, 0x5a, 0x04, 0x7c, 0x47, 0xd0, 0x90, 0xc0, 0x24, 0xc4, 0x6f, 0x36, 0x7c, 0x04))

    static func make(catalog: GameCatalog, policy: CandidateLatentSlotPolicyR003) throws -> GameSnapshot {
        var state = try GameSnapshot.newCandidateGame(catalog: catalog, candidateLatentPolicy: policy)
        state.lastClaimAt = Date()
        // Synthetic prerequisite for the isolated comparison interaction test.
        // This fixture does not assert an earned craft or normal progression.
        state.craftedGearOnce = true
        let payload = try CandidateLatentSlotsR003(slots: [
            .init(affixID: "AF_POWER", rawQ: 250),
            .init(affixID: "AF_HEAL", rawQ: 400),
            .init(affixID: "AF_CRIT_DMG", rawQ: 0)
        ])
        try policy.validateNewInstanceSlots(templateID: "EQ_BODY_01", joinedActorIDs: Set(state.partyActorIDs), slots: payload)
        state.gear.append(GearInstance(id: lowItemID, definitionID: "EQ_BODY_01",
            candidateLatentSlots: payload, qualityID: "Q0"))
        state.gear.append(GearInstance(id: highItemID, definitionID: "EQ_BODY_01",
            candidateLatentSlots: payload, qualityID: "Q4"))
        return state
    }
}
