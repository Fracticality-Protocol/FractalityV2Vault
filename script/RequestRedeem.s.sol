// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "@forge-std/Script.sol";
import {FractalityV2Vault} from "../src/FractalityV2Vault.sol";
import {console} from "@forge-std/console.sol";

//run via: forge script script/RequestRedeem.s.sol --fork-url sepolia --broadcast
contract RequestRedeem is Script {
    function run() external {
        uint256 user1PrivateKey = vm.envUint("USER_1_PRIVATE_KEY");
        address user1Address= vm.addr(user1PrivateKey);

        address VAULT_ADDRESS = vm.envAddress("VAULT_ADDRESS");

        uint256 shareAmountToRedeem=10;//TODO: set number of shares here.

        FractalityV2Vault vault = FractalityV2Vault(VAULT_ADDRESS);

        vm.startBroadcast(user1PrivateKey);

        if(vault.allowance(user1Address,user1Address)<shareAmountToRedeem){
            console.log("approving");
            //Self approval is strange, but necessary in this case.
            //Why? Because the caller, user1, becomes the spender, and the from is also user1.
            //To allow a better ux I suggest that the use does a max approval in the simple scenario of caller==owner==controller
            vault.approve(user1Address, shareAmountToRedeem);
        }

        console.log(vault.allowance(user1Address,VAULT_ADDRESS));

        //simple redeem with no delegation at all, caller==owner==controller
        vault.requestRedeem(shareAmountToRedeem, user1Address, user1Address);

        // solhint-disable-next-line no-console
        console.log("User %x requested a redeem of %d shares into vault",user1Address,shareAmountToRedeem);

        vm.stopBroadcast();
    }
}