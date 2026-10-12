import Foundation
@main struct GameSinkRegression {
    static func main() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("witch-game-sink-"+UUID().uuidString)
        let file=folder.appendingPathComponent("save.json")
        let saves=try SaveRepository(fileURL:file);let sink=GameStoreKitQASink(saves:saves)
        func event(_ id:UInt64,_ kind:StoreKitLocalQAEventKind = .purchase,_ ticket:Bool=false)->StoreKitLocalQAEvent {StoreKitLocalQAEvent(kind:kind,transactionID:id,productID:ticket ? "local.witch.test.ticket":"local.witch.test.furniture",productKind:ticket ? .consumable:.nonConsumable,environment:"Xcode",purchaseDate:Date(timeIntervalSince1970:1000),revocationDate:kind == .revocation ? Date(timeIntervalSince1970:2000):nil)}
        try await sink.apply(event(1));try await sink.apply(event(1));try await sink.apply(event(1,.restore))
        var state=await saves.snapshot();precondition(state.revision==1 && state.localStoreKitQARecords.count==1 && state.localStoreKitQAOwnedProductIDs.count==1)
        let reloaded=try SaveRepository(fileURL:file);let loaded=await reloaded.snapshot();precondition(loaded.localStoreKitQARecords.count==1)
        try await sink.apply(event(2));try await sink.apply(event(1,.revocation));state=await saves.snapshot();precondition(state.localStoreKitQAOwnedProductIDs.count==1)
        try await sink.apply(event(2,.revocation));state=await saves.snapshot();precondition(state.localStoreKitQAOwnedProductIDs.isEmpty)
        try await sink.apply(event(3,.revocation));try await sink.apply(event(3));state=await saves.snapshot();precondition(state.localStoreKitQAOwnedProductIDs.isEmpty)
        try await sink.apply(event(4,.purchase,true));try await sink.apply(event(4,.purchase,true));try await sink.apply(event(4,.restore,true));state=await saves.snapshot();precondition(state.currency["storekit_qa_ticket"]==1 && state.localStoreKitQAOwnedProductIDs.isEmpty)
        try await sink.apply(event(4,.revocation,true));try await sink.apply(event(4,.revocation,true));state=await saves.snapshot();precondition(state.currency["storekit_qa_ticket"]==0)
        try await sink.apply(event(5,.revocation,true));try await sink.apply(event(5,.purchase,true));state=await saves.snapshot();precondition(state.currency["storekit_qa_ticket"]==0)
        await withTaskGroup(of:Void.self){group in for _ in 0..<10{group.addTask{try! await sink.apply(event(6,.purchase,true))}}}
        state=await saves.snapshot();precondition(state.currency["storekit_qa_ticket"]==1)
        let invalid=StoreKitLocalQAEvent(kind:.purchase,transactionID:100,productID:"local.witch.test.furniture",productKind:.nonConsumable,environment:"Sandbox",purchaseDate:Date(),revocationDate:nil)
        do{try await sink.apply(invalid);fatalError("Sandbox event accepted")}catch StoreKitLocalQAError.nonXcodeEnvironment{}
        let blocked=folder.appendingPathComponent("blocked");try Data("file".utf8).write(to:blocked)
        let broken=try SaveRepository(fileURL:blocked.appendingPathComponent("save.json"));let failedSink=GameStoreKitQASink(saves:broken)
        do{try await failedSink.apply(event(88));fatalError("write failure ignored")}catch{}
        let failedState=await broken.snapshot();precondition(failedState.localStoreKitQARecords.isEmpty)
        print("PASS: game-save sink purchase/restore/dedupe/reload/revoke/order/concurrency/environment/failure; native StoreKit delivery tested separately")
    }
}
