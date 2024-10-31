// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {FractalityXUserController} from "./FractalityXUserController.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

//Everything here will be called by the fractality bot backend
contract FractalityXFactory is Ownable {

    address public immutable vaultAddress;

    //twitterId => specific user controller
    mapping(string => address) public userControllers;

    constructor(address _vault) Ownable(msg.sender) {
        vaultAddress = _vault;
    }

    function createUserController(string memory id) external onlyOwner {
        require(userControllers[id] == address(0), "User already registered");

        address newUserController = address(new FractalityXUserController(vaultAddress, id));

        userControllers[id] = newUserController;
    }

    //ability to switch user controller if we want that.

}