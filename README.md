# 🏦 Decentralized Stablecoin Backend (DSC Engine)

A production-grade smart contract backend for a decentralized stablecoin (DSC) system built using [Foundry](https://book.getfoundry.sh/) and Solidity. The system maintains price stability through over-collateralization, robust oracle integration, and sophisticated liquidation mechanics.

---

## 📋 Table of Contents

- [Architecture Overview](#-architecture-overview)
- [Project Structure](#-project-structure)
- [Smart Contracts](#-smart-contracts)
- [Testing Strategy](#-testing-strategy)
- [Installation & Setup](#-installation--setup)
- [Deployment](#-deployment)
- [Key Features](#-key-features)
- [Safety & Security](#-safety--security)

---

## ⚙️ Architecture Overview

The DSC protocol is built on three core pillars:

1. **Stablecoin Logic** (`DecentralizedStableCoin.sol`)
   - ERC20-compliant token with owner-controlled minting/burning
   - Maintains 1:1 peg with USD through collateral requirements

2. **Engine Core** (`DSCEngine.sol`)
   - Handles collateral deposits (WETH, WBTC)
   - Tracks user debt and collateral positions
   - Enforces health factor requirements (minimum 1.0)
   - Manages liquidations with incentive bonuses

3. **Oracle Integration** (`OracleLib.sol`)
   - Fetches real-time prices from Chainlink
   - Safe conversions between collateral and USD values
   - Stale price detection and validation

---

## 📁 Project Structure

```
dsc-backend/
├── src/
│   ├── interfaces/
│   │   └── AggregatorV3Interface.sol      # Chainlink price feed interface
│   │
│   ├── libraries/
│   │   └── OracleLib.sol                  # Oracle price fetching logic
│   │
│   ├── DecentralizedStableCoin.sol        # ERC20 stablecoin token contract
│   └── DSCEngine.sol                      # Core protocol engine (750+ lines)
│
├── script/
│   ├── DeployDSC.s.sol                    # Deployment script
│   └── HelperConfig.s.sol                 # Network-specific configurations
│
├── test/
│   ├── unit/
│   │   ├── DSCEngineTest.t.sol            # 56 comprehensive unit tests
│   │   ├── DecentralizedStabcoins...      # Token contract tests
│   │   └── OracleLibTest.t.sol            # Oracle library tests
│   │
│   ├── fuzz/
│   │   ├── Handler.t.sol                  # Fuzzing handler for invariants
│   │   ├── Invariants.t.sol               # Invariant-based fuzz tests
│   │   └── ContinueOnRevertHandler.t.sol  # Advanced fuzz testing
│   │
│   └── mocks/
│       ├── ERC20Mock.sol                  # Mock ERC20 token
│       ├── MockV3Aggregator.sol           # Mock price feed
│       ├── MockFailedMintDSC.sol          # Simulates mint failures
│       ├── MockFailedTransfer.sol         # Simulates transfer failures
│       └── MockMoreDebtDSC.sol            # High debt mock
│
├── lib/
│   ├── openzeppelin-contracts/            # OpenZeppelin library
│   └── [other dependencies]
│
├── out/
│   └── [compiled contract ABIs]
│
├── broadcast/
│   └── [deployment artifacts]
│
├── cache/
│   └── [build cache]
│
├── .env                                   # Environment variables (not in repo)
├── .gitignore                             # Git ignore rules
├── .github/workflows/                     # CI/CD workflows
├── foundry.lock                           # Locked dependencies
├── foundry.toml                           # Foundry configuration
├── README.md                              # This file
└── Makefile                               # Build shortcuts (optional)
```

---

## 🔐 Smart Contracts

### **DSCEngine.sol** (Core Protocol - 750+ lines)
The heart of the protocol. Features include:

| Feature | Description |
|---------|-------------|
| **Deposit Collateral** | Users deposit WETH/WBTC to back their DSC minting |
| **Mint DSC** | Create stablecoins backed by collateral (max 50% LTV) |
| **Burn DSC** | Destroy stablecoins and recover collateral |
| **Redeem Collateral** | Withdraw collateral (health factor must stay >1.0) |
| **Liquidate** | Penalty mechanism when health factor drops below 1.0 |
| **ETH Direct Repay** | Repay debt directly using ETH (testnet version) |
| **Health Factor Tracking** | Real-time collateral-to-debt ratio monitoring |

**Key Constants:**
```solidity
LIQUIDATION_THRESHOLD = 50%    // Must maintain 50% collateral ratio
LIQUIDATION_BONUS = 10%        // Liquidators get 10% bonus
MIN_HEALTH_FACTOR = 1.0e18     // Minimum health factor before liquidation
```

### **DecentralizedStableCoin.sol** (Token - ERC20)
- Standard ERC20 implementation with owner controls
- Mint/burn restricted to DSCEngine
- Transfer and approval mechanisms

### **OracleLib.sol** (Oracle Integration)
- Fetches prices from Chainlink V3 aggregators
- Validates price freshness and range
- Handles precision conversions (8 decimals → 18 decimals)

---

## 🧪 Testing Strategy

### **Unit Tests** (56 tests - ALL PASSING ✅)

**Categories:**

| Test Category | Count | Purpose |
|--------------|-------|---------|
| Constructor Tests | 1 | Validates initialization |
| Price Tests | 2 | Tests oracle price conversions |
| Deposit Tests | 6 | Collateral deposit scenarios |
| Mint Tests | 8 | DSC minting logic |
| Burn Tests | 3 | DSC burning logic |
| Redeem Tests | 5 | Collateral redemption |
| Liquidation Tests | 8 | Liquidation mechanics |
| Health Factor Tests | 2 | Health factor calculations |
| ETH Deposit Tests | 4 | Native ETH handling |
| Max Mintable Tests | 3 | Maximum DSC calculation |
| ETH Repay Tests | 3 | ETH-based debt repayment |
| Multi-Collateral Tests | 1 | Multiple collateral types |
| View Functions | 5 | Getter function validation |

**Run Tests:**
```bash
# Run all tests
forge test

# Run specific test
forge test --match-contract DSCEngineTest

# Run with verbose output
forge test -vv

# Gas estimation
forge test --gas-report
```

### **Fuzz Tests** (Advanced - Optional)
- `Handler.t.sol` - Weighted function calls on random inputs
- `InvariantsTest.t.sol` - Protocol invariant enforcement
- Tests 100+ random scenarios per run

### **Mock Contracts**
- `ERC20Mock.sol` - Simulates token behavior
- `MockV3Aggregator.sol` - Simulates Chainlink price feeds
- `MockFailedMintDSC.sol` - Tests mint failure handling
- `MockFailedTransfer.sol` - Tests transfer failure handling
- `MockMoreDebtDSC.sol` - Tests high-debt scenarios

---

## 🚀 Installation & Setup

### **Prerequisites**
- Rust 1.70+
- Git
- Node.js 18+ (optional, for scripting)

### **Install Foundry**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### **Clone & Setup**
```bash
git clone https://github.com/sanskar717/stablecoin-backend.git
cd stablecoin-backend

# Install dependencies
forge install

# Create .env file
cp .env.example .env
# Fill in your RPC_URL and PRIVATE_KEY
```

### **Compile Contracts**
```bash
forge build
```

---

## 📤 Deployment

### **Local Network (Anvil)**
```bash
# Start local chain
anvil

# In another terminal, deploy
forge script script/DeployDSC.s.sol --broadcast -vvv

# With localhost
forge script script/DeployDSC.s.sol --broadcast --rpc-url http://localhost:8545 -vvv
```

### **Testnet Deployment**
```bash
# Set environment variables
export SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
export PRIVATE_KEY=0x...

# Deploy to Sepolia
forge script script/DeployDSC.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast -vvv
```

### **Configuration**
Update `script/HelperConfig.s.sol` for different networks:
- Sepolia: Chainlink price feeds
- Localhost: Mock price feeds
- Mainnet: Live Chainlink oracles

---

## ✨ Key Features

### **1. Over-Collateralization**
- Users must deposit collateral worth >2x their DSC debt
- Prevents system under-collateralization
- Health factor enforces this ratio

### **2. Liquidation Mechanism**
- If health factor drops below 1.0, anyone can liquidate
- Liquidators receive 10% bonus on collateral
- User's debt is covered, protocol stays solvent

### **3. Multi-Collateral Support**
- WETH support (primary)
- WBTC support (secondary)
- Easy to add more via configuration

### **4. Native ETH Support**
- `depositETHOnly()` - Deposit raw ETH
- `repayDSCWithETHDirect()` - Repay using ETH
- Automatic ETH ↔ collateral conversion

### **5. Oracle Integration**
- Chainlink V3 price feeds
- Stale price detection
- Failsafe mechanisms

---

## 🔒 Safety & Security

### **Reentrancy Protection**
```solidity
nonReentrant   // OpenZeppelin guard on all state-changing functions
```

### **Health Factor Enforcement**
```solidity
_revertIfHealthFactorIsBroken()   // Validates before every operation
```

### **Checks-Effects-Interactions Pattern**
- All checks first
- State changes second
- External calls last

### **Overflow/Underflow Protection**
- Solidity 0.8.20+ (automatic checks)
- SafeMath via compiler

### **Audit Recommendations**
- ✅ 56 unit tests covering 750+ lines
- ✅ Comprehensive error handling
- ⚠️ Production deployment recommended after formal audit

---

## 📊 Test Coverage

```
Total Tests: 56
Pass Rate: 100% ✅
Lines of Code: 750+
Test Categories: 13
Mock Contracts: 5
```

**Recent Test Run:**
```
Ran 56 tests for test/unit/DSCEngineTest.t.sol:DSCEngineTest
[PASS] testCanDepositETHOnly() (gas: 47926)
[PASS] testGetMaxMintableAmount() (gas: 116952)
[PASS] testLiquidationPayoutIsCorrect() (gas: 491454)
... (53 more tests)
Suite result: ok. 56 passed; 0 failed; 0 skipped;
```

---

## 🔗 Connected Repositories

- **Frontend**: [stablecoin-frontend](https://github.com/sanskar717/stablecoin-frontend)
  - React/Next.js UI for protocol interaction
  - Health factor monitoring
  - Transaction history

---

## 📝 License

MIT License - see LICENSE file for details

---

## 🤝 Contributing

Issues and pull requests welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Add tests for new features
4. Submit a pull request

---

## 📞 Support

For questions or issues:
- Open a GitHub issue
- Email: sanskar.gupta@example.com
- Discord: [Link to community]

---

**Last Updated:** February 2025  
**Solidity Version:** 0.8.20  
**Foundry Version:** Latest
