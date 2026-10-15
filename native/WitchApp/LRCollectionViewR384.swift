import SwiftUI

/// Compact, read-only collection and next-step guidance for existing Q4 gear.
/// Rows are per catalog template, never per owned instance, so inventory growth does not grow this list.
struct LRCollectionViewR384: View {
    let catalog: GameCatalog
    let state: GameSnapshot
    let policyEnabled: Bool
    let onOpenRegion: (String) -> Void

    @State private var latentPolicy: CandidateLatentSlotPolicyR003?

    private var projection: GearLegendaryCollectionProjectionR384 {
        .make(catalog: catalog, state: state, policyEnabled: policyEnabled,
             latentPolicy: latentPolicy)
    }

    var body: some View {
        let p = projection
        let visibleEntries = p.entries.filter { !isUnknown($0.route) }
        let unknownOwnedTypeCount = p.entries.filter { $0.isQ4Template && isUnknown($0.route) }.count
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("工房で進化先を作ると、探索で見つかる道具の種類が増えます。")
                    .fixedSize(horizontal: false, vertical: true)
                Text("集めた道具：\(p.ownedQ4TemplateCount)種類")
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("lr_collection_count_r384")
                Text("同じ種類の道具はまとめて表示します。")
                    .font(.caption)
                    .foregroundStyle(Palette.text)
                if unknownOwnedTypeCount > 0 {
                    Text("詳細を表示できない道具が\(unknownOwnedTypeCount)種類あります。")
                        .font(.caption)
                        .foregroundStyle(Palette.text)
                }
                if let q4 = p.qualityFacts.first(where: { $0.qualityID == "Q4" }) {
                    Text("伝説の道具の潜在枠：\(q4.activeLatentSlots.map { String($0) } ?? "確認できません")")
                        .font(.caption)
                }
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleEntries) { entry in entryRow(entry) }
                }
                .accessibilityIdentifier("lr_collection_rows_r384")
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } label: {
            HStack(spacing: 8) {
                Text("伝説の道具")
                Text("種類と入手先")
                    .font(.caption)
                    .foregroundStyle(Palette.gold)
            }
            .accessibilityIdentifier("lr_collection_header_r384")
        }
        .accessibilityIdentifier("lr_collection_disclosure_r384")
        .accessibilityElement(children: .contain)
        .task {
            guard latentPolicy == nil else { return }
            latentPolicy = try? CandidateLatentSlotPolicyR003.loadBundledR004()
        }
    }

    @ViewBuilder private func entryRow(_ entry: GearLegendaryCollectionProjectionR384.Entry) -> some View {
        let q4Count = entry.ownedInstances.filter(\.isLegendary).count
        let sourceNames = Array(Set(entry.ownedInstances.filter(\.isLegendary).compactMap(\.naturalSourceRegionID)))
            .sorted()
            .compactMap { id in catalog.regions.first(where: { $0.id == id })?.name }
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                AssetIcon(id: "ICO_" + entry.templateID, size: 44)
                    .accessibilityHidden(true)
                Text(entry.name).fontWeight(.semibold)
                Spacer(minLength: 4)
                if q4Count > 0 {
                    Text("所持 \(q4Count)個")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.gold, lineWidth: 1.5))
                        .accessibilityIdentifier("lr_owned_count_r384_\(entry.templateID)")
                }
            }
            if !entry.typeEffectIDs.isEmpty {
                Text(typeEffectDescription(entry.typeEffectIDs))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !sourceNames.isEmpty {
                Text("見つけた地域：" + sourceNames.joined(separator: "・"))
                    .font(.caption)
                    .foregroundStyle(Palette.text)
            }
            HStack(alignment: .top, spacing: 8) {
                Text(routeText(entry.route))
                    .font(.caption)
                    .foregroundStyle(routeIsAvailable(entry.route) ? Palette.gold : Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if case .eligible(let regionID, _, _) = entry.route {
                    Button("探索へ") { onOpenRegion(regionID) }
                        .font(.caption)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("lr_open_region_r384_\(regionID)")
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(q4Count > 0 ? Palette.gold.opacity(0.10) : Palette.panel.opacity(0.65))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(q4Count > 0 ? Palette.gold : Palette.text.opacity(0.2), lineWidth: q4Count > 0 ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lr_template_r384_\(entry.templateID)")
    }

    private func isUnknown(_ route: GearLegendaryCollectionProjectionR384.Route) -> Bool {
        if case .unknownTemplate = route { return true }
        return false
    }

    private func routeIsAvailable(_ route: GearLegendaryCollectionProjectionR384.Route) -> Bool {
        if case .eligible = route { return true }
        return false
    }

    private func routeText(_ route: GearLegendaryCollectionProjectionR384.Route) -> String {
        switch route {
        case .profileDisabled:
            return "現在の探索設定では入手候補を確認できません。"
        case .unknownTemplate:
            return "道具の情報を確認できません。"
        case .noActiveRegion:
            return "探索する地域を選ぶと、候補を確認できます。"
        case .regionLocked:
            return "この地域はまだ探索できません。"
        case .actorNotJoined:
            return "仲間がそろうと入手候補になります。"
        case .craftedDiscoveryRequired:
            return "工房で進化先を作ると、探索候補に加わります。"
        case .recipeGatesRequired(let gates):
            let names = gates.compactMap { gateName($0) }
            return names.isEmpty
                ? "工房の条件を満たすと、探索候補になります。"
                : "工房の条件：" + names.joined(separator: "・")
        case .eligible(let regionID, let localPoolMember, let period):
            let name = catalog.regions.first(where: { $0.id == regionID })?.name ?? "探索"
            switch period {
            case .inFlight:
                return localPoolMember
                    ? "進行中の周期では、\(name)の地域候補と共通候補に含まれます。"
                    : "進行中の周期では、地域共通の候補に含まれます。"
            case .followingPeriod:
                return localPoolMember
                    ? "次の周期は\(name)で始めると、地域候補と共通候補に含まれます。"
                    : "次の周期は地域共通の候補に含まれます。"
            case .newPeriod:
                return localPoolMember
                    ? "\(name)で始める周期の地域候補と共通候補に含まれます。"
                    : "\(name)で始める周期の共通候補に含まれます。"
            }
        }
    }

    private func typeEffectDescription(_ ids: [String]) -> String {
        let descriptions = ids.map(GameText.effect)
        let known = zip(ids, descriptions).compactMap { id, description in
            description == id ? nil : description
        }
        if known.count == ids.count { return known.joined(separator: "・") }
        if known.isEmpty { return "この道具ならではの効果があります。" }
        return known.joined(separator: "・") + " ほかの固有効果があります。"
    }

    private func gateName(_ gateID: String) -> String? {
        guard gateID == "G_START" || gateID.split(separator: "_").count == 3 else { return nil }
        if gateID == "G_START" { return "はじまりの条件" }
        let parts = gateID.split(separator: "_")
        guard parts[0] == "G" else { return nil }
        let encounterID = "B_\(parts[1])_\(parts[2])"
        return catalog.enemies.first(where: { $0.id == encounterID })?.name
    }
}
