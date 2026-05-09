// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./VaultV1.sol";

contract VaultV2 is VaultV1 {

    uint256 public withdrawalFee;

    function setWithdrawalFee(uint256 newFee) external onlyOwner {
        require(newFee <= 500, "Max 5%");
        withdrawalFee = newFee;
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        whenNotPaused
        returns (uint256)
    {
        require(assets >= MIN_DEPOSIT, "Withdraw too small");

        uint256 idle = IERC20(asset()).balanceOf(address(this));
        if (assets > idle) {
            _withdrawFromStrategies(assets - idle);
        }

        if (withdrawalFee > 0) {
            uint256 fee = (assets * withdrawalFee) / MAX_BPS;
            assets = assets - fee;
        }

        uint256 shares = super.withdraw(assets, receiver, owner);
        return shares;
    }
}