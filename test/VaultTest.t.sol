// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Proxy.sol";
import "../src/ProxyAdmin.sol";
import "../src/VaultV1.sol";
import "../src/VaultV2.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function decimals() public pure override returns (uint8) { return 6; }
}

contract VaultTest is Test {

    MockUSDC usdc;
    Proxy proxy;
    ProxyAdmin proxyAdmin;
    VaultV1 vaultV1impl;
    VaultV2 vaultV2impl;
    VaultV1 vault;

    address owner        = makeAddr("owner");
    address alice        = makeAddr("alice");
    address bob          = makeAddr("bob");
    address feeRecipient = makeAddr("feeRecipient");
    address randomGuy    = makeAddr("randomGuy");

    // 1000 USDC and 500 USDC in 6 decimal format
    uint256 constant DEPOSIT_1000 = 1000 * 1e6;
    uint256 constant DEPOSIT_500  = 500  * 1e6;

    function setUp() public {
        vm.startPrank(owner);

        usdc        = new MockUSDC();
        vaultV1impl = new VaultV1();
        vaultV2impl = new VaultV2();
        proxyAdmin  = new ProxyAdmin();
        proxy       = new Proxy(address(vaultV1impl));

        vault = VaultV1(address(proxy));
        vault.initialize(address(usdc), "Vault USDC", "vUSDC", feeRecipient);
        vault.unpause();

        vm.stopPrank();
    }

    // helper — mint USDC, approve vault, deposit
    function _deposit(address _user, uint256 _amount) internal {
        usdc.mint(_user, _amount);
        vm.startPrank(_user);
        usdc.approve(address(proxy), _amount);
        vault.deposit(_amount, _user);
        vm.stopPrank();
    }

    // DEPOSIT 

    // basic deposit — user gets shares, vault holds USDC
    function test_deposit_gives_shares() public {
        _deposit(alice, DEPOSIT_1000);

        // alice should have shares
        assertGt(vault.balanceOf(alice), 0);

        // vault should hold the USDC
        assertEq(usdc.balanceOf(address(proxy)), DEPOSIT_1000);
    }

    // cant deposit dust amounts
    function test_deposit_too_small_reverts() public {
        usdc.mint(alice, 100);
        vm.startPrank(alice);
        usdc.approve(address(proxy), 100);
        vm.expectRevert(bytes("Deposit too small"));
        vault.deposit(100, alice);
        vm.stopPrank();
    }

    // paused vault should block deposits
    function test_deposit_blocked_when_paused() public {
        vm.prank(owner);
        vault.pause();

        usdc.mint(alice, DEPOSIT_1000);
        vm.startPrank(alice);
        usdc.approve(address(proxy), DEPOSIT_1000);
        vm.expectRevert();
        vault.deposit(DEPOSIT_1000, alice);
        vm.stopPrank();
    }

    // two users depositing should not affect each other
    function test_two_users_deposit() public {
        _deposit(alice, DEPOSIT_1000);
        _deposit(bob, DEPOSIT_1000);

        assertGt(vault.balanceOf(alice), 0);
        assertGt(vault.balanceOf(bob), 0);

        // vault holds both deposits
        assertEq(usdc.balanceOf(address(proxy)), DEPOSIT_1000 * 2);
    }

    // first deposit — shares should equal assets 1:1
    function test_first_deposit_shares_equal_assets() public {
        _deposit(alice, DEPOSIT_1000);
        assertEq(vault.balanceOf(alice), DEPOSIT_1000);
    }

    // WITHDRAW 

    // full withdrawal returns all USDC
    function test_withdraw_returns_full_amount() public {
        _deposit(alice, DEPOSIT_1000);

        vm.startPrank(alice);
        vault.withdraw(DEPOSIT_1000, alice, alice);
        vm.stopPrank();

        // alice gets her USDC back
        assertEq(usdc.balanceOf(alice), DEPOSIT_1000);

        // vault is empty
        assertEq(vault.balanceOf(alice), 0);
    }

    // cant withdraw dust amounts
    function test_withdraw_too_small_reverts() public {
        _deposit(alice, DEPOSIT_1000);

        vm.startPrank(alice);
        vm.expectRevert(bytes("Withdraw too small"));
        vault.withdraw(100, alice, alice);
        vm.stopPrank();
    }

    // UPGRADE 

    // upgrading to v2 should not wipe user shares
    function test_upgrade_keeps_user_shares() public {
        _deposit(alice, DEPOSIT_1000);
        _deposit(bob, DEPOSIT_1000);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares   = vault.balanceOf(bob);

        vm.prank(owner);
        proxy.upgrade(address(vaultV2impl));

        // shares must survive the upgrade
        assertEq(vault.balanceOf(alice), aliceShares);
        assertEq(vault.balanceOf(bob), bobShares);
    }

    // storage set before upgrade must still be readable after
    function test_upgrade_keeps_storage() public {
        vm.prank(owner);
        vault.setPerformanceFee(500);

        vm.prank(owner);
        proxy.upgrade(address(vaultV2impl));

        VaultV2 vaultV2 = VaultV2(address(proxy));

        // fee set on v1 must still be 500 on v2
        assertEq(vaultV2.performanceFee(), 500);
    }

    // random user should never be able to upgrade
    function test_random_user_cannot_upgrade() public {
        vm.prank(randomGuy);
        vm.expectRevert(bytes("Not admin"));
        proxy.upgrade(address(vaultV2impl));
    }

    // V2 WITHDRAWAL FEE 

    // 1% withdrawal fee means user gets less than they withdrew
    function test_v2_withdrawal_fee_takes_cut() public {
        vm.prank(owner);
        proxy.upgrade(address(vaultV2impl));

        VaultV2 vaultV2 = VaultV2(address(proxy));

        vm.prank(owner);
        vaultV2.setWithdrawalFee(100); // 1%

        _deposit(alice, DEPOSIT_1000);

        vm.startPrank(alice);
        vaultV2.withdraw(DEPOSIT_500, alice, alice);
        vm.stopPrank();

        // alice gets less than 500 because 1% was taken as fee
        assertLt(usdc.balanceOf(alice), DEPOSIT_500);
    }

    // no fee set means user gets exact amount
    function test_v2_no_fee_returns_exact_amount() public {
        vm.prank(owner);
        proxy.upgrade(address(vaultV2impl));

        _deposit(alice, DEPOSIT_1000);

        vm.startPrank(alice);
        vault.withdraw(DEPOSIT_500, alice, alice);
        vm.stopPrank();

        assertEq(usdc.balanceOf(alice), DEPOSIT_500);
    }

    // ACCESS CONTROL 

    // only owner can pause the vault
    function test_only_owner_can_pause() public {
        vm.prank(randomGuy);
        vm.expectRevert();
        vault.pause();
    }

    // owner can update performance fee
    function test_owner_sets_performance_fee() public {
        vm.prank(owner);
        vault.setPerformanceFee(500);
        assertEq(vault.performanceFee(), 500);
    }

    // fee above max should revert
    function test_performance_fee_above_max_reverts() public {
        vm.prank(owner);
        vm.expectRevert(bytes("Fee too high"));
        vault.setPerformanceFee(3000);
    }

    // random user cannot touch fees
    function test_random_user_cannot_set_fee() public {
        vm.prank(randomGuy);
        vm.expectRevert();
        vault.setPerformanceFee(500);
    }
}