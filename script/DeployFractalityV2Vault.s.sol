// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "@forge-std/Script.sol";
import {FractalityV2Vault} from "../src/FractalityV2Vault.sol";
import {console} from "@forge-std/console.sol";


//deploy with forge script script/DeployFractalityV2Vault.s.sol --fork-url sepolia --broadcast
//verify with forge verify-contract 0x17d2575Ef048476589018411509ae2D3d4098E29 ./src/FractalityV2Vault.sol:FractalityV2Vault --rpc-url sepolia --watch --guess-constructor-args
contract DeployFractalityV2Vault is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address MOCK_ERC20_ADDRESS = vm.envAddress("MOCK_ERC20_ADDRESS");

        uint16 redeemFeeBasisPoints = 20;// 0.20%
        uint32 claimableDelay = 86400; // 1 day
        uint8 strategyType = 0; //EOA

        address strategyAddress = address(0xfa08ab4bc646cA5bBf2f649d4e0EaDFE0e31Ff2C);
        address redeemFeeCollector = vm.addr(deployerPrivateKey);
        address pnlReporter = vm.addr(deployerPrivateKey);

        uint128 maxDepositPerTransaction=1000000 * 1e18; //100,000$
        uint128 minDepositPerTransaction=100 * 1e18; //100$
        uint256 maxVaultCapacity=100000000 * 1e18; //100 million$

        vm.startBroadcast(deployerPrivateKey);

        FractalityV2Vault.ConstructorParams memory params = FractalityV2Vault.ConstructorParams({
            asset: MOCK_ERC20_ADDRESS,
            redeemFeeBasisPoints: redeemFeeBasisPoints, 
            claimableDelay: claimableDelay,
            strategyType: strategyType,
            strategyAddress: strategyAddress,
            redeemFeeCollector: redeemFeeCollector, 
            pnlReporter: pnlReporter, 
            maxDepositPerTransaction: maxDepositPerTransaction,
            minDepositPerTransaction: minDepositPerTransaction,
            maxVaultCapacity: maxVaultCapacity,
            strategyName: "Test Strategy",
            strategyURI: "https://example.com/strategy",
            vaultSharesName: "Fractality V2 Vault Test Shares",
            vaultSharesSymbol: "FV2VST"
        });

        FractalityV2Vault vault = new FractalityV2Vault(params);
        // solhint-disable-next-line no-console
        console.log("FractalityV2Vault deployed at:", address(vault));

        vm.stopBroadcast();
    }
}