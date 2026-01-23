// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {OracleLib, AggregatorV3Interface} from "./libraries/OracleLib.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DSCEngine
 * @author sanskar gupta
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {
    ////////////
    // Errors //
    ////////////

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    ///////////
    // Types //
    ///////////

    using OracleLib for AggregatorV3Interface;

    /////////////////////
    // state Variables //
    /////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ////////////
    // Events //
    ////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemTo, address indexed token, uint256 amount
    );

    ///////////////
    // Modifiers //
    ///////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ///////////////
    // Functions //
    ///////////////

    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////
    // External Functions //
    ////////////////////////

    /*
     * @param TokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscTOMint The amount of Decentralized Stable Coin to mint
     * @notice This funtion will deposit your collateral and mint DSC in one transaction
     */

    /**
     * @notice Deposit native ETH as collateral WITHOUT auto-minting DSC
     * @dev Users deposit first, then manually mint DSC later
     * This gives users more control compared to depositETHAndMintDSC()
     */

    function depositETHOnly() public payable moreThanZero(msg.value) nonReentrant {
        // Track ETH collateral using address(0) as marker for native ETH
        s_collateralDeposited[msg.sender][address(0)] += msg.value;
        emit CollateralDeposited(msg.sender, address(0), msg.value);
    }

    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscTOMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscTOMint);
    }

    /*
     * @notice Follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    } // *

    /*
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountDSCToBurn The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC to Burn
     * This Function burn's DSC & redeem's underlying collateral in one transction
     */

    // CORRECT VERSION
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
        moreThanZero(amountCollateral)
        isAllowToken(tokenCollateralAddress)
    {
        _burnDSC(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // In order to redeem collateral:
    // 1. Health facator must be over 1 AFTER collateral pulled
    // DRY: Don't Repeat Yourself
    // CEI: Checks-Effects-Interactions

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice Follows CEI
     * @param amountDSCToMint The amount of Decentralized Stable Coin to mint
     * @param They must have more collateral value than the minimum threshold
     */

    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @param collateral The ERC20 collateral address to liquidate From the user
     * @param The user who has broken the Health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param DebtToCover The amount of DSC want to improve the useres Health Factor
     * @notice You can partially liquidated a user.
     * @notice You will get a liquidation bouns  for taking the user funds
     * @notice This Function working assumes the protocol will be roughly 200% overcollateralized in order for This to work.
     * @notice A Known bug would be if the protocal were 100% or less Then collateralized, Then we wouldn't be able to incentive the liquidators.
     * For example, if The price of the collateral plummeted before anyone could be liquidated.
     *
     * Follows CEI: checks, Effect, Interaction's
     */

    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 satrtingUserHealthFactor = _healthFactor(user);
        if (satrtingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(collateral, debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        // We need to burn the DSC
        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= satrtingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ////////////////////////
    // Private  Functions //
    ////////////////////////

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        if (tokenCollateralAddress == address(0)) {
            (bool success,) = payable(to).call{value: amountCollateral}("");
            if (!success) {
                revert DSCEngine__TransferFailed();
            }
        } else {
            bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
            if (!success) {
                revert DSCEngine__TransferFailed();
            }
        }

    }

    function _burnDSC(uint256 amountDSCToBurn, address onBehalfOf, address DSCFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDSCToBurn;
        bool success = i_dsc.transferFrom(DSCFrom, address(this), amountDSCToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDSCToBurn);
    }

    ///////////////////////////////////////
    // Private & Internal View Functions //
    ///////////////////////////////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
    }

    /**
     * @notice Get maximum DSC amount user can safely mint
     * @param user The address to check
     * @return maxMintable Maximum DSC that can be minted without breaking health factor
     */

    function getMaxMintableAmount(address user) external view returns (uint256 maxMintable) {
        uint256 collateralValueInUSD = getAccountCollateralValue(user);
        uint256 alreadyMinted = s_DSCMinted[user];
        uint256 maxAllowed = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        if (maxAllowed > alreadyMinted) {
            maxMintable = maxAllowed - alreadyMinted;
        } else {
            maxMintable = 0;
        }
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUSD);
    }

    function _getUSDValue(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function _getETHPriceInUSD() private view returns (uint256) {
        address ethPriceFeed = s_priceFeeds[address(0)];

        if (ethPriceFeed == address(0)) {
            revert("No ETH price feed");
        }

        AggregatorV3Interface priceFeed = AggregatorV3Interface(ethPriceFeed);

        (, int256 price,,,) = priceFeed.latestRoundData();

        if (price <= 0) {
            revert("Invalid price");
        }
        return uint256(price) * ADDITIONAL_FEED_PRECISION;
    }

    function _calculateHealthFactor(uint256 totalDSCMinted, uint256 collateralValueInUSD)
        internal
        pure
        returns (uint256)
    {
        if (totalDSCMinted == 0) return type(uint256).max;
        uint256 collateralAdjustForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustForThreshold * PRECISION) / totalDSCMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /////////////////////////////////////////////
    // Public & External View & pure Functions //
    /////////////////////////////////////////////

    /*
     * @dev low-level interal Function do not call unless the Function calling it is checking for health factors being broken
     */

    function calculateHealthFactor(uint256 totalDSCMinted, uint256 collateralValueInUSD)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUSD);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        return _getAccountInformation(user);
    }

    function getUSDValue(address token, uint256 amount) external view returns (uint256) {
        return _getUSDValue(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        uint256 nativeEthAmount = s_collateralDeposited[user][address(0)];
        if (nativeEthAmount > 0) {
            uint256 ethPriceInUSD = _getETHPriceInUSD();
            totalCollateralValueInUSD += (nativeEthAmount * ethPriceInUSD) / PRECISION;
        }

        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            if (amount > 0) {
                totalCollateralValueInUSD += _getUSDValue(token, amount);
            }
        }
        return totalCollateralValueInUSD;
    }

    function getTokenAmountFromUSD(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getliquidationThershold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getliquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getliquidationPercision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDSC() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getAccountInfo(address user) external view returns (uint256 totalDSCMinted, uint256 collateralValueInUSD) {
        (totalDSCMinted, collateralValueInUSD) = _getAccountInformation(user);
    }
}
