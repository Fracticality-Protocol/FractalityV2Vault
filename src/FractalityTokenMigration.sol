// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC20/utils/TokenTimelock.sol)

pragma solidity ^0.8.26;

import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
/**
 * @dev inspired by OpenZeppelin v4.5.0 TokenTimelock contract
 * @author Jose Herrera
 * https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/refs/tags/v4.8.3/contracts/token/ERC20/utils/TokenTimelock.sol
 */ 
contract FractalityTokenMigration is Ownable {
    using SafeTransferLib for ERC20;

    // ERC20 basic token contract being held
    ERC20 public immutable token;

    // address where "burned" / "migrated" tokens are sent.
    address public constant BURN_ADDRESS=0x000000000000000000000000000000000000dEaD;

    // maximum number of seconds that can be added to the lock deadline
    uint256 public constant MAX_DEADLINE_EXTENSION_PER_CALL = 30 days;//2592000 seconds

    // time after which users can no longer migrate tokens.
    uint256 public lockDeadline;

    /// @notice Total amount of tokens that have been migrated to the burn address
    /// @dev This value is incremented each time tokens are migrated via the migrate function
    uint256 public totalMigratedTokens;

    /// @notice Whether token migrations are currently paused
    /// @dev When true, calls to migrate() will revert with MigrationPaused error
    bool public paused;

    /// @notice Event emitted when tokens are migrated to the burn address
    /// @dev These events will be collected by an external service to track the migration
    /// @param amount The amount of tokens migrated
    /// @param caller The address that initiated the migration
    /// @param migrationAddress The address that should receive the migrated tokens on the new chain
    event MigrationRegistered(uint256 amount, address indexed caller,address indexed migrationAddress);

    /// @notice Event emitted when the lock deadline is extended
    /// @param newLockDeadline The new lock deadline
    event LockDeadlineExtended(uint256 newLockDeadline);

    /// @notice Emitted when tokens are rescued from the contract
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    /// @notice Event emitted when the migration pause status is changed
    /// @param paused The new pause status - true if paused, false if unpaused
    event MigrationPausedStatusChanged(bool paused);

    /// @notice Error thrown when the deadline chosen is before the current time
    error DeadlineBeforeCurrentTime();

    /// @notice Error thrown when the deadline has passed
    error DeadlineHasPassed();

    /// @notice Error thrown when the deadline extension exceeds the maximum allowed extension per call
    error DeadlineExtensionTooLarge();

    /// @notice Error thrown when a zero address is provided where a non-zero address is required
    error ZeroAddress();

    /// @notice Error thrown when an amount of tokens is zero.
    error ZeroAmount();

    /// @notice Error thrown when attempting to migrate tokens while migrations are paused
    error MigrationPaused();

    /// @dev Deploys this contract, which allows users to migrate 'burn' their tokens before the deadline, so they can be migrated to the new chain.
    constructor(
        ERC20 token_,
        uint256 lockDeadline_
    ) Ownable(msg.sender) {
        if (lockDeadline_ <= block.timestamp) {
            revert DeadlineBeforeCurrentTime();
        }
        if(address(token_) == address(0)) {
            revert ZeroAddress();
        }
        token = token_;
        lockDeadline = lockDeadline_;
    }

    /**
     * @notice Extends the lock deadline by the specified amount of seconds
     * @dev Can only be called by the contract owner
     * @param deadLineExtension The number of seconds to extend the deadline by
     */
    function extendLockDeadline(uint256 deadLineExtension) external onlyOwner {
        if (deadLineExtension > MAX_DEADLINE_EXTENSION_PER_CALL) {
            revert DeadlineExtensionTooLarge();
        }
        if (block.timestamp > lockDeadline) {
            revert DeadlineHasPassed();
        }
        lockDeadline += deadLineExtension;
        emit LockDeadlineExtended(lockDeadline);
    }   

    function togglePaused() external onlyOwner {
        paused = !paused;
        emit MigrationPausedStatusChanged(paused);
    }

    /**
     * @notice Allows the owner to rescue any ERC20 tokens that were accidentally sent to this contract
     * @param tokenAddress The address of the token to rescue
     * @param to The address to send the tokens to
     */
    function rescueTokens(
        address tokenAddress,
        address to
    ) external onlyOwner {
        if (to == address(0)) {
            revert ZeroAddress();
        }
        uint256 amount = ERC20(tokenAddress).balanceOf(address(this));
        if (amount == 0) {
            revert ZeroAmount();
        }

        ERC20(tokenAddress).safeTransfer(to, amount);
        emit TokensRescued(tokenAddress, to, amount);
    }

    /**
     * @dev Migrates the tokens to the burn address
     * @dev Throws an error if the deadline has passed
     * @notice Requires an approval from the user to burn their tokens
     */
    function migrate(uint256 amount,address migrationAddress) external {
        if (block.timestamp > lockDeadline) {
            revert DeadlineHasPassed();
        }

        if(paused) {
            revert MigrationPaused();
        }
        
        if(address(migrationAddress) == address(0)) {
            revert ZeroAddress();
        }

        if(amount == 0) {
            revert ZeroAmount();
        }

        unchecked { 
            totalMigratedTokens+=amount;
        }

        token.safeTransferFrom(msg.sender, BURN_ADDRESS, amount);
        emit MigrationRegistered(amount, msg.sender, migrationAddress);
    }

}