// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import '../src/contracts/lendingSpoke/Spoke.sol'; // Update the import path according to your project structure;


contract DeploySpoke is Script {
    function run() external {
         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Define your deployment parameters
        uint16 chainId = 14; // Example: Ethereum Mainnet
        address wormhole = 0x88505117CA88e7dd2eC6EA1E13f0948db2D50D56; // Address of the Wormhole contract
        address tokenBridge = 0x05ca6037eC51F8b712eD2E6Fa72219FEaE74E153; // Address of the TokenBridge contract
        uint16 hubChainId = 5; // Chain ID of the Hub
        address hubContractAddress = 0x25346B0b34921692AE95B41c1375988056F46438; // Contract address of the Hub contract

        // Deploy the Spoke contract
        Spoke spoke = new Spoke(chainId, wormhole, tokenBridge, hubChainId, hubContractAddress);
        console.log("Spoke deployed at:", address(spoke) , "on chain", spoke.chainId());

        vm.stopBroadcast();
    }
}
