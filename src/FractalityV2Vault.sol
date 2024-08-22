// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
//This reentrancy guard is from the master branch of openzeppelin, that uses transient storage.
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC4626} from "@solmate/tokens/ERC4626.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
/*
 /$$$$$$$$ /$$$$$$$   /$$$$$$   /$$$$$$  /$$$$$$$$ /$$$$$$  /$$       /$$$$$$ /$$$$$$$$ /$$     /$$
| $$_____/| $$__  $$ /$$__  $$ /$$__  $$|__  $$__//$$__  $$| $$      |_  $$_/|__  $$__/|  $$   /$$/
| $$      | $$  \ $$| $$  \ $$| $$  \__/   | $$  | $$  \ $$| $$        | $$     | $$    \  $$ /$$/ 
| $$$$$   | $$$$$$$/| $$$$$$$$| $$         | $$  | $$$$$$$$| $$        | $$     | $$     \  $$$$/  
| $$__/   | $$__  $$| $$__  $$| $$         | $$  | $$__  $$| $$        | $$     | $$      \  $$/   
| $$      | $$  \ $$| $$  | $$| $$    $$   | $$  | $$  | $$| $$        | $$     | $$       | $$    
| $$      | $$  | $$| $$  | $$|  $$$$$$/   | $$  | $$  | $$| $$$$$$$$ /$$$$$$   | $$       | $$    
|__/      |__/  |__/|__/  |__/ \______/    |__/  |__/  |__/|________/|______/   |__/       |__/    
                                                                                                   
                                                                                                   
                                                                                                   
 /$$    /$$  /$$$$$$  /$$   /$$ /$$    /$$$$$$$$       /$$    /$$  /$$$$$$                         
| $$   | $$ /$$__  $$| $$  | $$| $$   |__  $$__/      | $$   | $$ /$$__  $$                        
| $$   | $$| $$  \ $$| $$  | $$| $$      | $$         | $$   | $$|__/  \ $$                        
|  $$ / $$/| $$$$$$$$| $$  | $$| $$      | $$         |  $$ / $$/  /$$$$$$/                        
 \  $$ $$/ | $$__  $$| $$  | $$| $$      | $$          \  $$ $$/  /$$____/                         
  \  $$$/  | $$  | $$| $$  | $$| $$      | $$           \  $$$/  | $$                              
   \  $/   | $$  | $$|  $$$$$$/| $$$$$$$$| $$            \  $/   | $$$$$$$$                        
    \_/    |__/  |__/ \______/ |________/|__/             \_/    |________/                        
*/
/// @title FractalityV2Vault
/// @notice This contract implements an ERC7540 async deposit vault where funds are invested in an external strategy.
/// @dev Inherits from AccessControl for role-based access control, ERC4626 for tokenized vault functionality, and ReentrancyGuard for protection against reentrancy attacks
/// @author Jose Herrera <jose@y2k.finance>
contract FractalityV2Vault is AccessControl, ERC4626, ReentrancyGuard {
    using SafeTransferLib for ERC20;
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
        address strategyAddress; //256 -> slot
        StrategyAddressType strategyAddressType; //256 -> slot
        string strategyURI; //256 -> slot
        string strategyName; //256 -> slot
    }

    /// @notice Struct representing a redemption request
    /// @dev This struct contains all the necessary information about a user's redemption request
    /// @param redeemRequestShareAmount The number of shares requested to be redeemed
    /// @param redeemRequestAssetAmount The converted number of assets to be redeemed (exchange rate frozen at request time)
    /// @param redeemRequestCreationTime Timestamp of the redemption request
    /// @param originalSharesOwner The address that originally owned the shares being redeemed
    /// @param redeemFeeBasisPoints The fee charged to be charged on redeem, in basis points.
    struct RedeemRequestData {
        uint256 redeemRequestShareAmount; //256 -> slot
        uint256 redeemRequestAssetAmount; //256 -> slot
        uint96 redeemRequestCreationTime; //96
        address originalSharesOwner; //160 -> slot
        uint16 redeemFeeBasisPoints; //16 -> slot
    }

    /// @notice Struct containing parameters for initializing the vault
    /// @param asset The address of the underlying asset token. Cannot be a rebasing token!
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
        address asset; //160
        uint16 redeemFeeBasisPoints; //16
        uint32 claimableDelay; //32
        uint8 strategyType; //8 -> slot
        address strategyAddress; //160 -> slot
        address redeemFeeCollector; //160 -> slot
        address pnlReporter; //160 -> slot
        uint128 maxDepositPerTransaction; //128
        uint128 minDepositPerTransaction; //128 -> slot
        uint256 maxVaultCapacity; //256 -> slot
        string strategyName; //256 -> slot
        string strategyURI; //256 -> slot
        string vaultSharesName; //256 -> slot
        string vaultSharesSymbol; //256 -> slot
    }

    /*
    STATE VARIABLES
    */

    /// @notice The investment strategy currently employed by this vault
    /// @dev This strategy defines where and how all the funds in the vault will be invested
    InvestmentStrategy public strategy;

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
    uint16 private constant _MAX_BASIS_POINTS = 10000;

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

    /// @notice Error thrown when reported losses exceed the total assets in the vault
    /// @dev This error is used to prevent the vault's asset balance from causing an underflow.
    /// @dev It's thrown in the reportLosses function if the reported loss amount is greater than the current vaultAssets
    error LossExceedsVaultAssets();

    /// @notice Emitted when a redeem request fails due to produce enough assets, specified in the request.
    /// @dev This event is triggered when the converted asset amount is less than the specified minimum assets out in a redeem request
    error RequestRedeemMinAssetsFail();

    /// @notice Error thrown when the caller is not the controller of a redeem request
    /// @dev This error is used to ensure that only the caller of the redeem request can process it.
    /// @dev Turns off one layer of delegation - use operator functionality instead to delegate.
    error ControllerMustBeCaller();

    /// @notice Error thrown when a user attempts to redeem more shares than they own
    /// @dev This error is not needed, but it gives context to ERC20's error handling.
    error InsufficientShares();

    /// @notice Error thrown when there are not enough assets in general to fulfill a redemption request
    /// @dev This error is triggered only in the case of a catastrophic loss of capital in the trading strategy.
    error InsufficientAssetsInVault();

    /// @notice Error thrown when the caller's asset allowance is insufficient for a transfer
    /// @dev This error is used to provide more context than the standard ERC20 error
    error InsufficientAllowance();

    /*
    Modifiers
    */
    /// @notice Modifier to restrict function execution when the contract is halted
    /// @dev This modifier checks if the contract is in a halted state and reverts if it is
    modifier onlyWhenNotHalted() {
        if (halted) {
            revert Halted();
        }
        _;
    }

    /// @notice Modifier to check if the caller is authorized to perform operations on behalf of a user
    /// @dev This modifier checks if the caller is either the user themselves or an approved operator for the user
    /// @param user The address of the user whose authorization is being checked
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
        if (params.redeemFeeBasisPoints > _MAX_BASIS_POINTS) {
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
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PNL_REPORTER_ROLE, params.pnlReporter);
    }

    /// @notice Sets a new claimable delay for the vault
    /// @dev This function can only be called by an account with the DEFAULT_ADMIN_ROLE
    /// @param _newClaimableDelay The new delay (in seconds) before a redeem request becomes claimable.
    function setClaimableDelay(
        uint32 _newClaimableDelay
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        claimableDelay = _newClaimableDelay;
        emit ClaimableDelaySet(_newClaimableDelay);
    }

    /// @notice Sets the halt status of the vault
    /// @dev This function can only be called by an account with the DEFAULT_ADMIN_ROLE
    /// @param _newHaltStatus The new halt status to set (true for halted, false for not halted)
    function setHaltStatus(
        bool _newHaltStatus
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (halted == _newHaltStatus) {
            revert HaltStatusUnchanged();
        }
        halted = _newHaltStatus;
        emit HaltStatusChanged(_newHaltStatus);
    }

    /// @notice Sets the maximum deposit amount allowed per transaction
    /// @dev This function can only be called by an account with the DEFAULT_ADMIN_ROLE
    /// @param _newMaxDepositPerTransaction The new maximum deposit amount per transaction
    function setMaxDepositPerTransaction(
        uint128 _newMaxDepositPerTransaction
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newMaxDepositPerTransaction < minDepositPerTransaction) {
            revert InvalidMaxDepositPerTransaction();
        }
        maxDepositPerTransaction = _newMaxDepositPerTransaction;
        emit MaxDepositPerTransactionSet(_newMaxDepositPerTransaction);
    }

    /// @notice Sets the minimum deposit amount allowed per transaction
    /// @dev This function can only be called by an account with the DEFAULT_ADMIN_ROLE
    /// @param _newMinDepositPerTransaction The new minimum deposit amount per transaction
    function setMinDepositPerTransaction(
        uint128 _newMinDepositPerTransaction
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newMinDepositPerTransaction > maxDepositPerTransaction) {
            revert InvalidMinDepositPerTransaction();
        }
        minDepositPerTransaction = _newMinDepositPerTransaction;
        emit MinDepositSet(_newMinDepositPerTransaction);
    }

    /// @notice Sets the maximum capacity of assets that the vault can hold
    /// @dev This function can only be called by an account with the DEFAULT_ADMIN_ROLE
    /// @dev The new max vault capacity must be higher than the current vaultAssets
    /// @param _newMaxVaultCapacity The new maximum capacity of assets for the vault
    function setMaxVaultCapacity(
        uint256 _newMaxVaultCapacity
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newMaxVaultCapacity < vaultAssets) {
            revert InvalidMaxVaultCapacity();
        }
        maxVaultCapacity = _newMaxVaultCapacity;
        emit MaxVaultCapacitySet(_newMaxVaultCapacity);
    }

    /// @notice Sets or removes an operator for the caller's account
    /// @dev This function allows users to designate or revoke operator privileges for their account
    /// @param _operator The address to set as an operator or remove operator status from
    /// @param _approved True to approve the operator, false to revoke approval
    function setOperator(address _operator, bool _approved) external {
        if (_operator == address(0)) {
            revert ZeroAddress();
        }
        operators[msg.sender][_operator] = _approved;
        emit OperatorSet(msg.sender, _operator, _approved);
    }

    /// @notice Sets the redeem fee for the vault
    /// @dev This function can only be called by an account with the DEFAULT_ADMIN_ROLE
    /// @param _newRedeemFeeBasisPoints The new redeem fee in basis points (100 basis points = 1%)
    function setRedeemFee(
        uint16 _newRedeemFeeBasisPoints
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newRedeemFeeBasisPoints > _MAX_BASIS_POINTS) {
            revert InvalidRedeemFee();
        }
        redeemFeeBasisPoints = _newRedeemFeeBasisPoints;
        emit RedeemFeeSet(_newRedeemFeeBasisPoints);
    }

    /// @notice Sets a new name for the investment strategy
    /// @dev This function can only be called by an account with the DEFAULT_ADMIN_ROLE
    /// @param _newStrategyName The new name to set for the investment strategy
    function setStrategyName(
        string memory _newStrategyName
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategy.strategyName = _newStrategyName;
        emit StrategyNameSet(_newStrategyName);
    }

    /// @notice Sets a new URI for the investment strategy
    /// @dev This function can only be called by an account with the DEFAULT_ADMIN_ROLE
    /// @param _newStrategyURI The new URI to set for the investment strategy
    function setStrategyURI(
        string memory _newStrategyURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategy.strategyURI = _newStrategyURI;
        emit StrategyURISet(_newStrategyURI);
    }

    /// @notice Sets a new address for the redeem fee collector
    /// @dev This function can only be called by an account with the DEFAULT_ADMIN_ROLE
    /// @param _newRedeemFeeCollector The new address to set as the redeem fee collector
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

    /// @notice Returns the total amount of assets "in" the vault - both assets in the vault for the purpose of withdraws + assets in the strategy.
    /// @dev This function overrides the totalAssets function from ERC4626
    /// @dev Goes up on deposits/mints and profit reports, goes down on redeems and loss reports.
    /// @return The total assets "in" the vault
    function totalAssets() public view override returns (uint256) {
        return vaultAssets;
    }

    /// @notice Returns the maximum amount of assets that can be deposited in a single transaction
    /// @dev This function overrides the maxDeposit function from ERC4626
    /// @dev Returns the smaller of the maxDepositPerTransaction and the remaining vault capacity
    /// @param 0 The address that would receive the minted shares (unused in this implementation)
    /// @return The maximum amount of assets that can be deposited
    function maxDeposit(
        address /*receiver*/
    ) public view override returns (uint256) {
        if (halted) {
            return 0; //cannot deposit while halted
        }
        uint256 remainingCapacity = maxVaultCapacity - vaultAssets;
        return
            remainingCapacity < maxDepositPerTransaction
                ? remainingCapacity
                : maxDepositPerTransaction;
    }

    /// @notice Returns the maximum amount of shares that can be minted in a single transaction
    /// @dev This function overrides the maxMint function from ERC4626
    /// @dev Calculates the maximum shares by converting the maximum deposit amount to shares
    /// @param receiver The address that would receive the minted shares (unused in this implementation)
    /// @return The maximum amount of shares that can be minted
    function maxMint(address receiver) public view override returns (uint256) {
        return convertToShares(maxDeposit(receiver));
    }

    /// @notice Checks if an address is an operator for an account
    /// @dev This function verifies if the given operator address has been authorized for the specified account
    /// @param account The address of the account to check
    /// @param operator The address of the potential operator for the account.
    /// @return bool Returns true if the operator is authorized for the account, false otherwise
    function isOperator(
        address account,
        address operator
    ) public view returns (bool) {
        return operators[account][operator];
    }

    /// @notice Returns the amount of shares in a pending redeem request for a given controller
    /// @dev A redeem request is considered pending if it hasn't reached the claimable delay period
    /// @param 0 The ID of the redeem request (unused, as we have 1 request per user at a time)
    /// @param controller The address of the request's controller
    /// @return uint256 The amount of shares in the pending redeem request, or 0 if no pending request exists
    function pendingRedeemRequest(
        uint256 /*requestId*/,
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

    /// @notice Returns the amount of shares in a claimable redeem request for a given controller
    /// @dev A redeem request is considered claimable if it has reached or passed the claimable delay period
    /// @param 0 The ID of the redeem request (unused, as we have 1 request per user at a time)
    /// @param controller The address of the request's controller
    /// @return uint256 The amount of shares in the claimable redeem request, or 0 if no claimable request exists
    function claimableRedeemRequest(
        uint256 /*requestId*/,
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
            return
                _getClaimableShares(
                    request.redeemRequestShareAmount,
                    request.redeemRequestAssetAmount
                );
        }
    }

    /// @notice Returns the maximum amount of shares that can be redeemed by a controller
    /// @dev This function overrides the ERC4626 maxRedeem function
    /// @dev We don't have partial redeems, so the return value is either 0 or all the shares in a request.
    /// @param controller The address of the controller attempting to redeem
    /// @return uint256 The maximum number of shares that can be redeemed, or 0 if redemption is not possible
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

        return
            _getClaimableShares(
                request.redeemRequestShareAmount,
                request.redeemRequestAssetAmount
            );
    }

    /*
    MAIN OPERATIONAL FUNCTIONS
    */

    /**
     * @notice Deposits assets into the vault and mints shares to the receiver, by specifying the amount of assets.
     * @dev This function overrides the ERC4626 deposit function
     * @dev It can only be called when the vault is not halted
     * @param assets The amount of assets to deposit
     * @param receiver The address that will receive the minted shares
     * @return shares The amount of shares minted
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public override onlyWhenNotHalted nonReentrant returns (uint256 shares) {
        shares = previewDeposit(assets);
        _mintAndDepositCommon(assets, receiver, shares);
    }

    /**
     * @notice Deposits assets into the vault and mints shares to the receiver, by specifying the amount of shares.
     * @dev This function overrides the ERC4626 mint function
     * @dev It can only be called when the vault is not halted
     * @param shares The amount of shares to mint
     * @param receiver The address that will receive the minted shares
     * @return assets The amount of assets deposited
     */
    function mint(
        uint256 shares,
        address receiver
    ) public override onlyWhenNotHalted nonReentrant returns (uint256 assets) {
        assets = previewMint(shares);
        _mintAndDepositCommon(assets, receiver, shares);
    }

    /**
     * @notice Reports profits to the vault
     * @dev This function can only be called by an account with the PNL_REPORTER_ROLE
     * @dev Even though tokens aren't transferred to the vault, vaultAssets are increased.
     * @param assetProfitAmount The amount of profit in asset tokens
     * @param infoURI A URI containing additional information about the profit report
     * @return The total amount of profits reported so far
     */
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

    /**
     * @notice Reports losses to the vault
     * @dev This function can only be called by an account with the PNL_REPORTER_ROLE
     * @dev Decreases the vaultAssets by the reported loss amount
     * @param assetLossAmount The amount of loss in asset tokens
     * @param infoURI A URI containing additional information about the loss report
     * @return The total amount of losses reported so far
     */
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

    /**
     * @notice Requests a redemption of shares
     * @dev This function can only be called when the contract is not halted
     * @dev Caller can be any owner of shares, or an approved operator of the owner.
     * @dev It creates a new redemption request or reverts if there's an existing request
     * @dev Note that the exchange rate between shares and assets is fixed in the request.
     * @param shares The number of shares to redeem
     * @param controller The address that will control this redemption request (must be caller)
     * @param owner The address that owns the shares to be redeemed
     * @return A uint8 representing the request ID (always 0 in this implementation)
     */
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
        return _requestRedeem(shares, controller, owner);
    }

    /**
     * @notice Requests a redemption of shares with a minimum assets out check
     * @dev This function can only be called when the contract is not halted
     * @dev Caller can be any owner of shares, or an approved operator of the owner
     * @dev It creates a new redemption request or reverts if there's an existing request
     * @dev The exchange rate between shares and assets is fixed in the request
     * @dev Reverts if the converted assets are less than the specified minimum
     * @param shares The number of shares to redeem
     * @param controller The address that will control this redemption request (must be caller)
     * @param owner The address that owns the shares to be redeemed
     * @param minAssetsOut The minimum amount of assets expected from the redemption
     * @return A uint8 representing the request ID (always 0 in this implementation)
     */
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner,
        uint256 minAssetsOut
    )
        external
        onlyWhenNotHalted
        operatorCheck(owner)
        nonReentrant
        returns (uint8)
    {
        if (convertToAssets(shares) < minAssetsOut) {
            revert RequestRedeemMinAssetsFail();
        }
        return _requestRedeem(shares, controller, owner);
    }

    /**
     * @notice Redeems shares for assets, completing a previously initiated redemption request
     * @dev This function can only be called when the contract is not halted
     * @dev Caller must be the controller of the redemption request or an approved operator
     * @dev It processes the redemption request, burns the claimable shares, and transfers assets to the receiver
     * @dev A redemption fee is applied to the redeemed assets.
     * @dev The actual amount of assets transferred to the receiver will be less than the
     * original requested amount due to this withdrawal fee.
     * @param shares The number of shares to redeem (must match the original request)
     * @param receiver The address that will receive the redeemed assets
     * @param controller The address that controls this redemption request (must be the original caller of the redeem request)
     * @return The amount of assets transferred to the receiver
     */
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
        //second check here is unreachable
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
            request.redeemRequestShareAmount,
            request.redeemRequestAssetAmount
        );
        if (
            block.timestamp <
            request.redeemRequestCreationTime + claimableDelay ||
            claimableShares == 0
        ) {
            revert NonClaimableRedeemRequest();
        }

        totalAssetsInRedemptionProcess -= request.redeemRequestAssetAmount;
        totalSharesInRedemptionProcess -= request.redeemRequestShareAmount;

        delete redeemRequests[controller];

        //calculate withdraw fee

        uint256 withdrawFee = _calculateWithdrawFee(
            request.redeemRequestAssetAmount,
            request.redeemFeeBasisPoints
        );
        uint256 netAssetRedeemAmount = request.redeemRequestAssetAmount -
            withdrawFee;

        asset.safeTransfer(redeemFeeCollector, withdrawFee);
        asset.safeTransfer(receiver, netAssetRedeemAmount);

        emit Withdraw(
            msg.sender,
            receiver,
            request.originalSharesOwner,
            netAssetRedeemAmount,
            shares
        );

        return netAssetRedeemAmount;
    }

    /**
     * @notice Rebalances assets so that the vault has enough assets, but not more, to cover all pending redemption requests
     * @dev This function can only be called by an account with the DEFAULT_ADMIN_ROLE
     * @dev It ensures that the vault has enough assets to cover all pending redemption requests
     * @dev If the vault has more assets than needed, it transfers the excess to the strategy
     * @dev If the vault has less assets than needed, it transfers the necessary amount from provided address.
     * @param sourceOfAssets The address from which to transfer additional assets if needed
     */
    function rebalanceAssets(
        address sourceOfAssets
    ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (sourceOfAssets == address(0)) {
            revert ZeroAddress();
        }
        uint256 assetVaultBalance = asset.balanceOf(address(this));
        if (totalAssetsInRedemptionProcess > assetVaultBalance) {
            uint256 inflow = totalAssetsInRedemptionProcess - assetVaultBalance;

            asset.safeTransferFrom(sourceOfAssets, address(this), inflow);

            emit AssetsRebalanced(inflow, 0);
        } else if (totalAssetsInRedemptionProcess < assetVaultBalance) {
            uint256 outflow = assetVaultBalance -
                totalAssetsInRedemptionProcess;

            asset.safeTransfer(strategy.strategyAddress, outflow);

            emit AssetsRebalanced(0, outflow);
        } else {
            emit AssetsRebalanced(0, 0); //Correct amount was already in the vault
        }
    }

    /*
    INTERNAL FUNCTIONS
    */

    function _mintAndDepositCommon(
        uint256 assets,
        address receiver,
        uint256 shares
    ) internal {
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

        //This check is not necessary, but it gives context to ERC20's error handling.
        if (asset.allowance(msg.sender, address(this)) < assets) {
            revert InsufficientAllowance();
        }

        asset.safeTransferFrom(msg.sender, strategy.strategyAddress, assets);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function _getClaimableShares(
        uint256 _redeemRequestShareAmount,
        uint256 _redeemRequestAssetAmount
    ) internal view returns (uint256) {
        if (asset.balanceOf(address(this)) < _redeemRequestAssetAmount) {
            return 0; //Not enough assets in the vault to cover the request
        } else {
            return _redeemRequestShareAmount; //Can redeem the shares for the requested asset amount
        }
    }

    function _calculateWithdrawFee(
        uint256 _redeemAssetAmount,
        uint256 _redeemFeeBasisPoints
    ) internal pure returns (uint256) {
        return (_redeemAssetAmount * _redeemFeeBasisPoints) / _MAX_BASIS_POINTS;
    }

    function _requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) internal returns (uint8) {
        //Unreachable
        if (owner == address(0)) {
            revert ZeroAddress();
        }

        if (controller != msg.sender) {
            revert ControllerMustBeCaller();
        }

        if (balanceOf[owner] < shares) {
            revert InsufficientShares();
        }

        uint256 assets = convertToAssets(shares);
        if (assets == 0) {
            revert ZeroAssets();
        }
        //Unreachable
        if (assets > vaultAssets) {
            revert InsufficientAssetsInVault();
        }

        RedeemRequestData storage request = redeemRequests[controller];

        if (request.redeemRequestCreationTime > 0) {
            revert ExistingRedeemRequest();
        }

        request.redeemRequestShareAmount = shares;
        request.redeemRequestAssetAmount = assets;
        request.redeemRequestCreationTime = uint96(block.timestamp);
        request.originalSharesOwner = owner;
        request.redeemFeeBasisPoints = redeemFeeBasisPoints;

        totalAssetsInRedemptionProcess += assets;
        totalSharesInRedemptionProcess += shares;

        //reduce the vault's investment assets right away.
        vaultAssets -= assets;

        //burn the owner's shares right away.
        _burn(owner, shares);

        emit RedeemRequest(msg.sender, controller, owner, shares, assets);

        return 0; // Request id, always since we only have 1 request per user at a time.
    }

    /*
    BOILERPLATE FUNCTIONS FOR ERC7540 AND ERC4626 COMPLIANCE
    */

    /**
     * @dev This function always reverts because the withdraw function is not available in this vault. Only redeem functionality is supported.
     * @param 0 The amount of assets that would be withdrawn
     * @return This function never returns; it always reverts
     */
    function previewWithdraw(
        uint256 /*assets*/
    ) public pure override returns (uint256) {
        revert NotAvailableInAsyncRedeemVault();
    }

    /**
     * @dev This function always reverts because it's not possible to preview a redeem because they are async.
     * @param 0 The amount of shares that would be redeemed (Not used in this implementation)
     * @return This function never returns; it always reverts
     */
    function previewRedeem(
        uint256 /*shares*/
    ) public pure override returns (uint256) {
        revert NotAvailableInAsyncRedeemVault();
    }

    /**
     * @dev This function always reverts because this implementation does not have async deposits.
     * @param 0 The amount of shares that would be deposited (Not used in this implementation)
     * @return This function never returns; it always reverts
     */
    function requestDeposit(uint256 /*shares*/) public pure returns (uint256) {
        revert NotAvailableInAsyncRedeemVault();
    }

    /**
     * @dev This function always reverts because this implementation does not have async deposits.
     * @param 0 The ID of the deposit request (Not used in this implementation)
     * @param 1 The address of the controller (Not used in this implementation)
     * @return This function never returns; it always reverts
     */
    function pendingDepositRequest(
        uint256 /*requestId*/,
        address /*controller*/
    ) public pure returns (uint256) {
        return 0; //Not an async deposit vault
    }

    /**
     * @dev This function always reverts because this implementation does not have async deposits.
     * @param 0 The ID of the deposit request (Not used in this implementation)
     * @param 1 The address of the controller (Not used in this implementation)
     * @return This function never returns; it always reverts
     */
    function claimableDepositRequest(
        uint256 /*requestId*/,
        address /*controller*/
    ) public pure returns (uint256) {
        return 0; //Not an async deposit vault
    }

    /**
     * @dev Returns the maximum amount of assets that can be withdrawn from the vault for a given owner.
     * @param 0 The address of the account to check the maximum withdrawal for (unused in this implementation)
     * @return Always returns 0 because withdraws are not supported in this vault, only redeems are available.
     */
    function maxWithdraw(
        address /*owner*/
    ) public pure override returns (uint256) {
        return 0;
    }

    /**
     * @dev This function always reverts because withdraws are not supported in this vault, only redeems are available.
     * @param 0 The amount of assets to withdraw (unused)
     * @param 1 The address to receive the withdrawn assets (unused)
     * @param 2 owner The owner of the assets to withdraw (unused)
     * @return This function never returns; it always reverts
     */
    function withdraw(
        uint256 /*assets*/,
        address /*receiver*/,
        address /*owner*/
    ) public pure override returns (uint256) {
        revert NotAvailableInAsyncRedeemVault();
    }
}
