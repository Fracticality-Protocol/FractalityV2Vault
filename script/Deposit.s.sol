// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "@forge-std/Script.sol";
import {FractalityV2Vault} from "../src/FractalityV2Vault.sol";
import {console} from "@forge-std/console.sol";
import {MockERC20} from "../src/MockERC20.sol";

//run via: forge script script/Deposit.s.sol --fork-url sepolia --broadcast
contract Deposit is Script {
    function run() external {
        uint256 user1PrivateKey = vm.envUint("USER_1_PRIVATE_KEY");
        address user1Address= vm.addr(user1PrivateKey);

        address MOCK_ERC20_ADDRESS = vm.envAddress("MOCK_ERC20_ADDRESS");
        address VAULT_ADDRESS = vm.envAddress("VAULT_ADDRESS");

        uint256 depositAmount = 1000 * 1e18; //1000$

        MockERC20 asset = MockERC20(MOCK_ERC20_ADDRESS);
        FractalityV2Vault vault = FractalityV2Vault(VAULT_ADDRESS);

        vm.startBroadcast(user1PrivateKey);

        if(asset.balanceOf(user1Address)<depositAmount){
            asset.mint(depositAmount, user1Address);
        }

        if(asset.allowance(user1Address,VAULT_ADDRESS)<depositAmount){
            asset.approve(VAULT_ADDRESS, depositAmount);
        }
        
        vault.deposit(depositAmount,user1Address);

        // solhint-disable-next-line no-console
        console.log("User %x deposited %d tokens into vault",user1Address,depositAmount);

        vm.stopBroadcast();
    }
}