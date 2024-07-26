// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "@forge-std/Script.sol";

import {MockERC20} from "../src/MockERC20.sol";
import {console} from "@forge-std/console.sol";
//To run, run forge script script/DeployMockERC20.s.sol --fork-url sepolia --broadcast
//To verify run forge verify-contract 0x0285d2cc5A030A8313Cd3f7643D01C1a14cAca50 ./src/MockERC20.sol:MockERC20 --rpc-url sepolia --watch --guess-constructor-args
contract DeployMockERC20 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 initSupply = vm.envUint("MOCK_ERC20_INIT_SUPPLY");

        vm.startBroadcast(deployerPrivateKey);

        MockERC20 token = new MockERC20(initSupply);

        vm.stopBroadcast();

        // solhint-disable-next-line no-console
        console.log("ERC20 token deployed to:", address(token));
    }
}