// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "@forge-std/Script.sol";
import {FractalityV2Vault} from "../src/FractalityV2Vault.sol";
import {console} from "@forge-std/console.sol";

//run via: forge script script/ReportPNL.s.sol --fork-url sepolia --broadcast
contract ReportPNL is Script {
    function run() external {
        uint256 pnlReporterPrivateKey = vm.envUint("PRIVATE_KEY");

        address VAULT_ADDRESS = vm.envAddress("VAULT_ADDRESS");

        bool isProfit = true;
        uint256 pnlAmount = 10 * 1e18;

        FractalityV2Vault vault = FractalityV2Vault(VAULT_ADDRESS);

        vm.startBroadcast(pnlReporterPrivateKey);

        if (isProfit) {
            vault.reportProfits(pnlAmount, "ProfitInfo");
            // solhint-disable-next-line no-console
            console.log(
                "User %x reported a profit of  %d",
                vm.addr(pnlReporterPrivateKey),
                pnlAmount
            );
        } else {
            vault.reportLosses(pnlAmount, "LossInfo");
            // solhint-disable-next-line no-console
           console.log(
                "User %x reported a loss of  %d",
                vm.addr(pnlReporterPrivateKey),
                pnlAmount
            );
        }

        vm.stopBroadcast();
    }
}
