# DSC Backend (Decentralized Stablecoin)

This repository contains the **smart contract backend** for a decentralized, overcollateralized stablecoin system built using **Solidity** and **Foundry**.

The project is inspired by modern DeFi protocols and is being developed as part of an **ETHGlobal hackathon**.

---

## 🧠 Project Overview

The goal of this project is to build a **decentralized stablecoin (DSC)** that:
- Is backed by crypto collateral (e.g. ETH)
- Uses on-chain price feeds (Chainlink)
- Allows users to:
  - Deposit collateral
  - Mint stablecoins
  - Repay debt
  - Withdraw collateral
- Maintains protocol safety using a **health factor**

---

## 🏗️ Architecture (Planned)

- **DSC Token**
  - ERC20 stablecoin
  - Minted and burned by the engine contract

- **DSC Engine**
  - Core protocol logic
  - Handles collateral deposits, minting, repayment, and liquidation
  - Integrates Chainlink price feeds

- **Price Feeds**
  - Chainlink AggregatorV3Interface
  - Used for real-time collateral valuation

---

## 🛠️ Tech Stack

- **Solidity** `^0.8.x`
- **Foundry** (forge, cast)
- **OpenZeppelin Contracts**
- **Chainlink Price Feeds**

---
