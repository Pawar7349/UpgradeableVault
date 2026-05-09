// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IProxy {
    function upgrade(address newImplementation) external;
    function getImplementation() external view returns (address);
}

contract ProxyAdmin {
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function upgrade(address proxy, address newImplementation) external onlyOwner {
        IProxy(proxy).upgrade(newImplementation);
    }

    function getImplementation(address proxy) external view returns (address) {
        return IProxy(proxy).getImplementation();
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
}