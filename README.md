# Fractality V2 Vault


## Differences from technical SPEC

- We still had some references to 'withdrawal', when in reality we use redeem. Because of this I changed most references from 'withdrawal' to 'redeem'. For example, withdrawFeeBasisPoints to redeemFeeBasisPoints.
- Deposit event not in contract, because it already exists in the ERC4626 parent contract.
- RedeemRequest struct renamed to RedeemRequestData to avoid clash with ERC7540 RedeemRequest event.
- Withdraw event not in contract, because it already exists in the ERC4626 parent contract. However, take note that the base event contains an owner field, which doesn't make sense in an async withdraw. The controller address will be emitted in place of the owner.
- Introduced a new error, to check if the redeem fee is between 0 and 10000 basis points (0% to 100%).
- Introduced a setter for setting claimableDelay
- Introduced a setter for setting the strategy's URI and Name. Plus associated event
- Introdfuced new error HaltStatusUnchanged when attempting to change the halt status to its current value.
- Rename maxDeposit var to maxDepositPerTransaction, due to name conflict with 4626 maxDeposit function. Along with all references to it.
- For consistency with the above, renamed minDeposit var to minDepositPerTransaction. Along with all references to it.
- Changed logic on maxDeposit, wasn't 100% correct.
- The internal function _maxShareRedeem was renamed to _getClaimableShares to better reflect what it does.
- we had AsyncDepositNotAvailable error thrown during requestDeposit, but it's better to have an error that can be used in other functions like previewWithdraw. This error is now NotAvailableInAsyncRedeemVault. Also replaces UseRedeem.
- Was missing ExceedsMaxVaultCapacity check in the mint function.
- New error LossExceedsVaultAssets to add a safety check in report losses.
- Added a setter for the redeem fee collector.
- Storing the original owner of the shares in the request data, so that it can be used in the Withdraw event.
