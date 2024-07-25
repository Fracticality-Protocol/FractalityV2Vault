// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/AccessControl.sol";
//This reentrancy guard is from the master branch of openzeppelin, that uses transient storage.
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@solmate/tokens/ERC4626.sol";

import "@solmate/tokens/ERC20.sol";

contract FractalityV2Vault is AccessControl, ERC4626, ReentrancyGuard {
    /*
    ROLES
    */

    /// @notice Role that allows reporting of profits and losses
    /// @dev This role is responsible for updating the vault's financial status due to the strategy's performance
    bytes32 public constant PNL_REPORTER_ROLE = keccak256("PNL_REPORTER_ROLE");

    /*
    TYPE DEFINITIONS
    */

    /// @notice Enum representing different types of addresses where the investment strategy funds are sent
    /// @dev This enum is used to categorize the strategy address in the InvestmentStrategy struct
    /// @param EOA Externally Owned Account, representing a normal wallet (e.g., MetaMask, Ledger)
    /// @param MULTISIG Multi-signature wallet (e.g., Gnosis Safe)
    /// @param SMARTCONTRACT Smart contract address
    /// @param CEXDEPOSIT Deposit address on a centralized exchange
    enum StrategyAddressType {
        EOA,
        MULTISIG,
        SMARTCONTRACT,
        CEXDEPOSIT
    }

    /// @notice Struct representing an investment strategy
    /// @dev This struct contains all the necessary information about a strategy
    /// @param strategyAddress The address where the funds will be sent to for the strategy
    /// @param strategyAddressType The type of address according to the StrategyAddressType enum
    /// @param strategyURI A URI that explains the strategy in detail
    /// @param strategyName The name of the strategy
    struct InvestmentStrategy {
        address strategyAddress;//256 -> slot
        StrategyAddressType strategyAddressType;//256 -> slot
        string strategyURI;//256 -> slot
        string strategyName;//256 -> slot
    }

    /// @notice Struct representing a redemption request
    /// @dev This struct contains all the necessary information about a user's redemption request
    /// @param redeemRequestShareAmount The number of shares requested to be redeemed
    /// @param redeemRequestAssetAmount The converted number of assets to be redeemed (exchange rate frozen at request time)
    /// @param redeemRequestCreationTime Timestamp of the redemption request
    /// @param originalSharesOwner The address that originally owned the shares being redeemed
    struct RedeemRequestData {
        uint256 redeemRequestShareAmount;//256 -> slot
        uint256 redeemRequestAssetAmount;//256 -> slot
        uint96 redeemRequestCreationTime;//96 
        address originalSharesOwner;//160 -> slot
    }

    /// @notice Struct containing parameters for initializing the vault
    /// @param asset The address of the underlying asset token
    /// @param vaultSharesName The name of the vault shares token
    /// @param vaultSharesSymbol The symbol of the vault shares token
    /// @param strategyAddress The address where the strategy funds will be sent
    /// @param strategyName The name of the investment strategy
    /// @param strategyURI A URI that explains the strategy in detail
    /// @param strategyType The type of strategy address (0: EOA, 1: MULTISIG, 2: SMARTCONTRACT, 3: CEXDEPOSIT)
    /// @param maxDepositPerTransaction The maximum amount of assets that can be deposited by a user per transaction
    /// @param minDepositPerTransaction The minimum amount of assets that need to be deposited by a user per transaction
    /// @param maxVaultCapacity The maximum amount of assets the vault can hold in total
    /// @param redeemFeeBasisPoints The fee charged on redeems, in basis points, on assets redeemed
    /// @param claimableDelay The minimum delay between creating a redemption request and when it can be processed
    /// @param redeemFeeCollector The address where redeem fees are sent on redeems
    /// @param pnlReporter The address granted the PNL_REPORTER_ROLE
    struct ConstructorParams {
        address asset;//160
        uint16 redeemFeeBasisPoints;//16
        uint32 claimableDelay;//32
        uint8 strategyType;//8 -> slot
        address strategyAddress;//160 -> slot
        address redeemFeeCollector;//160 -> slot
        address pnlReporter;//160 -> slot
        uint128 maxDepositPerTransaction;//128
        uint128 minDepositPerTransaction;//128 -> slot
        uint256 maxVaultCapacity;//256 -> slot
        string strategyName;//256 -> slot
        string strategyURI;//256 -> slot
        string vaultSharesName;//256 -> slot
        string vaultSharesSymbol;//256 -> slot
    }

    /*
    STATE VARIABLES
    */

    /// @notice The investment strategy currently employed by this vault
    /// @dev This strategy defines where and how all the funds in the vault will be invested
    InvestmentStrategy public strategy;

    //look into struct packing for some of these "loose" vars

    /// @notice Total number of shares currently in the redemption process
    /// @dev These shares are no longer in the custody of users but are held by the vault during redemption
    /// @dev This value represents the sum of all shares that have been requested for redemption but not yet processed
    uint256 public totalSharesInRedemptionProcess;

    /// @notice Total sum of all historical profits reported by the PNL_REPORTER_ROLE admin.
    /// @dev This variable accumulates all profits reported over time, providing a historical record of the vault's performance
    uint256 public totalProfitsReported;

    /// @notice Total sum of all historical losses reported by the PNL_REPORTER_ROLE admin.
    /// @dev This variable accumulates all losses reported over time, providing a historical record of the vault's negative performance
    uint256 public totalLossesReported;

    /// @notice Total value of assets currently in the redemption process
    /// @dev This represents the sum of all assets (converted from shares at their respective exchange rates at request time) that are currently being redeemed
    /// @dev It's important to note that this sum was made with different exchange rates, so it's not safe to convert back to shares using the current exchange rate.
    uint256 public totalAssetsInRedemptionProcess;

    //Next 2 vars are in one slot.

    /// @notice The minimum amount of assets that need to be deposited by a user per deposit transaction
    /// @dev This value sets the lower limit for deposits to prevent dust amounts and prevent truncation errors.
    /// @dev Attempts to deposit less than this amount will be rejected
    uint128 public minDepositPerTransaction;

    /// @notice The maximum amount of assets that can be deposited by a user per deposit transaction
    /// @dev This value sets the upper limit for deposits to prevent overflows and prevent truncation errors.
    /// @dev Attempts to deposit more than this amount will be rejected
    uint128 public maxDepositPerTransaction;

    /// @notice The maximum amount of assets that the vault can hold
    /// @dev This value sets the upper limit for the total assets in the vault
    /// @dev Deposits that would cause the total assets to exceed this limit will be rejected
    uint256 public maxVaultCapacity;

    /// @notice The abstract representation of the total assets in the vault
    /// @dev This value represents the assets in the vault, although the actual assets are held in the strategy
    /// @dev Increases with deposits and profit reporting, decreases with redeems and loss reporting
    /// @dev Note: This is an abstract representation as the actual assets are managed by the strategy
    uint256 public vaultAssets;

    //Next 5 vars are in one slot.

    /// @notice The address where redeem fees are sent
    /// @dev This address receives the assets collected from the redeem fee
    address public redeemFeeCollector;

    /// @notice Indicates whether the vault operations are halted
    /// @dev When true, certain operations in the vault cannot be performed
    /// @dev This is typically used in emergency situations or during maintenance
    bool public halted;

    /// @notice The maximum number of basis points
    /// @dev This constant represents 100% in basis points (100% = 10000 basis points)
    /// @dev Used as a denominator in percentage calculations during redeem fee calculation.
    uint16 private constant _maxBasisPoints = 10000;

    /// @notice The fee charged on redeems, expressed in basis points
    /// @dev 100 basis points = 1%. For example, a value of 20 represents a 0.2% fee
    /// @dev This fee is deducted from the assets at the time of redeem
    uint16 public redeemFeeBasisPoints;

    /// @notice The minimum delay between creating a redemption request and when it can be processed
    /// @dev This value is in seconds and represents the mandatory waiting period for redemption requests
    /// @dev Users must wait at least this long after creating a request before it can be processed
    uint32 public claimableDelay;

    /*
    MAPPINGS
    */

    /// @notice Mapping of user addresses to their redeem requests
    /// @dev This mapping holds redeem requests per user. Only one active redeem request per user is allowed.
    /// @dev The key is the user's address, and the value is a RedeemRequest struct containing the request details.
    mapping(address => RedeemRequestData) public redeemRequests;

    /// @notice Mapping of operator permissions
    /// @dev This double mapping represents the operator status of an address, for another address
    /// @dev The first address is the account giving operator status to the second address
    /// @dev The second address is the operator being granted permissions
    /// @dev The boolean value indicates whether the operator status is active (true) or not (false)
    /// @dev This is used in several functions to allow delegation of certain actions
    mapping(address => mapping(address => bool)) public operators;

    /*
    CUSTOM EVENTS  
    */

    /// @notice Emitted when the halt status of the vault is changed
    /// @param newStatus The new halt status
    event HaltStatusChanged(bool newStatus);

    /// @notice Emitted when profit is reported to the vault
    /// @param assetProfitAmount The amount of profit reported in asset terms
    /// @param infoURI The URI containing additional information about the profit report
    event ProfitReported(uint256 assetProfitAmount, string infoURI);

    /// @notice Emitted when loss is reported to the vault
    /// @param assetLossAmount The amount of loss reported in asset terms
    /// @param infoURI The URI containing additional information about the loss report
    event LossReported(uint256 assetLossAmount, string infoURI);

    /// @notice Emitted when the maximum deposit limit per transaction is set
    /// @param newMaxDepositPerTransaction The new maximum deposit limit in asset terms
    event MaxDepositPerTransactionSet(uint256 newMaxDepositPerTransaction);

    /// @notice Emitted when the minimum deposit limit is set
    /// @param newMinDepositPerTransaction The new minimum deposit limit in asset terms
    event MinDepositSet(uint256 newMinDepositPerTransaction);

    /// @notice Emitted when the maximum vault capacity is set
    /// @param newMaxVaultCapacity The new maximum vault capacity in asset terms
    event MaxVaultCapacitySet(uint256 newMaxVaultCapacity);

    /// @notice Emitted when an operator's status is set
    /// @param caller The address that is giving operator status to the operator
    /// @param operator The address of the operator, the account being given an operator status for the caller.
    /// @param approved The new approval status of the operator
    event OperatorSet(
        address indexed caller,
        address indexed operator,
        bool approved
    );

    /// @notice Emitted when a redeem request is made
    /// @param caller The address that initiated the redeem request
    /// @param controller The address that will control the redeem request
    /// @param owner The address that owned the shares being redeemed
    /// @param shares The amount of shares to be redeemed
    /// @param assets The amount of assets to be redeemed, converted from the shares at the current exchange rate.
    event RedeemRequest(
        address indexed caller,
        address indexed controller,
        address indexed owner,
        uint256 shares,
        uint256 assets
    );

    /// @notice Emitted when the redeem fee is set
    /// @param newRedeemFee The new redeem fee
    event RedeemFeeSet(uint16 newRedeemFee);

    /// @notice Emitted when the claimable delay is set
    /// @param newClaimableDelay The new claimable delay value in seconds
    event ClaimableDelaySet(uint32 newClaimableDelay);

    /// @notice Emitted when the strategy name is updated
    /// @param newStrategyName The new name of the strategy
    event StrategyNameSet(string newStrategyName);

    /// @notice Emitted when the strategy URI is updated
    /// @param newStrategyURI The new URI of the strategy
    event StrategyURISet(string newStrategyURI);

    /// @notice Emitted when the redeem fee collector address is updated
    /// @param newRedeemFeeCollector The new address of the redeem fee collector
    event RedeemFeeCollectorSet(address newRedeemFeeCollector);

    /// @notice Emitted when assets are rebalanced between the vault and the strategy
    /// @param assetInflow The amount of assets transferred into the vault
    /// @param assetOutflow The amount of assets transferred out of the vault to the strategy
    event AssetsRebalanced(uint256 assetInflow, uint256 assetOutflow);

    /*
    ERRORS  
    */

    /// @notice Error thrown when an operation is attempted while the vault is halted
    /// @dev This error is used to prevent certain actions when the vault is in a halted state
    error Halted();

    /// @notice Error thrown when trying to deposit assets worth 0 shares
    /// @dev Deposits must result in a non-zero amount of shares
    error ZeroShares();

    /// @notice Error thrown when trying to redeem shares that equal zero assets
    /// @dev Withdrawals must result in a non-zero amount of assets
    error ZeroAssets();

    /// @notice Error thrown when an input address is the zero address
    /// @dev Addresses must be non-zero
    error ZeroAddress();

    /// @notice Error thrown when an invalid max deposit per transaction amount has been attempted to be set
    /// @dev The maximum deposit per transaction amount must be valid according to vault rules
    error InvalidMaxDepositPerTransaction();

    /// @notice Error thrown when an invalid min deposit amount per transaction has been attempted to be set
    /// @dev The minimum deposit per transaction amount must be valid according to vault rules
    error InvalidMinDepositPerTransaction();

    /// @notice Error thrown when an invalid max vault capacity has been attempted to be set
    /// @dev The maximum vault capacity must be valid according to vault rules
    error InvalidMaxVaultCapacity();

    /// @notice Error thrown when assets are attempted to be added that would exceed the max vault capacity
    /// @dev The total assets in the vault must not exceed the maximum capacity
    error ExceedsMaxVaultCapacity();

    /// @notice Error thrown when an invalid deposit amount is provided
    /// @dev This error is used when the deposit amount is outside the allowed range for a deposit transaction
    /// @param amount The invalid deposit amount that was provided
    error InvalidDepositAmount(uint256 amount);

    /// @notice Generic error thrown when the caller isn't authorized to do an action
    /// @dev This is particularly used for checking operator permissions
    error Unauthorized();

    /// @notice Error thrown when a user tries to create a redeem request when there is an existing one already
    /// @dev A user can only have one active redeem request at a time
    error ExistingRedeemRequest();

    /// @notice Error thrown when a user tries to redeem a request that doesn't exist
    /// @dev A redeem request must exist before it can be processed
    error NonexistentRedeemRequest();

    /// @notice Error thrown when a user tries to redeem a request that is not yet claimable
    /// @dev A redeem request must wait for the claimable delay before it can be processed
    error NonClaimableRedeemRequest();

    /// @notice Error thrown during a redeem when input and request shares don't match
    /// @dev This is a safety check to ensure the correct amount of shares are being redeemed
    error ShareAmountDiscrepancy();

    /// @notice Error thrown when someone tries to do an operation not available in a vault that does async redeems, such as this one. Deposits are still synchronous.
    /// @dev Async deposits are not supported in this vault implementation
    error NotAvailableInAsyncRedeemVault();

    /// @notice Error thrown when an invalid redeem fee has been attempted to be set
    /// @dev The redeem fee must be between 0 and 10000 basis points (0% to 100%)
    error InvalidRedeemFee();

    /// @notice Error thrown when an invalid strategy type has been provided
    /// @dev The strategy type must be a valid enum value in StrategyAddressType (0 to 3)
    error InvalidStrategyType();

    /// @notice Error thrown when attempting to change the halt status to its current value
    /// @dev This error is used to prevent unnecessary state changes and gas costs
    /// @dev It's thrown when calling setHaltStatus() with a value that matches the current halted state
    error HaltStatusUnchanged();

    /// @notice Error thrown when an ERC20 token transfer fails
    /// @dev This error is used when a transfer or transferFrom operation on the underlying ERC20 asset fails
    /// @dev It can occur during any operation involving token transfers
    error ERC20TransferFailed();

    /// @notice Error thrown when reported losses exceed the total assets in the vault
    /// @dev This error is used to prevent the vault's asset balance from causing an underflow.
    /// @dev It's thrown in the reportLosses function if the reported loss amount is greater than the current vaultAssets
    error LossExceedsVaultAssets();

    /*
    Modifiers
    */
    modifier onlyWhenNotHalted() {
        if (halted) {
            revert Halted();
        }
        _;
    }

    modifier operatorCheck(address user) {
        if (msg.sender != user && !isOperator(user, msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    /*
    CONSTRUCTOR AND SETTERS  
    */
    /// @notice Initializes the vault with the provided parameters
    /// @dev Sets up the vault's configuration, strategy, and initial roles
    /// @param params A struct containing all necessary initialization parameters, see ConstructorParams for details
    constructor(
        ConstructorParams memory params
    )
        ERC4626(
            ERC20(params.asset),
            params.vaultSharesName,
            params.vaultSharesSymbol
        )
        AccessControl()
    {
        if (
            params.asset == address(0) ||
            params.strategyAddress == address(0) ||
            params.pnlReporter == address(0) ||
            params.redeemFeeCollector == address(0)
        ) {
            revert ZeroAddress();
        }
        if (params.minDepositPerTransaction > params.maxDepositPerTransaction) {
            revert InvalidMinDepositPerTransaction();
        }
        if (params.maxVaultCapacity == 0) {
            revert InvalidMaxVaultCapacity();
        }
        if (params.redeemFeeBasisPoints > _maxBasisPoints) {
            revert InvalidRedeemFee();
        }
        if (params.strategyType > 3) {
            revert InvalidStrategyType();
        }

        strategy = InvestmentStrategy(
            params.strategyAddress,
            StrategyAddressType(params.strategyType),
            params.strategyURI,
            params.strategyName
        );

        maxDepositPerTransaction = params.maxDepositPerTransaction;
        minDepositPerTransaction = params.minDepositPerTransaction;
        maxVaultCapacity = params.maxVaultCapacity;
        redeemFeeBasisPoints = params.redeemFeeBasisPoints;
        claimableDelay = params.claimableDelay;

        redeemFeeCollector = params.redeemFeeCollector;
        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(PNL_REPORTER_ROLE, params.pnlReporter);
    }

    function setClaimableDelay(
        uint32 _newClaimableDelay
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        claimableDelay = _newClaimableDelay;
        emit ClaimableDelaySet(_newClaimableDelay);
    }

    function setHaltStatus(
        bool _newHaltStatus
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (halted == _newHaltStatus) {
            revert HaltStatusUnchanged();
        }
        halted = _newHaltStatus;
        emit HaltStatusChanged(_newHaltStatus);
    }

    function setMaxDepositPerTransaction(
        uint128 _newMaxDepositPerTransaction
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newMaxDepositPerTransaction < minDepositPerTransaction) {
            revert InvalidMaxDepositPerTransaction();
        }
        maxDepositPerTransaction = _newMaxDepositPerTransaction;
        emit MaxDepositPerTransactionSet(_newMaxDepositPerTransaction);
    }

    function setMinDepositPerTransaction(
        uint128 _newMinDepositPertransaction
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newMinDepositPertransaction > maxDepositPerTransaction) {
            revert InvalidMinDepositPerTransaction();
        }
        minDepositPerTransaction = _newMinDepositPertransaction;
        emit MinDepositSet(_newMinDepositPertransaction);
    }

    function setMaxVaultCapacity(
        uint256 _newMaxVaultCapacity
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newMaxVaultCapacity < vaultAssets) {
            revert InvalidMaxVaultCapacity();
        }
        maxVaultCapacity = _newMaxVaultCapacity;
        emit MaxVaultCapacitySet(_newMaxVaultCapacity);
    }

    function setOperator(address _operator, bool _approved) external {
        if (_operator == address(0)) {
            revert ZeroAddress();
        }
        operators[msg.sender][_operator] = _approved;
        emit OperatorSet(msg.sender, _operator, _approved);
    }

    function setRedeemFee(
        uint16 _newRedeemFeeBasisPoints
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        redeemFeeBasisPoints = _newRedeemFeeBasisPoints;
        emit RedeemFeeSet(_newRedeemFeeBasisPoints);
    }

    function setStrategyName(
        string memory _newStrategyName
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategy.strategyName = _newStrategyName;
        emit StrategyNameSet(_newStrategyName);
    }

    function setStrategyURI(
        string memory _newStrategyURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategy.strategyURI = _newStrategyURI;
        emit StrategyURISet(_newStrategyURI);
    }

    function setRedeemFeeCollector(
        address _newRedeemFeeCollector
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newRedeemFeeCollector == address(0)) {
            revert ZeroAddress();
        }
        redeemFeeCollector = _newRedeemFeeCollector;
        emit RedeemFeeCollectorSet(_newRedeemFeeCollector);
    }

    /*
        GETTERS AND VIEW FUNCTIONS
    */

    function totalAssets() public view override returns (uint256) {
        return vaultAssets;
    }

    function maxDeposit(
        address /*receiver*/
    ) public view override returns (uint256) {
        uint256 remainingCapacity = maxVaultCapacity - vaultAssets;
        return
            remainingCapacity < maxDepositPerTransaction
                ? remainingCapacity
                : maxDepositPerTransaction;
    }

    function maxMint(address receiver) public view override returns (uint256) {
        return convertToShares(maxDeposit(receiver));
    }

    function isOperator(
        address account,
        address operator
    ) public view returns (bool) {
        return operators[account][operator];
    }

    function pendingRedeemRequest(
        uint /*requestId*/,
        address controller
    ) public view returns (uint256) {
        RedeemRequestData memory request = redeemRequests[controller];
        if (request.redeemRequestCreationTime == 0) {
            return 0; //No request request exists
        }

        if (
            block.timestamp < request.redeemRequestCreationTime + claimableDelay
        ) {
            return request.redeemRequestShareAmount;
        } else {
            return 0; //Request is not pending, it is claimable.
        }
    }

    function claimableRedeemRequest(
        uint /*requestId*/,
        address controller
    ) public view returns (uint256) {
        RedeemRequestData memory request = redeemRequests[controller];
        if (request.redeemRequestCreationTime == 0) {
            return 0; //No request request exists
        }

        if (
            block.timestamp < request.redeemRequestCreationTime + claimableDelay
        ) {
            return 0; //Request is still pending, not claimable
        } else {
            return _getClaimableShares(request.redeemRequestShareAmount);
        }
    }

    function maxRedeem(
        address controller
    ) public view override returns (uint256) {
        if (halted) {
            return 0; //cannot redeem while halted
        }
        RedeemRequestData memory request = redeemRequests[controller];

        if (request.redeemRequestCreationTime == 0) {
            return 0; //No request request exists
        }

        if (
            block.timestamp < request.redeemRequestCreationTime + claimableDelay
        ) {
            return 0; //Request is still pending, not claimable
        }

        return _getClaimableShares(request.redeemRequestShareAmount);
    }

      function _mintAndDepositCommon(uint256 assets, address receiver,uint256 shares) internal {
        if (shares == 0) {
            revert ZeroShares();
        }
        if (
            assets < minDepositPerTransaction ||
            assets > maxDepositPerTransaction
        ) {
            revert InvalidDepositAmount(assets);
        }

        if (assets + vaultAssets > maxVaultCapacity) {
            revert ExceedsMaxVaultCapacity();
        }
        vaultAssets += assets;
        _mint(receiver, shares);
        if (!asset.transferFrom(msg.sender, strategy.strategyAddress, assets)) {
            revert ERC20TransferFailed();
        }
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function _getClaimableShares(
        uint256 _redeemRequestShareAmount
    ) internal view returns (uint256) {
        uint256 sharesInVault = convertToShares(asset.balanceOf(address(this)));
        if (sharesInVault < _redeemRequestShareAmount) {
            return 0; //Not enough shares in the vault to cover the request
        } else {
            return _redeemRequestShareAmount;
        }
    }

    function _calculateWithdrawFee(
        uint256 _redeemAssetAmount
    ) internal view returns (uint256) {
        return (_redeemAssetAmount * redeemFeeBasisPoints) / _maxBasisPoints;
    }

    /*
    MAIN OPERATIONAL FUNCTIONS
    */

    function deposit(
        uint256 assets,
        address receiver
    ) public override onlyWhenNotHalted nonReentrant returns (uint256 shares) {
        shares = previewDeposit(assets);
        _mintAndDepositCommon(assets, receiver, shares);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public override onlyWhenNotHalted nonReentrant returns (uint256 assets) {
        assets = previewMint(shares);
        _mintAndDepositCommon(assets, receiver, shares);
    }


    function reportProfits(
        uint256 assetProfitAmount,
        string memory infoURI
    ) external onlyRole(PNL_REPORTER_ROLE) returns (uint256) {
        if (assetProfitAmount + vaultAssets > maxVaultCapacity) {
            revert ExceedsMaxVaultCapacity();
        }

        vaultAssets += assetProfitAmount;
        totalProfitsReported += assetProfitAmount;
        emit ProfitReported(assetProfitAmount, infoURI);
        return totalProfitsReported;
    }

    function reportLosses(
        uint256 assetLossAmount,
        string memory infoURI
    ) external onlyRole(PNL_REPORTER_ROLE) returns (uint256) {
        if (assetLossAmount > vaultAssets) {
            revert LossExceedsVaultAssets();
        }

        vaultAssets -= assetLossAmount;
        totalLossesReported += assetLossAmount;
        emit LossReported(assetLossAmount, infoURI);
        return totalLossesReported;
    }

    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    )
        external
        onlyWhenNotHalted
        operatorCheck(owner)
        nonReentrant
        returns (uint8)
    {
        if (controller == address(0) || owner == address(0)) {
            revert ZeroAddress();
        }
        uint256 assets = convertToAssets(shares);
        if (assets == 0) {
            revert ZeroAssets();
        }

        RedeemRequestData storage request = redeemRequests[controller];

        if (request.redeemRequestCreationTime > 0) {
            revert ExistingRedeemRequest();
        }

        request.redeemRequestShareAmount = shares;
        request.redeemRequestAssetAmount = assets;
        request.redeemRequestCreationTime = uint96(block.timestamp);
        request.originalSharesOwner = owner;

        totalAssetsInRedemptionProcess += assets;
        totalSharesInRedemptionProcess += shares;

        if (!transferFrom(owner, address(this), shares)) {
            revert ERC20TransferFailed();
        }

        emit RedeemRequest(msg.sender, controller, owner, shares, assets);

        return 0; // Request id, always since we only have 1 request per user at a time.
    }

    function redeem(
        uint256 shares,
        address receiver,
        address controller
    )
        public
        override
        onlyWhenNotHalted
        operatorCheck(controller)
        nonReentrant
        returns (uint256)
    {
        if (receiver == address(0) || controller == address(0)) {
            revert ZeroAddress();
        }
        RedeemRequestData memory request = redeemRequests[controller];

        if (request.redeemRequestCreationTime == 0) {
            revert NonexistentRedeemRequest();
        }

        if (request.redeemRequestShareAmount != shares) {
            revert ShareAmountDiscrepancy();
        }
        uint256 claimableShares = _getClaimableShares(
            request.redeemRequestShareAmount
        );
        if (
            block.timestamp <
            request.redeemRequestCreationTime + claimableDelay ||
            claimableShares == 0
        ) {
            revert NonClaimableRedeemRequest();
        }
        _burn(address(this), claimableShares);

        totalAssetsInRedemptionProcess -= request.redeemRequestAssetAmount;
        vaultAssets -= request.redeemRequestAssetAmount;
        totalSharesInRedemptionProcess -= request.redeemRequestShareAmount;

        delete redeemRequests[controller];

        //calculat withdraw fee

        uint256 withdrawFee = _calculateWithdrawFee(
            request.redeemRequestAssetAmount
        );
        uint256 netAssetRedeemAmount = request.redeemRequestAssetAmount -
            withdrawFee;

        if (
            !asset.transfer(redeemFeeCollector, withdrawFee) ||
            !asset.transfer(receiver, netAssetRedeemAmount)
        ) {
            revert ERC20TransferFailed();
        }

        emit Withdraw(
            msg.sender,
            receiver,
            request.originalSharesOwner,
            request.redeemRequestAssetAmount,
            shares
        );

        return netAssetRedeemAmount;
    }

    function rebalanceAssets(address sourceOfAssets) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE){
        if(sourceOfAssets == address(0)){
            revert ZeroAddress();
        }
        uint256 assetVaultBalance=asset.balanceOf(address(this));
        if(totalAssetsInRedemptionProcess > assetVaultBalance){
            uint256 inflow = totalAssetsInRedemptionProcess - assetVaultBalance;
            if(!asset.transferFrom(sourceOfAssets, address(this), inflow)){
                revert ERC20TransferFailed();
            }
            emit AssetsRebalanced(inflow,0);
        }else if(totalAssetsInRedemptionProcess < assetVaultBalance){
            uint256 outflow = assetVaultBalance - totalAssetsInRedemptionProcess;
            if(!asset.transfer(strategy.strategyAddress, outflow)){
                revert ERC20TransferFailed();
            }
            emit AssetsRebalanced(0, outflow);
        }else{
            emit AssetsRebalanced(0,0); //Correct amount was already in the vault
        }
    }

    /*
    BOILERPLATE FUNCTIONS FOR ERC7540 AND ERC4626 COMPLIANCE
    */

    function previewWithdraw(
        uint256 /*assets*/
    ) public pure override returns (uint256) {
        revert NotAvailableInAsyncRedeemVault();
    }

    function previewRedeem(
        uint256 /*shares*/
    ) public pure override returns (uint256) {
        revert NotAvailableInAsyncRedeemVault();
    }

    function requestDeposit(uint256 /*shares*/) public pure returns (uint256) {
        revert NotAvailableInAsyncRedeemVault();
    }

    function pendingDepositRequest(
        uint256 /*requestId*/,
        address /*controller*/
    ) public pure returns (uint256) {
        return 0; //Not an async deposit vault
    }

    function claimableDepositRequest(
        uint256 /*requestId*/,
        address /*controller*/
    ) public pure returns (uint256) {
        return 0; //Not an async deposit vault
    }

    function maxWithdraw(
        address /*owner*/
    ) public pure override returns (uint256) {
        return 0; // Withdraws are not supported, only redeems are.
    }

    function withdraw(
        uint256 /*assets*/,
        address /*receiver*/,
        address /*owner*/
    ) public pure override returns (uint256) {
        revert NotAvailableInAsyncRedeemVault();
    }
}
