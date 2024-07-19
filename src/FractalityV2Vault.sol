// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/AccessControl.sol";
//This reentrancy guard is from the master branch of openzeppelin, that uses transient storage.
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@solmate/tokens/ERC4626.sol";

import "@solmate/tokens/ERC20.sol";

contract FractalityV2Vault is AccessControl, ERC4626 {
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
        address strategyAddress;
        StrategyAddressType strategyAddressType;
        string strategyURI;
        string strategyName;
    }

    /// @notice Struct representing a redemption request
    /// @dev This struct contains all the necessary information about a user's redemption request
    /// @param redeemRequestShareAmount The number of shares requested to be redeemed
    /// @param redeemRequestAssetAmount The converted number of assets to be redeemed (exchange rate frozen at request time)
    /// @param redeemRequestCreationTime Timestamp of the redemption request
    struct RedeemRequestData {
        uint256 redeemRequestShareAmount;
        uint256 redeemRequestAssetAmount;
        uint256 redeemRequestCreationTime;
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

    /// @notice The fee charged on redeems, expressed in basis points
    /// @dev 100 basis points = 1%. For example, a value of 20 represents a 0.2% fee
    /// @dev This fee is deducted from the assets at the time of redeem
    uint256 public redeemFeeBasisPoints;

    /// @notice The address where redeem fees are sent
    /// @dev This address receives the assets collected from the redeem fee
    address public redeemFeeCollector;

    /// @notice The minimum delay between creating a redemption request and when it can be processed
    /// @dev This value is in seconds and represents the mandatory waiting period for redemption requests
    /// @dev Users must wait at least this long after creating a request before it can be processed
    uint256 public claimableDelay;

    /// @notice The minimum amount of assets that can be deposited by a user
    /// @dev This value sets the lower limit for deposits to prevent dust amounts and prevent truncation errors.
    /// @dev Attempts to deposit less than this amount will be rejected
    uint256 public minDeposit;

    /// @notice The maximum amount of assets that can be deposited by a user
    /// @dev This value sets the upper limit for deposits to prevent overflows and prevent truncation errors.
    /// @dev Attempts to deposit more than this amount will be rejected
    uint256 public maxDeposit;

    /// @notice The maximum amount of assets that the vault can hold
    /// @dev This value sets the upper limit for the total assets in the vault
    /// @dev Deposits that would cause the total assets to exceed this limit will be rejected
    uint256 public maxVaultCapacity;

    /// @notice The abstract representation of the total assets in the vault
    /// @dev This value represents the assets in the vault, although the actual assets are held in the strategy
    /// @dev Increases with deposits and profit reporting, decreases with redeems and loss reporting
    /// @dev Note: This is an abstract representation as the actual assets are managed by the strategy
    uint256 public vaultAssets;

    /// @notice Indicates whether the vault operations are halted
    /// @dev When true, certain operations in the vault cannot be performed
    /// @dev This is typically used in emergency situations or during maintenance
    bool public halted;

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

    /// @notice Emitted when the maximum deposit limit is set
    /// @param newMaxDeposit The new maximum deposit limit in asset terms
    event MaxDepositSet(uint256 newMaxDeposit);

    /// @notice Emitted when the minimum deposit limit is set
    /// @param newMinDeposit The new minimum deposit limit in asset terms
    event MinDepositSet(uint256 newMinDeposit);

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
    event RedeemFeeSet(uint256 newRedeemFee);

    /*
    ERRORS  
    */

    /// @notice Error thrown when a user tries to use withdraw instead of redeem
    /// @dev Users must use the redeem function for withdrawals in this vault
    error UseRedeem();

    /// @notice Error thrown when trying to deposit assets worth 0 shares
    /// @dev Deposits must result in a non-zero amount of shares
    error ZeroShares();

    /// @notice Error thrown when trying to redeem shares that equal zero assets
    /// @dev Withdrawals must result in a non-zero amount of assets
    error ZeroAssets();

    /// @notice Error thrown when an input address is the zero address
    /// @dev Addresses must be non-zero
    error ZeroAddress();

    /// @notice Error thrown when an invalid max deposit amount has been attempted to be set
    /// @dev The maximum deposit amount must be valid according to vault rules
    error InvalidMaxDeposit();

    /// @notice Error thrown when an invalid min deposit amount has been attempted to be set
    /// @dev The minimum deposit amount must be valid according to vault rules
    error InvalidMinDeposit();

    /// @notice Error thrown when an invalid max vault capacity has been attempted to be set
    /// @dev The maximum vault capacity must be valid according to vault rules
    error InvalidMaxVaultCapacity();

    /// @notice Error thrown when assets are attempted to be added that would exceed the max vault capacity
    /// @dev The total assets in the vault must not exceed the maximum capacity
    error ExceedsMaxVaultCapacity();

    /// @notice Generic error thrown when the caller isn't authorized to do an action
    /// @dev This is particularly used for checking operator permissions
    error Unauthorized();

    /// @notice Error thrown when a user tries to create a redeem request when there is an existing one already
    /// @dev A user can only have one active redeem request at a time
    error ExistingRedeemRequest();

    /// @notice Error thrown when a user tries to redeem a request that doesn't exist
    /// @dev A redeem request must exist before it can be processed
    error NonexistentRedeemRequest();

    /// @notice Error thrown during a redeem when input and request shares don't match
    /// @dev This is a safety check to ensure the correct amount of shares are being redeemed
    error ShareAmountDiscrepancy();

    /// @notice Error thrown when someone tries to do an async deposit, which is not available in this vault
    /// @dev Async deposits are not supported in this vault implementation
    error AsyncDepositNotAvailable();

    /// @notice Error thrown when an invalid redeem fee has been attempted to be set
    /// @dev The redeem fee must be between 0 and 10000 basis points (0% to 100%)
    error InvalidRedeemFee();

    /// @notice Error thrown when an invalid strategy type has been provided
    /// @dev The strategy type must be a valid enum value in StrategyAddressType (0 to 3)
    error InvalidStrategyType();


    /*
    EXTERNAL FUNCTIONS  
    */
    constructor(address _asset, string memory _vaultSharesName, string memory _vaultSharesSymbol, address _strategyAddress, string memory _strategyName, string memory _strategyURI, uint8 _strategyType, uint256 _maxDeposit, uint256 _minDeposit, uint256 _maxVaultCapacity, uint256 _redeemFeeBasisPoints, uint256 _claimableDelay, address _redeemFeeCollector, address _pnlReporter) ERC4626(ERC20(_asset), _vaultSharesName, _vaultSharesSymbol) AccessControl() {
        if(_asset==address(0) || _strategyAddress==address(0) || _pnlReporter==address(0) || _redeemFeeCollector==address(0) ){
            revert ZeroAddress();
        }
        if(_minDeposit>_maxDeposit){
            revert InvalidMinDeposit();
        }
        if(_maxVaultCapacity==0){
            revert InvalidMaxVaultCapacity();
        }
        if (_redeemFeeBasisPoints > 10000) {
            revert InvalidRedeemFee();
        }
        if (_strategyType > 3) {
            revert InvalidStrategyType();
        }
 
        strategy = InvestmentStrategy(_strategyAddress, StrategyAddressType(_strategyType), _strategyURI, _strategyName);

        maxDeposit=_maxDeposit;
        minDeposit=_minDeposit;
        maxVaultCapacity=_maxVaultCapacity;
        redeemFeeBasisPoints=_redeemFeeBasisPoints;
        claimableDelay=_claimableDelay;

        redeemFeeCollector=_redeemFeeCollector;
        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(PNL_REPORTER_ROLE, _pnlReporter);
    }

    



}
