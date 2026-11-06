import Foundation
import XCTest
@testable import WitchGameCore

final class SaveRepositoryCommerceR1Tests: XCTestCase {
    private func location() throws -> URL {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("product-commerce-codec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        return dir.appendingPathComponent("save.json")
    }
    private func root(_ url:URL) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
    }
    private func write(_ input:[String:Any],to url:URL) throws {
        var value=input
        value["integritySHA256"]=try SaveDocumentCodec.checksum(for:value)
        try JSONSerialization.data(withJSONObject:value,options:.sortedKeys).write(to:url,options:.atomic)
    }
    private func seeded(_ snapshot:GameSnapshot = GameSnapshot()) async throws -> URL {
        let url=try location(), repository=try SaveRepository(initial:snapshot,fileURL:url)
        _=try await repository.transact(expectedRevision:0,operationID:UUID(),requestFingerprint:"codec-seed") {_ in "seed"}
        return url
    }

    func testLegacyAbsenceIsAcceptedButPresentNullCannotEraseProvenance() async throws {
        let url=try await seeded(GameSnapshot(ownedCosmeticIDs:["legacy-free"]))
        let legacy=try SaveRepository(fileURL:url)
        let state=await legacy.snapshot()
        XCTAssertNil(state.commerceOwnershipR1)
        XCTAssertEqual(state.ownedCosmeticIDs,["legacy-free"])
        var document=try root(url)
        var snapshot=try XCTUnwrap(document["snapshot"] as? [String:Any])
        snapshot["commerceOwnershipR1"]=NSNull()
        document["snapshot"]=snapshot
        try write(document,to:url)
        let bytes=try Data(contentsOf:url)
        XCTAssertThrowsError(try SaveRepository(fileURL:url))
        XCTAssertEqual(try Data(contentsOf:url),bytes)
    }

    func testMalformedProvenanceFailsClosedWithoutRewritingSave() async throws {
        var state=GameSnapshot()
        state.commerceOwnershipR1=CommerceOwnershipProvenanceR1()
        let url=try await seeded(state)
        var document=try root(url)
        var snapshot=try XCTUnwrap(document["snapshot"] as? [String:Any])
        var ledger=try XCTUnwrap(snapshot["commerceOwnershipR1"] as? [String:Any])
        ledger["authorityRevision"] = -1
        snapshot["commerceOwnershipR1"]=ledger
        document["snapshot"]=snapshot
        try write(document,to:url)
        let bytes=try Data(contentsOf:url)
        XCTAssertThrowsError(try SaveRepository(fileURL:url))
        XCTAssertEqual(try Data(contentsOf:url),bytes)
    }

    func testOpaqueGrantDataFollowsStableIdentityAcrossAdditionRemovalAndColdRead() async throws {
        let digest=String(repeating:"a",count:64)
        let first=CommerceOwnershipProvenanceR1.Grant(transactionID:"test-1",entitlementID:"cosmetic",cosmeticIDs:["one"],furnitureIDs:[],expiresAtEpochSeconds:nil,receiptFingerprint:digest)
        let second=CommerceOwnershipProvenanceR1.Grant(transactionID:"test-2",entitlementID:"cosmetic",cosmeticIDs:["two"],furnitureIDs:[],expiresAtEpochSeconds:nil,receiptFingerprint:digest)
        var state=GameSnapshot(ownedCosmeticIDs:["one"])
        state.commerceOwnershipR1=CommerceOwnershipProvenanceR1(grants:[first])
        let url=try await seeded(state)
        var document=try root(url)
        var snapshot=try XCTUnwrap(document["snapshot"] as? [String:Any])
        var ledger=try XCTUnwrap(snapshot["commerceOwnershipR1"] as? [String:Any])
        var grants=try XCTUnwrap(ledger["grants"] as? [[String:Any]])
        grants[0]["futureGrantField"]=["belongsTo":"test-1"]
        ledger["grants"]=grants;ledger["futureLedgerField"]=17
        snapshot["commerceOwnershipR1"]=ledger;document["snapshot"]=snapshot
        try write(document,to:url)
        let repository=try SaveRepository(fileURL:url)
        // Codec-only synthetic ledger: no purchase, normal save, or real entitlement.
        _=try await repository.transact(expectedRevision:1,operationID:UUID(),requestFingerprint:"codec-add") {
            $0.commerceOwnershipR1?.grants.insert(second,at:0)
            $0.ownedCosmeticIDs.insert("two")
            return "added"
        }
        _=try await repository.transact(expectedRevision:2,operationID:UUID(),requestFingerprint:"codec-remove") {
            $0.commerceOwnershipR1?.grants.removeAll{$0.transactionID == "test-2"}
            $0.ownedCosmeticIDs.remove("two")
            return "removed"
        }
        let final=try root(url)
        let finalState=try XCTUnwrap(final["snapshot"] as? [String:Any])
        let finalLedger=try XCTUnwrap(finalState["commerceOwnershipR1"] as? [String:Any])
        let finalGrants=try XCTUnwrap(finalLedger["grants"] as? [[String:Any]])
        XCTAssertEqual(finalLedger["futureLedgerField"] as? Int,17)
        XCTAssertEqual(finalGrants.count,1)
        XCTAssertEqual(finalGrants[0]["id"] as? String,first.id)
        XCTAssertEqual(finalGrants[0]["futureGrantField"] as? [String:String],["belongsTo":"test-1"])
        let cold=try SaveRepository(fileURL:url)
        let reopened=await cold.snapshot()
        XCTAssertEqual(reopened.commerceOwnershipR1?.grants,[first])
        XCTAssertEqual(reopened.ownedCosmeticIDs,["one"])
    }
}
