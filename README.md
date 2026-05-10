# UpgradeableVault

A transparent upgradeable vault protocol built from scratch using EIP-1967 storage slots and delegatecall.

Built to understand how production DeFi protocols handle upgrades without losing user funds.

## Live Deployment (Sepolia)

| Contract | Address |
|---|---|
| Proxy | [0x70A6f30Cf845017f0E9F36e7e30AA1e51C10707e](https://sepolia.etherscan.io/address/0x70A6f30Cf845017f0E9F36e7e30AA1e51C10707e) |
| VaultV1 Implementation | [0x113883C1ce50E562F2b8F4df9116E67Cfd2E57D1](https://sepolia.etherscan.io/address/0x113883C1ce50E562F2b8F4df9116E67Cfd2E57D1) |
| VaultV2 Implementation | [0xcb518D4c770fE60eFBb9C1dbeeA909ac4220C64a](https://sepolia.etherscan.io/address/0xcb518D4c770fE60eFBb9C1dbeeA909ac4220C64a) |
| ProxyAdmin | [0x55E2Ba793bAA26b491312D87C1456c7BE9d0dc4b](https://sepolia.etherscan.io/address/0x55E2Ba793bAA26b491312D87C1456c7BE9d0dc4b) |

## What This Is

Most DeFi protocols need to fix bugs or add features after deployment. The problem is you can't change a deployed contract. The solution is a proxy pattern — users interact with a proxy contract that delegates all calls to an implementation contract. To upgrade, you just point the proxy to a new implementation. User balances and storage survive untouched.

This project implements that pattern from scratch, without relying on OpenZeppelin's pre-built proxy contracts.

## How It Works

```
User
  │
  ▼
Proxy.sol  ←── holds all storage (user balances, fees, strategies)
  │
  │  delegatecall
  ▼
VaultV1.sol  ←── holds the logic (deposit, withdraw, harvest)
```

When the owner upgrades to V2:

```
Proxy.sol  ←── same storage, nothing wiped
  │
  │  delegatecall
  ▼
VaultV2.sol  ←── new logic (adds withdrawal fee)
```

User balances survive. Storage survives. Only the logic changes.

## Why EIP-1967 Storage Slots

The naive approach is to store the implementation address at slot 0. The problem is VaultV1 also has state variables starting at slot 0. When delegatecall runs VaultV1's code inside the Proxy's storage, slot 0 gets overwritten with vault data — destroying the implementation address.

EIP-1967 solves this by storing the implementation address at a slot derived from a hash:

```solidity
bytes32 private constant IMPLEMENTATION_SLOT =
    bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
```

This slot is so far into the 2²⁵⁶ storage space that no state variable will ever accidentally land there. Same approach used by Uniswap, Aave, and most production protocols.

## Contracts

**Proxy.sol**
- Stores implementation address at EIP-1967 slot
- Fallback function delegates all calls to implementation using assembly
- Only admin can upgrade

**ProxyAdmin.sol**
- Owns the upgrade rights
- Separates upgrade control from vault ownership

**VaultV1.sol**
- ERC4626 upgradeable vault
- Accepts USDC deposits, issues shares
- Pluggable yield strategies
- Performance fee on harvested profit
- Emergency pause

**VaultV2.sol**
- Inherits VaultV1
- Adds withdrawal fee (max 5%)
- Storage layout preserved from V1

## The Upgrade Test

The most important test in this project:

```solidity
function test_storage_survives_upgrade() public {
    vm.prank(owner);
    vault.setPerformanceFee(500);

    vm.prank(owner);
    proxy.upgrade(address(vaultV2impl));

    VaultV2 vaultV2 = VaultV2(address(proxy));
    assertEq(vaultV2.performanceFee(), 500); // still 500 after upgrade
}
```

If this test fails it means user balances and protocol state get wiped on every upgrade. That would be catastrophic on a live protocol. This test proves the storage layout is correct.

## Tests

```bash
forge test
```

```
[PASS] test_deposit_gives_shares
[PASS] test_deposit_too_small_reverts
[PASS] test_deposit_blocked_when_paused
[PASS] test_two_users_deposit
[PASS] test_first_deposit_shares_equal_assets
[PASS] test_withdraw_returns_full_amount
[PASS] test_withdraw_too_small_reverts
[PASS] test_upgrade_keeps_user_shares
[PASS] test_upgrade_keeps_storage
[PASS] test_random_user_cannot_upgrade
[PASS] test_v2_withdrawal_fee_takes_cut
[PASS] test_v2_no_fee_returns_exact_amount
[PASS] test_only_owner_can_pause
[PASS] test_owner_sets_performance_fee
[PASS] test_performance_fee_above_max_reverts
[PASS] test_random_user_cannot_set_fee

16 passing
```

## Running Locally

```bash
git clone https://github.com/Pawar7349/UpgradeableVault
cd UpgradeableVault
forge install
forge test
```

## What I Learned Building This

The hardest part was understanding why storage layout between the proxy and implementation must match exactly.

When delegatecall runs, it borrows the implementation's bytecode but executes it in the proxy's storage context. If VaultV2 adds a new state variable before an existing one, every existing variable shifts down one slot and all stored values point to wrong data.

The `__gap` variable in VaultV1 reserves 50 empty slots specifically to prevent this — giving room to add new variables in V1 without breaking V2's layout.

The other thing that took time to understand was why EIP-1967 slots exist. Storing the implementation address at slot 0 causes a storage collision with the vault's own variables. The hash-derived slot puts the implementation address somewhere nothing else will ever land.

## Stack

- Solidity 0.8.24
- Foundry
- OpenZeppelin Upgradeable Contracts

---

Built by [Pratik Pawar](https://github.com/Pawar7349) · [Twitter](https://x.com/PratikP43786754) · [LinkedIn](https://www.linkedin.com/in/pratik-pawar-600731237/)