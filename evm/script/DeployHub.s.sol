// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import '../src/contracts/lendingHub/Hub.sol'; // Update the import path according to your project structure;


contract DeployHub is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Parameters for the Hub constructor
        address wormhole = 0x88505117CA88e7dd2eC6EA1E13f0948db2D50D56;
        address tokenBridge = 0x88505117CA88e7dd2eC6EA1E13f0948db2D50D56;
        uint8 consistencyLevel = 1;
        address pythAddress = 0x88505117CA88e7dd2eC6EA1E13f0948db2D50D56;
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

        console.log("Hub deployed at:", address(hub));

        vm.stopBroadcast();
    }
}

