import Foundation
import CryptoKit

extension GameModel {
    /// No caller in the local candidate supplies this configuration. This is
    /// the composition boundary for an approved environment; default startup
    /// keeps ProductCommerceModelR1 disconnected and never accesses Keychain.
    func configureApprovedCommerceR1(
        configuration: CommerceApprovalConfigurationR465,
        approvedProductByContentID: [String:String],
        approvedContentByEntitlementID: [String:(cosmeticIDs:Set<String>,furnitureIDs:Set<String>)],
        supportedKindsByProductID: [String:Set<CommerceOperationKindR465>],
        bindingProvider: any CommerceAccountBindingProviderR465,
        credentialProvider: any CommerceCredentialProviderR465,
        receiptPublicKey: Curve25519.Signing.PublicKey,
        receiptKeyID: String,
        journal: KeychainCommerceJournalR465
    ) throws {
        guard configuration.validationReasons.isEmpty,
              configuration.bundleID == Bundle.main.bundleIdentifier,
              startupState == .ready, engine != nil,
              !approvedProductByContentID.isEmpty, !approvedContentByEntitlementID.isEmpty,
              Set(approvedProductByContentID.values).isSubset(of:configuration.productIDs),
              Set(supportedKindsByProductID.keys) == configuration.productIDs else {
            throw CoreError.invalidCommand("approved commerce environment and content mapping are incomplete")
        }
        let transport=try URLSessionPurchaseTransportR465(configuration:configuration,credential:credentialProvider)
        let authority=CommerceCandidateAuthorityClientR465(transport:transport,
            receiptPublicKey:receiptPublicKey,receiptKeyID:receiptKeyID,
            contentByEntitlementID:approvedContentByEntitlementID,
            supportedKindsByProductID:supportedKindsByProductID,
            ownershipCommit:{[weak self] mutation in
                guard let self else {throw CoreError.invalidCommand("game is unavailable for durable purchase delivery")}
                try await self.commitVerifiedCommerceOwnershipR1(mutation)
            })
        let adapter=CommerceStoreKit2R465(configuration:configuration,journal:journal,
            authority:authority,bindingProvider:bindingProvider)
        productCommerce=ProductCommerceModelR1(adapter:adapter,
            approvedProductByContentID:approvedProductByContentID)
    }

    /// StoreKit finish is performed by the adapter only after this returns.
    /// Both the game receipt and ownership source ledger use a stable operation
    /// identity, including on an interrupted delivery's later retry.
    func commitVerifiedCommerceOwnershipR1(_ mutation: VerifiedCommerceOwnershipMutationR1) async throws {
        guard let engine else {
            throw CoreError.invalidCommand("game save is unavailable for purchase delivery")
        }
        let before=await engine.snapshot()
        do {
            _=try await engine.dispatchConfirmingSavedReceipt(
                .applyVerifiedCommerceOwnershipR1(mutation,nowEpochSeconds:Int64(Date().timeIntervalSince1970)),
                operationID:mutation.durableOperationID,expectedRevision:before.revision)
            await refresh()
        } catch {
            self.error=commandErrorText(error)
            await refresh()
            throw error
        }
    }

    /// Reconcile only existing commerce records. This never creates purchase
    /// rights or modifies a legacy save without a commerce ledger.
    func reconcileExpiredCommerceOwnershipR1() async {
        guard let engine else {return}
        let before=await engine.snapshot()
        guard before.commerceOwnershipR1 != nil else {return}
        let now=Int64(Date().timeIntervalSince1970)
        var projected=before
        projected.reconcileCommerceOwnershipR1(nowEpochSeconds:now)
        guard projected != before else {return}
        do {
            _=try await engine.dispatchConfirmingSavedReceipt(.reconcileCommerceOwnershipR1(nowEpochSeconds:now),
                operationID:UUID(),expectedRevision:before.revision)
            await refresh()
        } catch {self.error=commandErrorText(error)}
    }
}
