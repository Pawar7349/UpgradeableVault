//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IStrategy.sol";



contract Vault is  ERC4626, Ownable, ReentrancyGuard, Pausable {
  using SafeERC20 for IERC20;

  uint256 public constant MAX_BPS = 10000;
  uint256 public constant MAX_PERFORMANCE_FEE = 2000; 
  uint256 public constant MIN_DEPOSIT = 1e6;
  uint256 public constant MAX_STRATEGIES = 10;


  event StrategyAdded(address strategy, uint256 allocation);
  event StrategyRemoved(address strategy);
  event Deposited(uint256 assets, address receiver);
  event Withdrawn(uint256 assets, address receiver, address owner);
  event Harvested(uint256 profit, uint256 feeAmount);
  event FeeUpdated(uint256 newFee);


  struct StrategyInfo {
    bool active;
    uint256 allocation;
    uint256 deposited;
  } 

  IStrategy[] public strategies;

  mapping(address => StrategyInfo) public strategyInfo;

  uint256 public performanceFee = 1000;
  address public feeRecipient;
  uint256 public lastHarvest;

  constructor(
    address _asset,
    string memory _name,
    string memory _symbol,
    address _feeRecipient
  )

  ERC4626(IERC20(_asset))
  ERC20(_name, _symbol)
  Ownable(msg.sender)

  {
   require(_feeRecipient != address(0), "Invalid fee recipient");
   feeRecipient = _feeRecipient;
   lastHarvest  = block.timestamp;
   _pause();
  }