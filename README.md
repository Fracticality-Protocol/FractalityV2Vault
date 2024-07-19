# Fractality V2 Vault


## Differences from technical SPEC

- We still had some references to 'withdrawal', when in reality we use redeem. Because of this I changed most references from 'withdrawal' to 'redeem'. For example, withdrawFeeBasisPoints to redeemFeeBasisPoints.
- Deposit event not in contract, because it already exists in the ERC4626 parent contract.
- RedeemRequest struct renamed to RedeemRequestData to avoid clash with ERC7540 RedeemRequest event.
- Withdraw event not in contract, because it already exists in the ERC4626 parent contract. However, take note that the base event contains an owner field, which doesn't make sense in an async withdraw. The controller address will be emitted in place of the owner.
- Introduced a new error, to check if the redeem fee is between 0 and 10000 basis points (0% to 100%).