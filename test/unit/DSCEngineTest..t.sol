// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";

contract DSCEngineTest is Test {
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemTo, address indexed token, uint256 amount
    );

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;

    address btcUSDPriceFeed;
    address ethUSDPriceFeed;
    address weth;
    address public wbtc;
    uint256 public deployerKey;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;

    address public USER = makeAddr("user");
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUSDPriceFeed, btcUSDPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
        if (block.chainid == 31_337) {
            vm.deal(USER, STARTING_ERC20_BALANCE);
        }

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
    }

    ////////////////////////
    // Constructor Test's //
    ////////////////////////

    address[] public tokenAddresses;
    address[] public feedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceeFeeds() public {
        tokenAddresses.push(weth);
        feedAddresses.push(ethUSDPriceFeed);
        feedAddresses.push(btcUSDPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
    }

    //////////////////
    // Price Test's //
    //////////////////

    // s-1
    function testGetUsdValue() public view {
        uint256 ethamount = 15e18;

        uint256 expectedUSD = 30000e18; // 15 ETH * $2000/ETH = $30,000
        uint256 actualUSD = engine.getUSDValue(weth, ethamount);
        assertEq(expectedUSD, actualUSD);
    } // *

    // s-2
    function testGetTokenAmountFromUSD() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;

        uint256 actualWeth = engine.getTokenAmountFromUSD(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    } // *

    //////////////////////////////
    // DepositCollateral Test's //
    //////////////////////////////

    // E-1
    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    } // *

    // E-1'2
    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, amountCollateral);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), amountCollateral);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedDepositedAmount = engine.getTokenAmountFromUSD(weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositedAmount, amountCollateral);
    }

    /////////////////////////////////
    // DepositCollateralAndMintDSC //
    /////////////////////////////////

    function testeRevertsIfMintedDSCBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUSDPriceFeed).latestRoundData();
        amountToMint = (amountCollateral * (uint256(price) * engine.getAdditionalFeedPrecision()))
            / engine.getPrecision();
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);

        uint256 expectedHealthFactor =
            engine.calculateHealthFactor(amountToMint, engine.getUSDValue(weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDSC() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountToMint);
        engine.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDSC {
        uint256 userbalance = dsc.balanceOf(USER);
        assertEq(userbalance, amountToMint);
    }

    ////////////////////
    // MintDSC Test's //
    ////////////////////

    // This test need's it's own custom setup
    function testRevertsIsIfMintFails() public {
        // Arrange-setup
        MockFailedMintDSC mockDSC = new MockFailedMintDSC();
        tokenAddresses = [weth];
        feedAddresses = [ethUSDPriceFeed];
        address owner = msg.sender;

        vm.prank(owner);
        DSCEngine mockDSCE = new DSCEngine(tokenAddresses, feedAddresses, address(mockDSC));
        mockDSC.transferOwnership(address(mockDSCE));
        //Arrange - User

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDSCE), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDSCE.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDSC(0);
        vm.stopPrank();
    }

    function testRevertsIfMintAMountBreaksHealthFactor() public depositedCollateral {
        (, int256 price,,,) = MockV3Aggregator(ethUSDPriceFeed).latestRoundData();
        amountToMint = (amountCollateral * (uint256(price) * engine.getAdditionalFeedPrecision()))
            / engine.getPrecision();

        vm.startPrank(USER);
        uint256 expectedHealthFactor =
            engine.calculateHealthFactor(amountToMint, engine.getUSDValue(weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.mintDSC(amountToMint);
        vm.stopPrank();
    }

    function testCanMintDSC() public depositedCollateral {
        vm.startPrank(USER);
        engine.mintDSC(amountToMint);

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, amountToMint);
    }

    function testCannotMintWithoutDepositingCollateral() public {
        vm.startPrank(USER);

        // Do NOT deposit collateral; do NOT approve anything.
        // Try to mint — should revert because health factor will be broken.
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        engine.mintDSC(amountToMint);

        vm.stopPrank();
    }

    ////////////////////
    // BurnDSC Test's //
    ////////////////////

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountToMint);
        engine.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.burnDSC(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        engine.burnDSC(1);
    }

    function testCanBurnDSC() public depositedCollateralAndMintedDSC {
        vm.startPrank(USER);
        dsc.approve(address(engine), amountToMint);
        engine.burnDSC(amountToMint);
        vm.stopPrank();

        uint256 userbalance = dsc.balanceOf(USER);
        assertEq(userbalance, 0);
    }

    /////////////////////////////
    // redeemCollateral Test's //
    /////////////////////////////

    // This test needs it's own setup
    function testRevertsIfTransferFails() public {
        // Arrange - setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDSC = new MockFailedTransfer();
        tokenAddresses = [address(mockDSC)];
        feedAddresses = [ethUSDPriceFeed];
        vm.prank(owner);
        DSCEngine mockDSCE = new DSCEngine(tokenAddresses, feedAddresses, address(mockDSC));
        mockDSC.mint(USER, amountCollateral);

        vm.prank(owner);
        mockDSC.transferOwnership(address(mockDSCE));
        //Arrange-User
        vm.startPrank(USER);
        ERC20Mock(address(mockDSC)).approve(address(mockDSCE), amountCollateral);
        //Act / Assert
        mockDSCE.depositCollateral(address(mockDSC), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDSCE.redeemCollateral(address(mockDSC), amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollatearl() public depositedCollateral {
        vm.startPrank(USER);
        uint256 userBalancebeforeRedeem = engine.getCollateralBalanceOfUser(USER, weth);
        assertEq(userBalancebeforeRedeem, amountCollateral);
        engine.redeemCollateral(weth, amountCollateral);
        uint256 userbalanceAfterRedeem = engine.getCollateralBalanceOfUser(USER, weth);
        assertEq(userbalanceAfterRedeem, 0);
        vm.stopPrank();
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(engine));
        emit CollateralRedeemed(USER, USER, weth, amountCollateral);
        vm.startPrank(USER);
        engine.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();
    }

    //////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testMustRedeemMoreThanZero() public depositedCollateral {
        vm.startPrank(USER);
        dsc.approve(address(engine), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateralForDSC(weth, 0, amountToMint);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        dsc.approve(address(engine), amountToMint);
        engine.redeemCollateralForDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    /////////////////////////
    // healthFactor Test's //
    /////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDSC {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = engine.getHealthFactor(USER);

        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collatareral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 100 = 100 health factor
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDSC {
        int256 ethUSDUpdatedPrice = 18e8; // 1 ETH = $18
        // Remember, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(ethUSDUpdatedPrice);

        uint256 userHealthFactor = engine.getHealthFactor(USER);
        // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION) = 90 / 100 (totalDscMinted) =
        // 0.9
        assert(userHealthFactor == 0.9 ether);
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    // This test needs it's own setUp
    function testMustImproveHealthFactorOnLiquidation() public {
        // Arrange - Setup
        MockMoreDebtDSC mockDSC = new MockMoreDebtDSC(ethUSDPriceFeed);
        tokenAddresses = [weth];
        feedAddresses = [ethUSDPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDSCE = new DSCEngine(tokenAddresses, feedAddresses, address(mockDSC));
        mockDSC.transferOwnership(address(mockDSCE));
        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDSCE), amountCollateral);
        mockDSCE.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        // Arrange - Liquidator
        collateralToCover = 1 ether;
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(mockDSCE), collateralToCover);
        uint256 debtToCover = 10 ether;
        mockDSCE.depositCollateralAndMintDSC(weth, collateralToCover, amountToMint);
        mockDSC.approve(address(mockDSCE), debtToCover);
        // Act
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // Act/Assert
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        mockDSCE.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDSC {
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMintDSC(weth, collateralToCover, amountToMint);
        dsc.approve(address(engine), amountToMint);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        int256 ethUSDUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(ethUSDUpdatedPrice);
        uint256 userhealthFactor = engine.getHealthFactor(USER);

        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
        engine.depositCollateralAndMintDSC(weth, collateralToCover, amountToMint);
        dsc.approve(address(engine), amountToMint);
        engine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
        uint256 expectedWeth = engine.getTokenAmountFromUSD(weth, amountToMint)
            + ((engine.getTokenAmountFromUSD(weth, amountToMint) * engine.getliquidationBonus())
                / engine.getliquidationPercision());

        uint256 hardCodedExpected = 6_111_111_111_111_111_110;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost
        uint256 amountLiquidated = engine.getTokenAmountFromUSD(weth, amountToMint)
            + ((engine.getTokenAmountFromUSD(weth, amountToMint) * engine.getliquidationBonus())
                / engine.getliquidationPercision());

        uint256 USDamountLiquidated = engine.getUSDValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = engine.getUSDValue(weth, amountCollateral) - (USDamountLiquidated);

        (, uint256 userCollateralValueInUSD) = engine.getAccountInformation(USER);
        uint256 hardCodeExpectedValue = 70_000_000_000_000_000_020;
        assertEq(userCollateralValueInUSD, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUSD, hardCodeExpectedValue);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDSCMinted,) = engine.getAccountInformation(liquidator);
        assertEq(liquidatorDSCMinted, amountToMint);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDSCMinted,) = engine.getAccountInformation(USER);
        assertEq(userDSCMinted, 0);
    }

    /////////////////////////////////
    // View & Pure Function Test's //
    /////////////////////////////////

    function testGetCollateralTokenPriceFeed() public view {
        address priceFeed = engine.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUSDPriceFeed);
    }

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = engine.getCollateralTokens();
        assertEq(collateralTokens[1], weth);
        assertEq(collateralTokens[2], wbtc);
    }

    function testGetMinHealthFactor() public view {
        uint256 minHealthFactor = engine.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public view {
        uint256 liquidationThreshold = engine.getliquidationThershold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation() public depositedCollateral {
        (, uint256 collateralValue) = engine.getAccountInformation(USER);
        uint256 expectedCollateralValue = engine.getUSDValue(weth, amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        uint256 collateralBalance = engine.getCollateralBalanceOfUser(USER, weth);
        assertEq(collateralBalance, amountCollateral);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        uint256 collateralValue = engine.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = engine.getUSDValue(weth, amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetDSC() public view {
        address DSCaddress = engine.getDSC();
        assertEq(DSCaddress, address(dsc));
    }

    function testLiquidationPrecision() public view {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = engine.getliquidationPercision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }
}
