// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "@forge-std/Script.sol";
import {FractalityV2Vault} from "../src/FractalityV2Vault.sol";
import {console} from "@forge-std/console.sol";
import {MockERC20} from "../src/MockERC20.sol";

//run via: forge script script/Redeem.s.sol --fork-url sepolia --broadcast
contract Redeem is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        uint256 user1PrivateKey = vm.envUint("USER_1_PRIVATE_KEY");
        address user1Address = vm.addr(user1PrivateKey);

        address MOCK_ERC20_ADDRESS = vm.envAddress("MOCK_ERC20_ADDRESS");
        address VAULT_ADDRESS = vm.envAddress("VAULT_ADDRESS");

        FractalityV2Vault vault = FractalityV2Vault(VAULT_ADDRESS);
        MockERC20 asset = MockERC20(MOCK_ERC20_ADDRESS);

        (
            uint256 redeemRequestShareAmount,
            uint256 redeemRequestAssetAmount,
            uint96 redeemRequestCreationTime,

        ) = vault.redeemRequests(user1Address); //where controller == user

        vm.startBroadcast(deployerPrivateKey);
        asset.transfer(VAULT_ADDRESS, redeemRequestAssetAmount + 1);
        vm.stopBroadcast();

        vm.startBroadcast(user1PrivateKey);

        console.log(block.timestamp);
        console.log(redeemRequestCreationTime + vault.claimableDelay());

        //simple redeem with no delegation at all, caller==owner==controller
        vault.redeem(redeemRequestShareAmount, user1Address, user1Address);

        // solhint-disable-next-line no-console
        console.log(
            "User %x redeemed %d shares into vault to obtain %d assets",
            user1Address,
            redeemRequestShareAmount,
            redeemRequestAssetAmount
        );

        vm.stopBroadcast();
    }
}
