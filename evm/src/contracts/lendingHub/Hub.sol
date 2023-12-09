// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../interfaces/IWormhole.sol";

import "./HubSetters.sol";
import "../HubSpokeStructs.sol";
import "../HubSpokeMessages.sol";
import "./HubGetters.sol";
import "./HubChecks.sol";
import "./HubWormholeUtilities.sol";

contract Hub is HubSpokeStructs, HubSpokeMessages, HubGetters, HubSetters, HubWormholeUtilities, HubChecks {

    constructor(
        address wormhole,
        address tokenBridge,
        uint8 consistencyLevel,

        address pythAddress,
        uint8 oracleMode,
        uint64 priceStandardDeviations,
        uint64 priceStandardDeviationsPrecision,

        uint256 maxLiquidationBonus,
        uint256 maxLiquidationPortion,
        uint256 maxLiquidationPortionPrecision,
        uint256 interestAccrualIndexPrecision,
        uint256 collateralizationRatioPrecision
    ) {
        require(interestAccrualIndexPrecision <= 10 ** 6);
        require(collateralizationRatioPrecision <= 10 ** 6);
        require(maxLiquidationPortionPrecision <= 10 ** 6);
        require(priceStandardDeviationsPrecision <= 10 ** 6);

        setWormhole(wormhole);
        setTokenBridge(tokenBridge);
        setPyth(pythAddress);
        setOracleMode(oracleMode);
        setConsistencyLevel(consistencyLevel);
        setInterestAccrualIndexPrecision(interestAccrualIndexPrecision);
        setCollateralizationRatioPrecision(collateralizationRatioPrecision);
        setMaxLiquidationBonus(maxLiquidationBonus); 
        setMaxLiquidationPortion(maxLiquidationPortion);
        setMaxLiquidationPortionPrecision(maxLiquidationPortionPrecision);
        setMockPyth(60 * (10 ** 18), 0);
        setPriceStandardDeviations(priceStandardDeviations);
        setPriceStandardDeviationsPrecision(priceStandardDeviationsPrecision);
    }

    function registerAsset(
        address assetAddress,
        uint256 collateralizationRatioDeposit,
        uint256 collateralizationRatioBorrow,
        uint64 ratePrecision,
        uint256[] memory kinks,
        uint256[] memory rates,
        uint256 reserveFactor,
        uint256 reservePrecision,
        bytes32 pythId
    ) public onlyOwner {
        require(!getAssetInfo(assetAddress).exists, "Asset already registered");

        allowAsset(assetAddress);

        PiecewiseInterestRateModel memory interestRateModel = PiecewiseInterestRateModel({
            ratePrecision: ratePrecision,
            kinks: kinks,
            rates: rates,
            reserveFactor: reserveFactor,
            reservePrecision: reservePrecision
        });

        uint8 decimals = getDecimals(assetAddress);
        require(ratePrecision <= 10 ** 6);
        require(reservePrecision <= 10 ** 6);

        AssetInfo memory info = AssetInfo({
            collateralizationRatioDeposit: collateralizationRatioDeposit,
            collateralizationRatioBorrow: collateralizationRatioBorrow,
            pythId: pythId,
            decimals: decimals,
            interestRateModel: interestRateModel,
            exists: true
        });

        registerAssetInfo(assetAddress, info);
        setLastActivityBlockTimestamp(assetAddress, block.timestamp);
    }

    // Registers a new spoke contract for a given chain ID.
    // Only callable by the contract owner.
    function registerSpoke(uint16 chainId, address spokeContractAddress) public onlyOwner {
        require(spokeContractAddress != address(0), "Invalid spoke contract address");
        registerSpokeContract(chainId, spokeContractAddress);
    }

    // Completes a deposit action. The encoded message should contain the necessary information for the deposit.
    function completeDeposit(bytes memory encodedMessage) public {
        require(encodedMessage.length > 0, "Encoded message cannot be empty");
        completeAction(encodedMessage, true);
    }

    // Completes a withdraw action. The encoded message should contain the necessary information for the withdrawal.
    function completeWithdraw(bytes memory encodedMessage) public {
        require(encodedMessage.length > 0, "Encoded message cannot be empty");
        completeAction(encodedMessage, false);
    }

    // Completes a borrow action. The encoded message should contain the necessary information for the borrow.
    function completeBorrow(bytes memory encodedMessage) public {
        require(encodedMessage.length > 0, "Encoded message cannot be empty");
        completeAction(encodedMessage, false);
    }

    // Completes a repay action. The encoded message should contain the necessary information for the repayment.
    function completeRepay(bytes memory encodedMessage) public {
        require(encodedMessage.length > 0, "Encoded message cannot be empty");
        completeAction(encodedMessage, true);
    }

    function completeAction(bytes memory encodedMessage, bool isTokenBridgePayload)
        internal
        returns (bool completed, uint64 sequence)
    {
        bytes memory encodedActionPayload;
        IWormhole.VM memory parsed = getWormholeParsed(encodedMessage);

        if (isTokenBridgePayload) {
            encodedActionPayload = extractPayloadFromTransferPayload(getTransferPayload(encodedMessage));
        } else {
            verifySenderIsSpoke(parsed.emitterChainId, address(uint160(uint256(parsed.emitterAddress))));
            encodedActionPayload = parsed.payload;
        }

        ActionPayload memory params = decodeActionPayload(encodedActionPayload);
        Action action = Action(params.action);

        checkValidAddress(params.assetAddress);
        completed = true;
        bool transferTokensToSender = false;

        updateAccrualIndices(params.assetAddress);

        if (action == Action.Withdraw) {
            checkAllowedToWithdraw(params.sender, params.assetAddress, params.assetAmount);
            transferTokensToSender = true;
        } else if (action == Action.Borrow) {
            checkAllowedToBorrow(params.sender, params.assetAddress, params.assetAmount);
            transferTokensToSender = true;
        } else if (action == Action.Repay) {
            completed = allowedToRepay(params.sender, params.assetAddress, params.assetAmount);
            if (!completed) {
                transferTokensToSender = true;
            }
        }

        if (completed) {
            logActionOnHub(action, params.sender, params.assetAddress, params.assetAmount);
        }

        if (transferTokensToSender) {
            sequence = transferTokens(params.sender, params.assetAddress, params.assetAmount, parsed.emitterChainId);
        }
    }


    function liquidation(
        address vault,
        address[] memory assetRepayAddresses,
        uint256[] memory assetRepayAmounts,
        address[] memory assetReceiptAddresses,
        uint256[] memory assetReceiptAmounts
    ) public {

        checkLiquidationInputsValid(assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts);


        checkAllowedToLiquidate(
            vault, assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts
        );


        for (uint256 i = 0; i < assetRepayAddresses.length; i++) {
            logActionOnHub(Action.Repay, vault, assetRepayAddresses[i], assetRepayAmounts[i]);
        }


        for (uint256 i = 0; i < assetReceiptAddresses.length; i++) {
            logActionOnHub(Action.Withdraw, vault, assetReceiptAddresses[i], assetReceiptAmounts[i]);
        }


        for (uint256 i = 0; i < assetRepayAddresses.length; i++) {
            SafeERC20.safeTransferFrom(IERC20(assetRepayAddresses[i]), msg.sender, address(this), assetRepayAmounts[i]);
        }

        for (uint256 i = 0; i < assetReceiptAddresses.length; i++) {
            SafeERC20.safeTransfer(IERC20(assetReceiptAddresses[i]), msg.sender, assetReceiptAmounts[i]);
        }
    }

    function logActionOnHub(Action action, address vault, address assetAddress, uint256 amount)
        internal
    {

        VaultAmount memory vaultAmounts = getVaultAmounts(vault, assetAddress);
        VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);

        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        if (action == Action.Deposit) {
            uint256 normalizedDeposit = normalizeAmount(amount, indices.deposited, Round.DOWN);
            vaultAmounts.deposited += normalizedDeposit;
            globalAmounts.deposited += normalizedDeposit;
        } else if (action == Action.Withdraw) {
            uint256 normalizedWithdraw = normalizeAmount(amount, indices.deposited, Round.UP);
            vaultAmounts.deposited -= normalizedWithdraw;
            globalAmounts.deposited -= normalizedWithdraw;
        } else if (action == Action.Borrow) {
            uint256 normalizedBorrow = normalizeAmount(amount, indices.borrowed, Round.UP);
            vaultAmounts.borrowed += normalizedBorrow;
            globalAmounts.borrowed += normalizedBorrow;
        } else if (action == Action.Repay) {
            uint256 normalizedRepay = normalizeAmount(amount, indices.borrowed, Round.DOWN);
            if(normalizedRepay > vaultAmounts.borrowed) {
                normalizedRepay = vaultAmounts.borrowed;
            }
            vaultAmounts.borrowed -= normalizedRepay;
            globalAmounts.borrowed -= normalizedRepay;
        }

        setVaultAmounts(vault, assetAddress, vaultAmounts);
        setGlobalAmounts(assetAddress, globalAmounts);
    }
}
