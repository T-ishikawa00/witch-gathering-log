import Foundation
import StoreKit
import StoreKitTest

@main struct LocalStoreKitProbe {
    static func main() async {
        let args=CommandLine.arguments
        let out=URL(fileURLWithPath:args[2])
        var log:[String:Any] = ["environment":"StoreKitTest macOS local only","realCharge":false,"iOS_runtime_test":false]
        do{
            let session=try SKTestSession(contentsOf:URL(fileURLWithPath:args[1]))
            session.disableDialogs=true
            session.storefront="JPN"
            let product="local.witch.test.furniture"
            let transaction=try await session.buyProduct(identifier:product)
            log["purchase"]=["id":transaction.id,"product":transaction.productID,"environment":String(describing:transaction.environment)]
            try session.refundTransaction(identifier:UInt(transaction.id))
            log["after_refund"]=session.allTransactions().map{["id":$0.identifier,"cancelled":$0.cancelDate != nil,"state":$0.state.rawValue]}
            session.askToBuyEnabled=true
            do{_ = try await session.buyProduct(identifier:"local.witch.test.ticket");log["askToBuyRequested"]=true}catch{log["askToBuyError"]=String(describing:error)}
            log["pending"]=session.allTransactions().filter{$0.pendingAskToBuyConfirmation}.count
            log["status"]="LOCAL_STOREKIT_TEST_EXECUTED"
        }catch{log["status"]="BLOCKED_LOCAL_STOREKIT_RUNTIME";log["error"]=String(describing:error)}
        let data=try! JSONSerialization.data(withJSONObject:log,options:[.prettyPrinted,.sortedKeys]);try! data.write(to:out,options:.atomic);print(String(data:data,encoding:.utf8)!)
    }
}
