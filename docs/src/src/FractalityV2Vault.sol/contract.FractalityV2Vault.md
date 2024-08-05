# FractalityV2Vault
[Git Source](https://github.com/Fracticality-Protocol/FractalityV2Vault/blob/2a6df5a40c8e9bc55cd5b87bf651db18e00d67c4/src/FractalityV2Vault.sol)

**Inherits:**
AccessControl, ERC4626, ReentrancyGuard

**Author:**
Jose Herrera <jose@y2k.finance>

This contract implements an ERC7540 async deposit vault where funds are invested in an external strategy.

*Inherits from AccessControl for role-based access control, ERC4626 for tokenized vault functionality, and ReentrancyGuard for protection against reentrancy attacks*


## State Variables
### PNL_REPORTER_ROLE
Role that allows reporting of profits and losses

*This role is responsible for updating the vault's financial status due to the strategy's performance*


```solidity
bytes32 public constant PNL_REPORTER_ROLE = keccak256("PNL_REPORTER_ROLE");
```


### strategy
The investment strategy currently employed by this vault

*This strategy defines where and how all the funds in the vault will be invested*


```solidity
InvestmentStrategy public strategy;
```


### totalSharesInRedemptionProcess
Total number of shares currently in the redemption process

*These shares are no longer in the custody of users but are held by the vault during redemption*

*This value represents the sum of all shares that have been requested for redemption but not yet processed*


```solidity
uint256 public totalSharesInRedemptionProcess;
```


### totalProfitsReported
Total sum of all historical profits reported by the PNL_REPORTER_ROLE admin.

*This variable accumulates all profits reported over time, providing a historical record of the vault's performance*


```solidity
uint256 public totalProfitsReported;
```


### totalLossesReported
Total sum of all historical losses reported by the PNL_REPORTER_ROLE admin.

*This variable accumulates all losses reported over time, providing a historical record of the vault's negative performance*


```solidity
uint256 public totalLossesReported;
```


### totalAssetsInRedemptionProcess
Total value of assets currently in the redemption process

*This represents the sum of all assets (converted from shares at their respective exchange rates at request time) that are currently being redeemed*

*It's important to note that this sum was made with different exchange rates, so it's not safe to convert back to shares using the current exchange rate.*


```solidity
uint256 public totalAssetsInRedemptionProcess;
```


### minDepositPerTransaction
The minimum amount of assets that need to be deposited by a user per deposit transaction

*This value sets the lower limit for deposits to prevent dust amounts and prevent truncation errors.*

*Attempts to deposit less than this amount will be rejected*


```solidity
uint128 public minDepositPerTransaction;
```


### maxDepositPerTransaction
The maximum amount of assets that can be deposited by a user per deposit transaction

*This value sets the upper limit for deposits to prevent overflows and prevent truncation errors.*

*Attempts to deposit more than this amount will be rejected*


```solidity
uint128 public maxDepositPerTransaction;
```


### maxVaultCapacity
The maximum amount of assets that the vault can hold

*This value sets the upper limit for the total assets in the vault*

*Deposits that would cause the total assets to exceed this limit will be rejected*


```solidity
uint256 public maxVaultCapacity;
```


### vaultAssets
The abstract representation of the total assets in the vault

*This value represents the assets in the vault, although the actual assets are held in the strategy*

*Increases with deposits and profit reporting, decreases with redeems and loss reporting*

*Note: This is an abstract representation as the actual assets are managed by the strategy*


```solidity
uint256 public vaultAssets;
```


### redeemFeeCollector
The address where redeem fees are sent

*This address receives the assets collected from the redeem fee*


```solidity
address public redeemFeeCollector;
```


### halted
Indicates whether the vault operations are halted

*When true, certain operations in the vault cannot be performed*

*This is typically used in emergency situations or during maintenance*


```solidity
bool public halted;
```


### _MAX_BASIS_POINTS
The maximum number of basis points

*This constant represents 100% in basis points (100% = 10000 basis points)*

*Used as a denominator in percentage calculations during redeem fee calculation.*


```solidity
uint16 private constant _MAX_BASIS_POINTS = 10000;
```


### redeemFeeBasisPoints
The fee charged on redeems, expressed in basis points

*100 basis points = 1%. For example, a value of 20 represents a 0.2% fee*

*This fee is deducted from the assets at the time of redeem*


```solidity
uint16 public redeemFeeBasisPoints;
```


### claimableDelay
The minimum delay between creating a redemption request and when it can be processed

*This value is in seconds and represents the mandatory waiting period for redemption requests*

*Users must wait at least this long after creating a request before it can be processed*


```solidity
uint32 public claimableDelay;
```


### redeemRequests
Mapping of user addresses to their redeem requests

*This mapping holds redeem requests per user. Only one active redeem request per user is allowed.*

*The key is the user's address, and the value is a RedeemRequest struct containing the request details.*


```solidity
mapping(address => RedeemRequestData) public redeemRequests;
```


### operators
Mapping of operator permissions

*This double mapping represents the operator status of an address, for another address*

*The first address is the account giving operator status to the second address*

*The second address is the operator being granted permissions*

*The boolean value indicates whether the operator status is active (true) or not (false)*

*This is used in several functions to allow delegation of certain actions*


```solidity
mapping(address => mapping(address => bool)) public operators;
```


## Functions
### onlyWhenNotHalted

Modifier to restrict function execution when the contract is halted

*This modifier checks if the contract is in a halted state and reverts if it is*


```solidity
modifier onlyWhenNotHalted();
```

### operatorCheck

Modifier to check if the caller is authorized to perform operations on behalf of a user

*This modifier checks if the caller is either the user themselves or an approved operator for the user*


```solidity
modifier operatorCheck(address user);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|The address of the user whose authorization is being checked|


### constructor

Initializes the vault with the provided parameters

*Sets up the vault's configuration, strategy, and initial roles*


```solidity
constructor(ConstructorParams memory params)
    ERC4626(ERC20(params.asset), params.vaultSharesName, params.vaultSharesSymbol)
    AccessControl();
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`ConstructorParams`|A struct containing all necessary initialization parameters, see ConstructorParams for details|


### setClaimableDelay

Sets a new claimable delay for the vault

*This function can only be called by an account with the DEFAULT_ADMIN_ROLE*


```solidity
function setClaimableDelay(uint32 _newClaimableDelay) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newClaimableDelay`|`uint32`|The new delay (in seconds) before a redeem request becomes claimable.|


### setHaltStatus

Sets the halt status of the vault

*This function can only be called by an account with the DEFAULT_ADMIN_ROLE*


```solidity
function setHaltStatus(bool _newHaltStatus) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newHaltStatus`|`bool`|The new halt status to set (true for halted, false for not halted)|


### setMaxDepositPerTransaction

Sets the maximum deposit amount allowed per transaction

*This function can only be called by an account with the DEFAULT_ADMIN_ROLE*


```solidity
function setMaxDepositPerTransaction(uint128 _newMaxDepositPerTransaction) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newMaxDepositPerTransaction`|`uint128`|The new maximum deposit amount per transaction|


### setMinDepositPerTransaction

Sets the minimum deposit amount allowed per transaction

*This function can only be called by an account with the DEFAULT_ADMIN_ROLE*


```solidity
function setMinDepositPerTransaction(uint128 _newMinDepositPerTransaction) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newMinDepositPerTransaction`|`uint128`|The new minimum deposit amount per transaction|


### setMaxVaultCapacity

Sets the maximum capacity of assets that the vault can hold

*This function can only be called by an account with the DEFAULT_ADMIN_ROLE*

*The new max vault capacity must be higher than the current vaultAssets*


```solidity
function setMaxVaultCapacity(uint256 _newMaxVaultCapacity) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newMaxVaultCapacity`|`uint256`|The new maximum capacity of assets for the vault|


### setOperator

Sets or removes an operator for the caller's account

*This function allows users to designate or revoke operator privileges for their account*


```solidity
function setOperator(address _operator, bool _approved) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_operator`|`address`|The address to set as an operator or remove operator status from|
|`_approved`|`bool`|True to approve the operator, false to revoke approval|


### setRedeemFee

Sets the redeem fee for the vault

*This function can only be called by an account with the DEFAULT_ADMIN_ROLE*


```solidity
function setRedeemFee(uint16 _newRedeemFeeBasisPoints) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newRedeemFeeBasisPoints`|`uint16`|The new redeem fee in basis points (100 basis points = 1%)|


### setStrategyName

Sets a new name for the investment strategy

*This function can only be called by an account with the DEFAULT_ADMIN_ROLE*


```solidity
function setStrategyName(string memory _newStrategyName) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newStrategyName`|`string`|The new name to set for the investment strategy|


### setStrategyURI

Sets a new URI for the investment strategy

*This function can only be called by an account with the DEFAULT_ADMIN_ROLE*


```solidity
function setStrategyURI(string memory _newStrategyURI) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newStrategyURI`|`string`|The new URI to set for the investment strategy|


### setRedeemFeeCollector

Sets a new address for the redeem fee collector

*This function can only be called by an account with the DEFAULT_ADMIN_ROLE*


```solidity
function setRedeemFeeCollector(address _newRedeemFeeCollector) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newRedeemFeeCollector`|`address`|The new address to set as the redeem fee collector|


### totalAssets

Returns the total amount of assets "in" the vault - both assets in the vault for the purpose of withdraws + assets in the strategy.

*This function overrides the totalAssets function from ERC4626*

*Goes up on deposits/mints and profit reports, goes down on redeems and loss reports.*


```solidity
function totalAssets() public view override returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The total assets "in" the vault|


### maxDeposit

Returns the maximum amount of assets that can be deposited in a single transaction

*This function overrides the maxDeposit function from ERC4626*

*Returns the smaller of the maxDepositPerTransaction and the remaining vault capacity*


```solidity
function maxDeposit(address) public view override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The maximum amount of assets that can be deposited|


### maxMint

Returns the maximum amount of shares that can be minted in a single transaction

*This function overrides the maxMint function from ERC4626*

*Calculates the maximum shares by converting the maximum deposit amount to shares*


```solidity
function maxMint(address receiver) public view override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`receiver`|`address`|The address that would receive the minted shares (unused in this implementation)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The maximum amount of shares that can be minted|


### isOperator

Checks if an address is an operator for an account

*This function verifies if the given operator address has been authorized for the specified account*


```solidity
function isOperator(address account, address operator) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address of the account to check|
|`operator`|`address`|The address of the potential operator for the account.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool Returns true if the operator is authorized for the account, false otherwise|


### pendingRedeemRequest

Returns the amount of shares in a pending redeem request for a given controller

*A redeem request is considered pending if it hasn't reached the claimable delay period*


```solidity
function pendingRedeemRequest(uint256, address controller) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`||
|`controller`|`address`|The address of the request's controller|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256 The amount of shares in the pending redeem request, or 0 if no pending request exists|


### claimableRedeemRequest

Returns the amount of shares in a claimable redeem request for a given controller

*A redeem request is considered claimable if it has reached or passed the claimable delay period*


```solidity
function claimableRedeemRequest(uint256, address controller) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`||
|`controller`|`address`|The address of the request's controller|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256 The amount of shares in the claimable redeem request, or 0 if no claimable request exists|


### maxRedeem

Returns the maximum amount of shares that can be redeemed by a controller

*This function overrides the ERC4626 maxRedeem function*

*We don't have partial redeems, so the return value is either 0 or all the shares in a request.*


```solidity
function maxRedeem(address controller) public view override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`controller`|`address`|The address of the controller attempting to redeem|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256 The maximum number of shares that can be redeemed, or 0 if redemption is not possible|


### deposit

Deposits assets into the vault and mints shares to the receiver, by specifying the amount of assets.

*This function overrides the ERC4626 deposit function*

*It can only be called when the vault is not halted*


```solidity
function deposit(uint256 assets, address receiver)
    public
    override
    onlyWhenNotHalted
    nonReentrant
    returns (uint256 shares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of assets to deposit|
|`receiver`|`address`|The address that will receive the minted shares|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of shares minted|


### mint

Deposits assets into the vault and mints shares to the receiver, by specifying the amount of shares.

*This function overrides the ERC4626 mint function*

*It can only be called when the vault is not halted*


```solidity
function mint(uint256 shares, address receiver)
    public
    override
    onlyWhenNotHalted
    nonReentrant
    returns (uint256 assets);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of shares to mint|
|`receiver`|`address`|The address that will receive the minted shares|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of assets deposited|


### reportProfits

Reports profits to the vault

*This function can only be called by an account with the PNL_REPORTER_ROLE*

*Even though tokens aren't transferred to the vault, vaultAssets are increased.*


```solidity
function reportProfits(uint256 assetProfitAmount, string memory infoURI)
    external
    onlyRole(PNL_REPORTER_ROLE)
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetProfitAmount`|`uint256`|The amount of profit in asset tokens|
|`infoURI`|`string`|A URI containing additional information about the profit report|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The total amount of profits reported so far|


### reportLosses

Reports losses to the vault

*This function can only be called by an account with the PNL_REPORTER_ROLE*

*Decreases the vaultAssets by the reported loss amount*


```solidity
function reportLosses(uint256 assetLossAmount, string memory infoURI)
    external
    onlyRole(PNL_REPORTER_ROLE)
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetLossAmount`|`uint256`|The amount of loss in asset tokens|
|`infoURI`|`string`|A URI containing additional information about the loss report|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The total amount of losses reported so far|


### requestRedeem

Requests a redemption of shares

*This function can only be called when the contract is not halted*

*Caller can be any owner of shares, or an approved operator of the owner.*

*It creates a new redemption request or reverts if there's an existing request*

*Note that the exchange rate between shares and assets is fixed in the request.*


```solidity
function requestRedeem(uint256 shares, address controller, address owner)
    external
    onlyWhenNotHalted
    operatorCheck(owner)
    nonReentrant
    returns (uint8);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The number of shares to redeem|
|`controller`|`address`|The address that will control this redemption request|
|`owner`|`address`|The address that owns the shares to be redeemed|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint8`|A uint8 representing the request ID (always 0 in this implementation)|


### redeem

Redeems shares for assets, completing a previously initiated redemption request

*This function can only be called when the contract is not halted*

*Caller must be the controller of the redemption request or an approved operator*

*It processes the redemption request, burns the claimable shares, and transfers assets to the receiver*

*A redemption fee is applied to the redeemed assets.*

*The actual amount of assets transferred to the receiver will be less than the
original requested amount due to this withdrawal fee.*


```solidity
function redeem(uint256 shares, address receiver, address controller)
    public
    override
    onlyWhenNotHalted
    operatorCheck(controller)
    nonReentrant
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The number of shares to redeem (must match the original request)|
|`receiver`|`address`|The address that will receive the redeemed assets|
|`controller`|`address`|The address that controls this redemption request|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The amount of assets transferred to the receiver|


### rebalanceAssets

Rebalances assets so that the vault has enough assets, but not more, to cover all pending redemption requests

*This function can only be called by an account with the DEFAULT_ADMIN_ROLE*

*It ensures that the vault has enough assets to cover all pending redemption requests*

*If the vault has more assets than needed, it transfers the excess to the strategy*

*If the vault has less assets than needed, it transfers the necessary amount from provided address.*


```solidity
function rebalanceAssets(address sourceOfAssets) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sourceOfAssets`|`address`|The address from which to transfer additional assets if needed|


### _mintAndDepositCommon


```solidity
function _mintAndDepositCommon(uint256 assets, address receiver, uint256 shares) internal;
```

### _getClaimableShares


```solidity
function _getClaimableShares(uint256 _redeemRequestShareAmount, uint256 _redeemRequestAssetAmount)
    internal
    view
    returns (uint256);
```

### _calculateWithdrawFee


```solidity
function _calculateWithdrawFee(uint256 _redeemAssetAmount) internal view returns (uint256);
```

### previewWithdraw

*This function always reverts because the withdraw function is not available in this vault. Only redeem functionality is supported.*


```solidity
function previewWithdraw(uint256) public pure override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|This function never returns; it always reverts|


### previewRedeem

*This function always reverts because it's not possible to preview a redeem because they are async.*


```solidity
function previewRedeem(uint256) public pure override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|This function never returns; it always reverts|


### requestDeposit

*This function always reverts because this implementation does not have async deposits.*


```solidity
function requestDeposit(uint256) public pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|This function never returns; it always reverts|


### pendingDepositRequest

*This function always reverts because this implementation does not have async deposits.*


```solidity
function pendingDepositRequest(uint256, address) public pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`||
|`<none>`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|This function never returns; it always reverts|


### claimableDepositRequest

*This function always reverts because this implementation does not have async deposits.*


```solidity
function claimableDepositRequest(uint256, address) public pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`||
|`<none>`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|This function never returns; it always reverts|


### maxWithdraw

*Returns the maximum amount of assets that can be withdrawn from the vault for a given owner.*


```solidity
function maxWithdraw(address) public pure override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Always returns 0 because withdraws are not supported in this vault, only redeems are available.|


### withdraw

*This function always reverts because withdraws are not supported in this vault, only redeems are available.*


```solidity
function withdraw(uint256, address, address) public pure override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`||
|`<none>`|`address`||
|`<none>`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|This function never returns; it always reverts|


## Events
### HaltStatusChanged
Emitted when the halt status of the vault is changed


```solidity
event HaltStatusChanged(bool newStatus);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newStatus`|`bool`|The new halt status|

### ProfitReported
Emitted when profit is reported to the vault


```solidity
event ProfitReported(uint256 assetProfitAmount, string infoURI);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetProfitAmount`|`uint256`|The amount of profit reported in asset terms|
|`infoURI`|`string`|The URI containing additional information about the profit report|

### LossReported
Emitted when loss is reported to the vault


```solidity
event LossReported(uint256 assetLossAmount, string infoURI);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetLossAmount`|`uint256`|The amount of loss reported in asset terms|
|`infoURI`|`string`|The URI containing additional information about the loss report|

### MaxDepositPerTransactionSet
Emitted when the maximum deposit limit per transaction is set


```solidity
event MaxDepositPerTransactionSet(uint256 newMaxDepositPerTransaction);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newMaxDepositPerTransaction`|`uint256`|The new maximum deposit limit in asset terms|

### MinDepositSet
Emitted when the minimum deposit limit is set


```solidity
event MinDepositSet(uint256 newMinDepositPerTransaction);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newMinDepositPerTransaction`|`uint256`|The new minimum deposit limit in asset terms|

### MaxVaultCapacitySet
Emitted when the maximum vault capacity is set


```solidity
event MaxVaultCapacitySet(uint256 newMaxVaultCapacity);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newMaxVaultCapacity`|`uint256`|The new maximum vault capacity in asset terms|

### OperatorSet
Emitted when an operator's status is set


```solidity
event OperatorSet(address indexed caller, address indexed operator, bool approved);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`caller`|`address`|The address that is giving operator status to the operator|
|`operator`|`address`|The address of the operator, the account being given an operator status for the caller.|
|`approved`|`bool`|The new approval status of the operator|

### RedeemRequest
Emitted when a redeem request is made


```solidity
event RedeemRequest(
    address indexed caller, address indexed controller, address indexed owner, uint256 shares, uint256 assets
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`caller`|`address`|The address that initiated the redeem request|
|`controller`|`address`|The address that will control the redeem request|
|`owner`|`address`|The address that owned the shares being redeemed|
|`shares`|`uint256`|The amount of shares to be redeemed|
|`assets`|`uint256`|The amount of assets to be redeemed, converted from the shares at the current exchange rate.|

### RedeemFeeSet
Emitted when the redeem fee is set


```solidity
event RedeemFeeSet(uint16 newRedeemFee);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newRedeemFee`|`uint16`|The new redeem fee|

### ClaimableDelaySet
Emitted when the claimable delay is set


```solidity
event ClaimableDelaySet(uint32 newClaimableDelay);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newClaimableDelay`|`uint32`|The new claimable delay value in seconds|

### StrategyNameSet
Emitted when the strategy name is updated


```solidity
event StrategyNameSet(string newStrategyName);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newStrategyName`|`string`|The new name of the strategy|

### StrategyURISet
Emitted when the strategy URI is updated


```solidity
event StrategyURISet(string newStrategyURI);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newStrategyURI`|`string`|The new URI of the strategy|

### RedeemFeeCollectorSet
Emitted when the redeem fee collector address is updated


```solidity
event RedeemFeeCollectorSet(address newRedeemFeeCollector);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newRedeemFeeCollector`|`address`|The new address of the redeem fee collector|

### AssetsRebalanced
Emitted when assets are rebalanced between the vault and the strategy


```solidity
event AssetsRebalanced(uint256 assetInflow, uint256 assetOutflow);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assetInflow`|`uint256`|The amount of assets transferred into the vault|
|`assetOutflow`|`uint256`|The amount of assets transferred out of the vault to the strategy|

## Errors
### Halted
Error thrown when an operation is attempted while the vault is halted

*This error is used to prevent certain actions when the vault is in a halted state*


```solidity
error Halted();
```

### ZeroShares
Error thrown when trying to deposit assets worth 0 shares

*Deposits must result in a non-zero amount of shares*


```solidity
error ZeroShares();
```

### ZeroAssets
Error thrown when trying to redeem shares that equal zero assets

*Withdrawals must result in a non-zero amount of assets*


```solidity
error ZeroAssets();
```

### ZeroAddress
Error thrown when an input address is the zero address

*Addresses must be non-zero*


```solidity
error ZeroAddress();
```

### InvalidMaxDepositPerTransaction
Error thrown when an invalid max deposit per transaction amount has been attempted to be set

*The maximum deposit per transaction amount must be valid according to vault rules*


```solidity
error InvalidMaxDepositPerTransaction();
```

### InvalidMinDepositPerTransaction
Error thrown when an invalid min deposit amount per transaction has been attempted to be set

*The minimum deposit per transaction amount must be valid according to vault rules*


```solidity
error InvalidMinDepositPerTransaction();
```

### InvalidMaxVaultCapacity
Error thrown when an invalid max vault capacity has been attempted to be set

*The maximum vault capacity must be valid according to vault rules*


```solidity
error InvalidMaxVaultCapacity();
```

### ExceedsMaxVaultCapacity
Error thrown when assets are attempted to be added that would exceed the max vault capacity

*The total assets in the vault must not exceed the maximum capacity*


```solidity
error ExceedsMaxVaultCapacity();
```

### InvalidDepositAmount
Error thrown when an invalid deposit amount is provided

*This error is used when the deposit amount is outside the allowed range for a deposit transaction*


```solidity
error InvalidDepositAmount(uint256 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|The invalid deposit amount that was provided|

### Unauthorized
Generic error thrown when the caller isn't authorized to do an action

*This is particularly used for checking operator permissions*


```solidity
error Unauthorized();
```

### ExistingRedeemRequest
Error thrown when a user tries to create a redeem request when there is an existing one already

*A user can only have one active redeem request at a time*


```solidity
error ExistingRedeemRequest();
```

### NonexistentRedeemRequest
Error thrown when a user tries to redeem a request that doesn't exist

*A redeem request must exist before it can be processed*


```solidity
error NonexistentRedeemRequest();
```

### NonClaimableRedeemRequest
Error thrown when a user tries to redeem a request that is not yet claimable

*A redeem request must wait for the claimable delay before it can be processed*


```solidity
error NonClaimableRedeemRequest();
```

### ShareAmountDiscrepancy
Error thrown during a redeem when input and request shares don't match

*This is a safety check to ensure the correct amount of shares are being redeemed*


```solidity
error ShareAmountDiscrepancy();
```

### NotAvailableInAsyncRedeemVault
Error thrown when someone tries to do an operation not available in a vault that does async redeems, such as this one. Deposits are still synchronous.

*Async deposits are not supported in this vault implementation*


```solidity
error NotAvailableInAsyncRedeemVault();
```

### InvalidRedeemFee
Error thrown when an invalid redeem fee has been attempted to be set

*The redeem fee must be between 0 and 10000 basis points (0% to 100%)*


```solidity
error InvalidRedeemFee();
```

### InvalidStrategyType
Error thrown when an invalid strategy type has been provided

*The strategy type must be a valid enum value in StrategyAddressType (0 to 3)*


```solidity
error InvalidStrategyType();
```

### HaltStatusUnchanged
Error thrown when attempting to change the halt status to its current value

*This error is used to prevent unnecessary state changes and gas costs*

*It's thrown when calling setHaltStatus() with a value that matches the current halted state*


```solidity
error HaltStatusUnchanged();
```

### ERC20TransferFailed
Error thrown when an ERC20 token transfer fails

*This error is used when a transfer or transferFrom operation on the underlying ERC20 asset fails*

*It can occur during any operation involving token transfers*


```solidity
error ERC20TransferFailed();
```

### LossExceedsVaultAssets
Error thrown when reported losses exceed the total assets in the vault

*This error is used to prevent the vault's asset balance from causing an underflow.*

*It's thrown in the reportLosses function if the reported loss amount is greater than the current vaultAssets*


```solidity
error LossExceedsVaultAssets();
```

## Structs
### InvestmentStrategy
Struct representing an investment strategy

*This struct contains all the necessary information about a strategy*


```solidity
struct InvestmentStrategy {
    address strategyAddress;
    StrategyAddressType strategyAddressType;
    string strategyURI;
    string strategyName;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`strategyAddress`|`address`|The address where the funds will be sent to for the strategy|
|`strategyAddressType`|`StrategyAddressType`|The type of address according to the StrategyAddressType enum|
|`strategyURI`|`string`|A URI that explains the strategy in detail|
|`strategyName`|`string`|The name of the strategy|

### RedeemRequestData
Struct representing a redemption request

*This struct contains all the necessary information about a user's redemption request*


```solidity
struct RedeemRequestData {
    uint256 redeemRequestShareAmount;
    uint256 redeemRequestAssetAmount;
    uint96 redeemRequestCreationTime;
    address originalSharesOwner;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`redeemRequestShareAmount`|`uint256`|The number of shares requested to be redeemed|
|`redeemRequestAssetAmount`|`uint256`|The converted number of assets to be redeemed (exchange rate frozen at request time)|
|`redeemRequestCreationTime`|`uint96`|Timestamp of the redemption request|
|`originalSharesOwner`|`address`|The address that originally owned the shares being redeemed|

### ConstructorParams
Struct containing parameters for initializing the vault


```solidity
struct ConstructorParams {
    address asset;
    uint16 redeemFeeBasisPoints;
    uint32 claimableDelay;
    uint8 strategyType;
    address strategyAddress;
    address redeemFeeCollector;
    address pnlReporter;
    uint128 maxDepositPerTransaction;
    uint128 minDepositPerTransaction;
    uint256 maxVaultCapacity;
    string strategyName;
    string strategyURI;
    string vaultSharesName;
    string vaultSharesSymbol;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`asset`|`address`|The address of the underlying asset token|
|`redeemFeeBasisPoints`|`uint16`|The fee charged on redeems, in basis points, on assets redeemed|
|`claimableDelay`|`uint32`|The minimum delay between creating a redemption request and when it can be processed|
|`strategyType`|`uint8`|The type of strategy address (0: EOA, 1: MULTISIG, 2: SMARTCONTRACT, 3: CEXDEPOSIT)|
|`strategyAddress`|`address`|The address where the strategy funds will be sent|
|`redeemFeeCollector`|`address`|The address where redeem fees are sent on redeems|
|`pnlReporter`|`address`|The address granted the PNL_REPORTER_ROLE|
|`maxDepositPerTransaction`|`uint128`|The maximum amount of assets that can be deposited by a user per transaction|
|`minDepositPerTransaction`|`uint128`|The minimum amount of assets that need to be deposited by a user per transaction|
|`maxVaultCapacity`|`uint256`|The maximum amount of assets the vault can hold in total|
|`strategyName`|`string`|The name of the investment strategy|
|`strategyURI`|`string`|A URI that explains the strategy in detail|
|`vaultSharesName`|`string`|The name of the vault shares token|
|`vaultSharesSymbol`|`string`|The symbol of the vault shares token|

## Enums
### StrategyAddressType
Enum representing different types of addresses where the investment strategy funds are sent

*This enum is used to categorize the strategy address in the InvestmentStrategy struct*


```solidity
enum StrategyAddressType {
    EOA,
    MULTISIG,
    SMARTCONTRACT,
    CEXDEPOSIT
}
```

