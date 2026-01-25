// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintisCalled;
    address[] public userWithColateralDeposited;
    MockV3Aggregator public ethUSDPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        engine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[1]); 
        wbtc = ERC20Mock(collateralTokens[2]); 

        ethUSDPriceFeed = MockV3Aggregator(
            engine.getCollateralTokenPriceFeed(address(weth))
        );
    }

    function mintDSC(uint256 amount, uint256 addressSeed) public {
        if (userWithColateralDeposited.length == 0) {
            return;
        }
        address sender = userWithColateralDeposited[
            addressSeed % userWithColateralDeposited.length
        ];
        (uint256 totalDSCMinted, uint256 collateralvalueInUSD) = engine
            .getAccountInformation(sender);
        int256 maxDSCtoMint = (int256(collateralvalueInUSD) / 2) -
            int256(totalDSCMinted);
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

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        userWithColateralDeposited.push(msg.sender);
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(
            address(collateral),
            msg.sender
        );

        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        engine.redeemCollateral(address(collateral), amountCollateral);
    }

    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}

contract Invariants is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();
        handler = new Handler(engine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalsupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUSDValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUSDValue(wbtc, totalBtcDeposited);

        console.log("weth value:", wethValue);
        console.log("wbtc value:", wbtcValue);
        console.log("total supply:", totalSupply);
        console.log("Time's Mint called: ", handler.timesMintisCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }
}
