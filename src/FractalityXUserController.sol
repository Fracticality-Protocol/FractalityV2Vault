// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {FractalityV2Vault} from "./FractalityV2Vault.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

//Everything here will be called by the fractality bot backend
contract FractalityXUserController is ReentrancyGuard, Ownable {

    address public immutable vault;
    string public userId;//twitterID
    address public userAddress;//address that is getting the shares, picked up by the bot

    constructor(address _vault, address _userAddress, string memory id) Ownable(msg.sender) {
        vault = _vault;
        userAddress = _userAddress;
        userId = id;
    }

    //user needs to sends funds to this contract via simple transfer
    //avoid user needing to approve for the deposit.
    function deposit(uint256 amount) external onlyOwner nonReentrant {
        FractalityV2Vault(vault).asset().approve(address(vault), amount);
        FractalityV2Vault(vault).deposit(amount, userAddress);
    }

    //requires user to send the shares to this contract to avoid needing an operator approval operation.
    function requestRedeem(uint256 shares) onlyOwner external {
        FractalityV2Vault(vault).requestRedeem(shares, address(this), address(this));
    }

    //doesn't require any special operation. Assets sent to user.
    function redeem(uint256 shares) onlyOwner external {
        FractalityV2Vault(vault).redeem(shares, userAddress, address(this));
    }

    //allow  withdrawal of share and asset by the user address
    //allow  withdrawal of wrongly sent ETH any other random assets
}