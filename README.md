# 🏦 Decentralized Stablecoin Backend (DSC Engine)

This repository contains the smart contract backend for a decentralized stablecoin (DSC) system built using [Foundry](https://book.getfoundry.sh/) and Solidity. It is designed to maintain price stability through collateralized minting, robust oracle integration, and DAO-grade safety mechanisms.

---

## ⚙️ Architecture Overview

- **Stablecoin Logic**: `DecentralizedStableCoin.sol` — ERC20-compliant token with mint/redeem logic.
- **Engine Core**: `DSCEngine.sol` — handles collateral deposits, debt tracking, and health factor enforcement.
- **Oracle Integration**: `OracleLib.sol` — fetches price feeds via Chainlink and ensures safe conversions.
- **Interfaces**: `AggregatorV3Interface.sol` — Chainlink-compatible interface for price data.

---

## 🧪 Testing Strategy

Tests are written using Foundry’s Forge framework and cover:

- ✅ **Unit Tests**: `DSCEngineTest.t.sol` — core logic validation.
- 🔁 **Fuzz Tests**: `Handler.t.sol`, `InvariantsTest.t.sol` — randomized edge case simulation.
- 🧸 **Mocks**: simulate ERC20 tokens, price feeds, and failure scenarios.

src/
├── interfaces/
├── libraries/
out/
├── script/
test/
├── unit/
├── fuzz/
├── mocks/
.env
.gitignore
foundry.lock


Test folders:
test/
├── unit/
├── fuzz/
└── mocks/

---

## 🚀 Deployment Scripts

Foundry script-based deployment:
- `DeployDSC.s.sol` — deploys core contracts.
- `HelperConfig.s.sol` — manages network-specific config (e.g., price feed addresses).

Run with:
```bash
forge script script/DeployDSC.s.sol --broadcast --verify
