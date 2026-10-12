import Foundation

/// Provisional R4 scene-to-background projection for the isolated R015 candidate.
/// It does not own progression gates or save state; the source of the route records
/// is art_catalog_R4.json and these values are checked against that file by tests.
public struct R015AreaSceneRoute: Codable, Equatable, Sendable {
    public let sceneID: String
    public let areaID: String
    public let regionID: String
    public let baseBackgroundID: String
    public let variantID: String?
    public let gatherableMaterialIDs: [String]
    public let enemyIDs: [String]
    public let unlockGate: String

    public init(sceneID: String, areaID: String, regionID: String,
                baseBackgroundID: String, variantID: String?,
                gatherableMaterialIDs: [String], enemyIDs: [String], unlockGate: String) {
        self.sceneID = sceneID
        self.areaID = areaID
        self.regionID = regionID
        self.baseBackgroundID = baseBackgroundID
        self.variantID = variantID
        self.gatherableMaterialIDs = gatherableMaterialIDs
        self.enemyIDs = enemyIDs
        self.unlockGate = unlockGate
    }
}

public struct R015AreaSceneResolution: Codable, Equatable, Sendable {
    public enum SelectionBasis: String, Codable, Sendable {
        case activeFightEnemy
        case selectedGatherMaterial
        case regionDefaultArea01
        case enemyFallback
        case gatherFallback
    }

    public enum BackgroundMode: String, Codable, Sendable {
        case regionBase
        case layeredVariantReplacement
        case fullFrameVariantReplacement
    }

    public let route: R015AreaSceneRoute
    public let renderedBackgroundID: String
    public let selectionBasis: SelectionBasis
    public let backgroundMode: BackgroundMode
    public let fallbackReason: String?

    public var requestedVariantID: String? { route.variantID }
    public var selectedSceneID: String { route.sceneID }

    public func qaReceipt() -> [String: String] {
        var value: [String: String] = [
            "sceneID": route.sceneID,
            "areaID": route.areaID,
            "regionID": route.regionID,
            "baseBackgroundID": route.baseBackgroundID,
            "renderedBackgroundID": renderedBackgroundID,
            "selectionBasis": selectionBasis.rawValue,
            "backgroundMode": backgroundMode.rawValue
        ]
        if let variantID = route.variantID { value["requestedVariantID"] = variantID }
        if let fallbackReason { value["fallbackReason"] = fallbackReason }
        return value
    }

    public func fallingBackToBase(reason: String) -> R015AreaSceneResolution {
        R015AreaSceneResolution(route: route, renderedBackgroundID: route.baseBackgroundID,
                                selectionBasis: selectionBasis, backgroundMode: .regionBase,
                                fallbackReason: reason)
    }
}

public enum R015AreaSceneRouting {
    /// The values mirror only the routing fields of the 20 R4 `scenes` records.
    /// R4 source SHA: 0111b15d1f995ec9600a7ea6560e17610cade4138cbff8d2c7b0e7c1cc06f352.
    public static let sourceCatalogSHA256 = "0111b15d1f995ec9600a7ea6560e17610cade4138cbff8d2c7b0e7c1cc06f352"

    public static let routes: [R015AreaSceneRoute] = [
        .init(sceneID: "SCN_A_R01_01", areaID: "A_R01_01", regionID: "R01", baseBackgroundID: "BG_R01_FIELD", variantID: nil, gatherableMaterialIDs: ["M_R01_G1", "M_R01_G2"], enemyIDs: ["E_R01_01", "E_R01_02"], unlockGate: "G_START"),
        .init(sceneID: "SCN_A_R01_02", areaID: "A_R01_02", regionID: "R01", baseBackgroundID: "BG_R01_FIELD", variantID: "VAR_A_R01_02", gatherableMaterialIDs: [], enemyIDs: ["B_R01_A"], unlockGate: "G_START"),
        .init(sceneID: "SCN_A_R01_03", areaID: "A_R01_03", regionID: "R01", baseBackgroundID: "BG_R01_FIELD", variantID: "VAR_A_R01_03", gatherableMaterialIDs: ["M_R01_G3", "M_R01_G4"], enemyIDs: ["E_R01_03", "E_R01_04"], unlockGate: "G_R01_A"),
        .init(sceneID: "SCN_A_R01_04", areaID: "A_R01_04", regionID: "R01", baseBackgroundID: "BG_R01_BOSS", variantID: nil, gatherableMaterialIDs: [], enemyIDs: ["B_R01_B"], unlockGate: "G_R01_A"),
        .init(sceneID: "SCN_A_R02_01", areaID: "A_R02_01", regionID: "R02", baseBackgroundID: "BG_R02_FIELD", variantID: nil, gatherableMaterialIDs: ["M_R02_G1", "M_R02_G2"], enemyIDs: ["E_R02_01", "E_R02_02"], unlockGate: "G_R01_B"),
        .init(sceneID: "SCN_A_R02_02", areaID: "A_R02_02", regionID: "R02", baseBackgroundID: "BG_R02_FIELD", variantID: "VAR_A_R02_02", gatherableMaterialIDs: [], enemyIDs: ["B_R02_A"], unlockGate: "G_R01_B"),
        .init(sceneID: "SCN_A_R02_03", areaID: "A_R02_03", regionID: "R02", baseBackgroundID: "BG_R02_FIELD", variantID: "VAR_A_R02_03", gatherableMaterialIDs: ["M_R02_G3", "M_R02_G4"], enemyIDs: ["E_R02_03", "E_R02_04"], unlockGate: "G_R02_A"),
        .init(sceneID: "SCN_A_R02_04", areaID: "A_R02_04", regionID: "R02", baseBackgroundID: "BG_R02_BOSS", variantID: nil, gatherableMaterialIDs: [], enemyIDs: ["B_R02_B"], unlockGate: "G_R02_A"),
        .init(sceneID: "SCN_A_R03_01", areaID: "A_R03_01", regionID: "R03", baseBackgroundID: "BG_R03_FIELD", variantID: nil, gatherableMaterialIDs: ["M_R03_G1", "M_R03_G2"], enemyIDs: ["E_R03_01", "E_R03_02"], unlockGate: "G_R02_B"),
        .init(sceneID: "SCN_A_R03_02", areaID: "A_R03_02", regionID: "R03", baseBackgroundID: "BG_R03_FIELD", variantID: "VAR_A_R03_02", gatherableMaterialIDs: [], enemyIDs: ["B_R03_A"], unlockGate: "G_R02_B"),
        .init(sceneID: "SCN_A_R03_03", areaID: "A_R03_03", regionID: "R03", baseBackgroundID: "BG_R03_FIELD", variantID: "VAR_A_R03_03", gatherableMaterialIDs: ["M_R03_G3", "M_R03_G4"], enemyIDs: ["E_R03_03", "E_R03_04"], unlockGate: "G_R03_A"),
        .init(sceneID: "SCN_A_R03_04", areaID: "A_R03_04", regionID: "R03", baseBackgroundID: "BG_R03_BOSS", variantID: nil, gatherableMaterialIDs: [], enemyIDs: ["B_R03_B"], unlockGate: "G_R03_A"),
        .init(sceneID: "SCN_A_R04_01", areaID: "A_R04_01", regionID: "R04", baseBackgroundID: "BG_R04_FIELD", variantID: nil, gatherableMaterialIDs: ["M_R04_G1", "M_R04_G2"], enemyIDs: ["E_R04_01", "E_R04_02"], unlockGate: "G_R03_B"),
        .init(sceneID: "SCN_A_R04_02", areaID: "A_R04_02", regionID: "R04", baseBackgroundID: "BG_R04_FIELD", variantID: "VAR_A_R04_02", gatherableMaterialIDs: [], enemyIDs: ["B_R04_A"], unlockGate: "G_R03_B"),
        .init(sceneID: "SCN_A_R04_03", areaID: "A_R04_03", regionID: "R04", baseBackgroundID: "BG_R04_FIELD", variantID: "VAR_A_R04_03", gatherableMaterialIDs: ["M_R04_G3", "M_R04_G4"], enemyIDs: ["E_R04_03", "E_R04_04"], unlockGate: "G_R04_A"),
        .init(sceneID: "SCN_A_R04_04", areaID: "A_R04_04", regionID: "R04", baseBackgroundID: "BG_R04_BOSS", variantID: nil, gatherableMaterialIDs: [], enemyIDs: ["B_R04_B"], unlockGate: "G_R04_A"),
        .init(sceneID: "SCN_A_R05_01", areaID: "A_R05_01", regionID: "R05", baseBackgroundID: "BG_R05_FIELD", variantID: nil, gatherableMaterialIDs: ["M_R05_G1", "M_R05_G2"], enemyIDs: ["E_R05_01", "E_R05_02"], unlockGate: "G_R04_B"),
        .init(sceneID: "SCN_A_R05_02", areaID: "A_R05_02", regionID: "R05", baseBackgroundID: "BG_R05_FIELD", variantID: "VAR_A_R05_02", gatherableMaterialIDs: [], enemyIDs: ["B_R05_A"], unlockGate: "G_R04_B"),
        .init(sceneID: "SCN_A_R05_03", areaID: "A_R05_03", regionID: "R05", baseBackgroundID: "BG_R05_FIELD", variantID: "VAR_A_R05_03", gatherableMaterialIDs: ["M_R05_G3", "M_R05_G4"], enemyIDs: ["E_R05_03", "E_R05_04"], unlockGate: "G_R05_A"),
        .init(sceneID: "SCN_A_R05_04", areaID: "A_R05_04", regionID: "R05", baseBackgroundID: "BG_R05_BOSS", variantID: nil, gatherableMaterialIDs: [], enemyIDs: ["B_R05_B"], unlockGate: "G_R05_A")
    ]

    public struct VariantAvailability: Equatable, Sendable {
        public let fullFrameIDs: Set<String>
        public let layeredIDs: Set<String>
    }

    /// Layered data wins over selectedPNG when present. R01_02/03 are assembled
    /// from registered layers; R02-R05 variants use single full-frame review images.
    public static func variantAvailability(index: [String: [String: Any]], artRoot: URL,
                                           fileManager: FileManager = .default) -> VariantAvailability {
        var fullFrame = Set<String>()
        var layered = Set<String>()
        for (id, entry) in index where entry["kind"] as? String == "area_variant" {
            if let specs = entry["sceneLayers"] as? [[String: Any]], !specs.isEmpty {
                let paths = specs.compactMap { $0["path"] as? String }
                guard paths.count == specs.count,
                      paths.allSatisfy({ fileManager.fileExists(atPath: artRoot.appendingPathComponent($0).path) })
                else { continue }
                layered.insert(id)
            } else if let relativePath = entry["selectedPNG"] as? String, !relativePath.isEmpty,
                      fileManager.fileExists(atPath: artRoot.appendingPathComponent(relativePath).path) {
                fullFrame.insert(id)
            }
        }
        return VariantAvailability(fullFrameIDs: fullFrame, layeredIDs: layered)
    }

    public static func availableVariantIDs(index: [String: [String: Any]], artRoot: URL,
                                            fileManager: FileManager = .default) -> Set<String> {
        let availability = variantAvailability(index: index, artRoot: artRoot, fileManager: fileManager)
        return availability.fullFrameIDs.union(availability.layeredIDs)
    }

    public static func catalogEnemyID(fromRuntimeID runtimeID: String) -> String? {
        let candidate = runtimeID.hasPrefix("ACT_") ? String(runtimeID.dropFirst(4)) : runtimeID
        return routes.contains(where: { $0.enemyIDs.contains(candidate) }) ? candidate : nil
    }

    public static func resolve(regionID: String, activeFightEnemyID: String? = nil,
                               selectedGatherMaterialID: String? = nil,
                               availableVariantIDs: Set<String>,
                               layeredVariantIDs: Set<String> = []) -> R015AreaSceneResolution {
        let regionRoutes = routes.filter { $0.regionID == regionID }
        let scene: R015AreaSceneRoute
        let basis: R015AreaSceneResolution.SelectionBasis
        var reason: String?

        if let enemyID = activeFightEnemyID {
            if let matched = routes.first(where: { $0.enemyIDs.contains(enemyID) }), matched.regionID == regionID {
                scene = matched
                basis = .activeFightEnemy
            } else {
                scene = regionRoutes.first(where: { $0.areaID.hasSuffix("_01") }) ?? routes[0]
                basis = .enemyFallback
                reason = "enemy_scene_unmapped_or_region_mismatch:" + enemyID
            }
        } else if let materialID = selectedGatherMaterialID {
            if let matched = routes.first(where: { $0.gatherableMaterialIDs.contains(materialID) }), matched.regionID == regionID {
                scene = matched
                basis = .selectedGatherMaterial
            } else {
                scene = regionRoutes.first(where: { $0.areaID.hasSuffix("_01") }) ?? routes[0]
                basis = .gatherFallback
                reason = "gather_scene_unmapped_or_region_mismatch:" + materialID
            }
        } else {
            scene = regionRoutes.first(where: { $0.areaID.hasSuffix("_01") }) ?? routes[0]
            basis = .regionDefaultArea01
        }

        guard let variantID = scene.variantID else {
            return .init(route: scene, renderedBackgroundID: scene.baseBackgroundID,
                         selectionBasis: basis, backgroundMode: .regionBase, fallbackReason: reason)
        }
        guard availableVariantIDs.contains(variantID) else {
            reason = reason ?? "runtime_variant_unavailable:" + variantID
            return .init(route: scene, renderedBackgroundID: scene.baseBackgroundID,
                         selectionBasis: basis, backgroundMode: .regionBase, fallbackReason: reason)
        }
        let mode: R015AreaSceneResolution.BackgroundMode = layeredVariantIDs.contains(variantID)
            ? .layeredVariantReplacement : .fullFrameVariantReplacement
        return .init(route: scene, renderedBackgroundID: variantID,
                     selectionBasis: basis, backgroundMode: mode, fallbackReason: reason)
    }
}
