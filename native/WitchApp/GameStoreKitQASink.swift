import Foundation
import StoreKit
import CryptoKit

/// Local Xcode receipts live inside the same atomic save as game progress, but
/// in separate QA ownership/currency namespaces. These are never production rights.
actor GameStoreKitQASink: StoreKitLocalQADurableSink {
    let saves:SaveRepository
    let changed:@Sendable () async -> Void
    private var failWrites=false
    func setFailureInjection(_ enabled:Bool){failWrites=enabled}
    init(saves:SaveRepository,changed:@escaping @Sendable () async -> Void={}){self.saves=saves;self.changed=changed}
    func apply(_ event:StoreKitLocalQAEvent) async throws {
        guard event.environment=="Xcode" else{throw StoreKitLocalQAError.nonXcodeEnvironment(event.environment)}
        let furniture=event.productID=="local.witch.test.furniture" && event.productKind == .nonConsumable
        let ticket=event.productID=="local.witch.test.ticket" && event.productKind == .consumable
        guard furniture || ticket else{throw CoreError.invalidCommand("unknown local QA product/type")}
        if event.kind == .restore && ticket {return}
        if failWrites {throw CocoaError(.fileWriteOutOfSpace)}
        let hash=Array(SHA256.hash(data:Data(event.idempotencyKey.utf8)).prefix(16))
        let op=UUID(uuid:(hash[0],hash[1],hash[2],hash[3],hash[4],hash[5],hash[6],hash[7],hash[8],hash[9],hash[10],hash[11],hash[12],hash[13],hash[14],hash[15]))
        let transactionKey="storekit-xcode:\(event.transactionID)"
        for attempt in 0..<5 {
            let current=await saves.snapshot()
            do {
                _ = try await saves.transact(expectedRevision:current.revision,operationID:op,requestFingerprint:event.idempotencyKey+"|"+event.productID){state in
                    let purchaseKey=transactionKey+":entitlement", revokeKey=transactionKey+":revocation"
                    for existing in [state.localStoreKitQARecords[purchaseKey],state.localStoreKitQARecords[revokeKey]].compactMap({$0}) {guard existing.productID==event.productID else{throw CoreError.invalidCommand("local QA transaction product conflict")}}
                    if state.localStoreKitQARecords[event.idempotencyKey] != nil{return "local QA duplicate ignored"}
                    let revoked=event.kind == .revocation
                    state.localStoreKitQARecords[event.idempotencyKey]=LocalStoreKitQARecord(productID:event.productID,kind:revoked ? .revocation:.purchase,transactionID:String(event.transactionID),recordedAt:event.revocationDate ?? event.purchaseDate)
                    if ticket {
                        if !revoked && state.localStoreKitQARecords[revokeKey]==nil {state.currency["storekit_qa_ticket",default:0]+=1}
                        else if revoked && state.localStoreKitQARecords[purchaseKey] != nil {state.currency["storekit_qa_ticket",default:0]=max(0,state.currency["storekit_qa_ticket",default:0]-1)}
                    }
                    // Evaluate all receipts so a refund cannot remove a different valid entitlement.
                    let valid=state.localStoreKitQARecords.values.contains {record in record.productID==event.productID && record.kind == .purchase && state.localStoreKitQARecords["storekit-xcode:"+record.transactionID+":revocation"]==nil}
                    if furniture && valid {state.localStoreKitQAOwnedProductIDs.insert(event.productID)}else{state.localStoreKitQAOwnedProductIDs.remove(event.productID)}
                    return "XCODE_LOCAL_QA durable receipt; production rights unchanged"
                }
                await changed();return
            } catch CoreError.revisionConflict {if attempt==4{throw CoreError.invalidCommand("local QA save busy; transaction remains unfinished")}}
        }
    }
}
