// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import '../src/contracts/lendingHub/Hub.sol'; // Update the import path according to your project structure;


contract DeployHub is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Parameters for the Hub constructor
        address wormhole = 0x0CBE91CF822c73C2315FB05100C2F714765d5c20;
        address tokenBridge = 0x377D55a7928c046E18eEbb61977e714d2a76472a;
        uint8 consistencyLevel = 200;
        address pythAddress = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C;
        uint8 oracleMode = 0;
        uint64 priceStandardDeviations = 424;
        uint64 priceStandardDeviationsPrecision = 10**2;
        uint256 maxLiquidationBonus = 10**6;
        uint256 maxLiquidationPortion = 10**6;
        uint256 maxLiquidationPortionPrecision = 10**6;
        uint256 interestAccrualIndexPrecision = 10**6;
        uint256 collateralizationRatioPrecision = 10**6;

        Hub hub = new Hub(
            wormhole,
            tokenBridge,
            consistencyLevel,
            pythAddress,
            oracleMode,
            priceStandardDeviations,
            priceStandardDeviationsPrecision,
            maxLiquidationBonus,
            maxLiquidationPortion,
            maxLiquidationPortionPrecision,
            interestAccrualIndexPrecision,
            collateralizationRatioPrecision
        );

        console.log("Spoke deployed at:", address(hub));

        vm.stopBroadcast();
    }
}

