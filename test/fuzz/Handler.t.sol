// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

// Price Feed

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // its allow maxa uint96 value If we use max uint256 cause its revrt

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintisCalled;
    address[] public userWithColateralDeposited;
    MockV3Aggregator public ethUSDPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        engine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUSDPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }

    function mintDSC(uint256 amount, uint256 addressSeed) public {
        if (userWithColateralDeposited.length == 0) {
            return;
        }
        address sender = userWithColateralDeposited[addressSeed % userWithColateralDeposited.length];
        (uint256 totalDSCMinted, uint256 collateralvalueInUSD) = engine.getAccountInformation(sender);
        int256 maxDSCtoMint = (int256(collateralvalueInUSD) / 2) - int256(totalDSCMinted);
        if (maxDSCtoMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDSCtoMint));
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        engine.mintDSC(amount);
        vm.stopPrank();
        timesMintisCalled++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        userWithColateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(address(collateral), msg.sender);

        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        engine.redeemCollateral(address(collateral), amountCollateral);
    }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
