// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // Adjusted to ^0.8.20 as per OpenZeppelin v5.x dependencies

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol"; // Importing Nonces as per linter suggestion
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // For token recovery
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; // For safeTransfer
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
/**
 * @title FractalityHyperliquidToken
 * @author Jose Herrera
 * @dev An ERC20 token with a supply cap, EIP-2612 permit functionality,
 *      EIP-4494 voting capabilities, and Ownable access control.
 *      WARNING: Any tokens or native assets sent to this contract accidentally
 *      will be forfeited and cannot be recovered.
 */
contract FractalityHyperliquidToken is ERC20, ERC20Permit, ERC20Votes, Ownable,ReentrancyGuard {
    using SafeERC20 for IERC20; // Use SafeERC20 for IERC20 instances
 
    error NothingToRecover();
    error NativeAssetTransferFailed();

    event RecoveredERC20(address indexed tokenAddress, uint256 amount);
    event RecoveredNativeAsset(uint256 amount);

    //This is less than the max uint224, the max for ERC20Votes
    uint256 public constant SUPPLY = 17143000 * 10 ** 18;

    uint8 public constant hyperCoreTokenId=65;
    string public constant systemAddress="0x2000000000000000000000000000000000000041";

    string public constant NAME = "Fractality";
    string public constant SYMBOL = "FRCT";

    constructor()
        ERC20(NAME, SYMBOL)
        ERC20Permit(NAME) // Initializes EIP712 domain for EIP-2612 permit
        Ownable(msg.sender)
        // ERC20Votes and its base Votes contract (which includes EIP712 for delegateBySig)
        // are initialized implicitly. Votes uses EIP712("Votes", "1").
    {
        // The _mint function will trigger the _update chain.
        _mint(msg.sender, SUPPLY);
    }

    /**
     * @dev Overrides _update to ensure that the logic from ERC20Votes (voting unit transfers and votes' max supply check)
     * and the base ERC20 logic is applied.
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    /**
     * @dev Overrides nonces to resolve the ambiguity. ERC20Permit uses Nonces, and
     * ERC20Votes (via its base Votes) also uses Nonces.
     * Listing ERC20Permit (as a direct parent) and Nonces (as the common ancestor point of override).
     */
    function nonces(address owner)
        public
        view
        virtual
        override(ERC20Permit, Nonces) returns (uint256)
    {
        return super.nonces(owner);
    }

    /**
     * @dev Allows the contract owner to recover the entire balance of specific ERC20 tokens 
     * (including this contract's own token) mistakenly sent to this contract address.
     * The recovered tokens are sent to the contract owner.
     * @param tokenAddress The address of the ERC20 token to recover.
     */
    function recoverERC20(address tokenAddress) public virtual onlyOwner nonReentrant {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));

        if (balance == 0) {
             revert NothingToRecover();
        }

        token.safeTransfer(owner(), balance);
        emit RecoveredERC20(tokenAddress, balance);
    }

    /**
     * @dev Allows the contract owner to recover native assets (e.g., ETH) 
     * mistakenly sent to this contract address.
     * The recovered native assets are sent to the contract owner.
     */
    function recoverNativeAsset() public virtual onlyOwner nonReentrant {
        uint256 balance = address(this).balance;

        if (balance == 0) {
            revert NothingToRecover();
        }

        (bool success, ) = owner().call{value: balance}("");
        if (!success) {
            revert NativeAssetTransferFailed();
        }

        emit RecoveredNativeAsset(balance);
    }

}
