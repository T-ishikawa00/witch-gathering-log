import Foundation

/// Creates only an isolated render fixture in a fresh QA save. The caller must
/// refuse this fixture when an existing save is present. No command, reward,
/// currency, or progression state is altered by the fixture builder.
enum EquipmentMultiConsumerFixtureR084 {
    static func make(catalog: GameCatalog, variantID: String) throws -> GameSnapshot {
        guard let variant = EquipmentMultiConsumerRequestR084.variants[variantID],
              let expected = EquipmentMultiConsumerRequestR084.expectedCount(variantID),
              variant.consumers.count == expected else {
            throw CoreError.invalidCommand("unknown or malformed equipment multi-consumer variant")
        }
        var initial = GameSnapshot.newGame(catalog: catalog)
        initial.lastClaimAt = Date()
        let initialGearIDs = Set(initial.gear.map(\.id))
        let initialGearCount = initial.gear.count
        guard initialGearCount == 4 else {
            throw CoreError.invalidCommand("unexpected new-game starter gear count: \(initialGearCount)")
        }
        var seen = Set<String>()
        for consumer in variant.consumers {
            let key = consumer.owner + "|" + consumer.slot
            guard seen.insert(key).inserted,
                  let definition = catalog.gear.first(where: {
                      $0.id == consumer.gearID && $0.slot == consumer.slot && $0.actorIDs.contains(consumer.owner)
                  }) else {
                throw CoreError.invalidCommand("variant has duplicate slot or incompatible formal gear: \(key)=\(consumer.gearID)")
            }
            let instance = GearInstance(definitionID: definition.id, ownerID: consumer.owner, qualityID: "Q1")
            initial.gear.append(instance)
            initial.equippedGearIDs[key] = instance.id
        }
        guard initial.gear.count == initialGearCount + expected,
              initialGearIDs.isSubset(of: Set(initial.gear.map(\.id))) else {
            throw CoreError.invalidCommand("fixture item count or starter preservation mismatch")
        }
        return initial
    }
}
