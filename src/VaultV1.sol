//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;



import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IStrategy.sol";



contract VaultV1 is ERC4626Upgradeable, OwnableUpgradeable, ReentrancyGuard, PausableUpgradeable {
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

  uint256 public performanceFee;
  address public feeRecipient;
  uint256 public lastHarvest;


  function initialize(
    address _asset,
    string memory _name,
    string memory _symbol,
    address _feeRecipient
    ) external initializer {
    __ERC4626_init(IERC20(_asset));
    __ERC20_init(_name, _symbol);
    __Ownable_init(msg.sender);
    __Pausable_init();
    
    require(_feeRecipient != address(0), "Invalid fee recipient");
    feeRecipient = _feeRecipient;
    lastHarvest = block.timestamp;
    performanceFee = 1000;
    _pause();
  }

  function totalAssets() public view override returns(uint256){
    uint256 total = IERC20(asset()).balanceOf(address(this));

    for(uint256 i = 0; i < strategies.length; i++){
      if (strategyInfo[address(strategies[i])].active) {
            total += strategies[i].totalAssets();
      }
    }

    return total;
  }

  function deposit(uint256 assets, address receiver)
  public
  override
  whenNotPaused
  nonReentrant
  returns(uint256)
  {
    require(assets >= MIN_DEPOSIT, "Deposit too small");
    uint256 shares = super.deposit(assets, receiver);
    _deployToStrategies();
    return shares;
  }

  function withdraw(uint256 assets, address receiver, address owner)
  public
  virtual
  override
  whenNotPaused
  nonReentrant
  returns(uint256)
  {
    require(assets >= MIN_DEPOSIT , "Withdraw too small");
    uint256 idle = IERC20(asset()).balanceOf(address(this));

    if(assets > idle){
      _withdrawFromStrategies(assets - idle);
    }

    uint256 shares = super.withdraw(assets, receiver,owner);
    return shares;
  }

    function _deployToStrategies() internal {
    uint256 idle = IERC20(asset()).balanceOf(address(this));
    if(idle == 0) return;

    for(uint256 i = 0; i < strategies.length; i++){

      StrategyInfo storage info = strategyInfo[address(strategies[i])];
      if(!info.active) continue;
      
      uint256 amount = idle * info.allocation / MAX_BPS;
      if(amount == 0) continue;
        
      IERC20(asset()).safeIncreaseAllowance(address((strategies[i])), amount);
      strategies[i].deposit(amount);
      info.deposited += amount;
    }
  }

  function _withdrawFromStrategies(uint256 amounNeeded) internal {
    uint256 remaining = amounNeeded;
    for(uint256 i = 0; i < strategies.length; i++){
      StrategyInfo storage info = strategyInfo[address(strategies[i])];
      if(!info.active) continue;
      if(info.deposited == 0) continue;
      
      uint256 available = strategies[i].totalAssets();

      uint256 toWithdraw = remaining > available ? available : remaining;
      
      uint256 actualAmount = strategies[i].withdraw(toWithdraw);

      if(actualAmount >= info.deposited){
        info.deposited = 0;
      }else {
        info.deposited -= actualAmount;
      }

      remaining -= actualAmount;

      if(remaining == 0) break;
    }
    require(remaining == 0, "Insufficient liquidity");
  }

  function addStrategy(address strategy, uint256 allocation) external onlyOwner {
    require(strategy != address(0), "Invalid strategy");
    require(!strategyInfo[strategy].active, "Strategy already exists");
    require(strategies.length < MAX_STRATEGIES, "Stratergy limit exceed");
    require(IStrategy(strategy).asset() == asset(), "Asset mismatch");
    require(allocation > 0 && allocation <= MAX_BPS, "Invalid allocation");
    
    strategies.push(IStrategy(strategy));
    
    strategyInfo[strategy] = StrategyInfo({
      active:true,
      allocation: allocation,
      deposited:0
    });

    emit StrategyAdded(strategy, allocation);
  }

  function removestrategy(address strategy) external onlyOwner {
    require(strategyInfo[strategy].active, "Strategy not active");
    
    StrategyInfo storage info = strategyInfo[strategy];
    if(info.deposited > 0){
      IStrategy(strategy).withdraw(info.deposited);
      info.deposited = 0;
    }
    
    for(uint256 i = 0; i < strategies.length; i++) {
      if(address(strategies[i]) == strategy){
        strategies[i] = strategies[strategies.length -1];
        strategies.pop();
        break;
      }
    }
    info.active = false;
    

    emit StrategyRemoved(strategy);

  }

  function harvest() external {
    require(block.timestamp >= lastHarvest + 1 days, "Too soon");
    for(uint256 i = 0; i < strategies.length; i++) {
      StrategyInfo storage info = strategyInfo[address(strategies[i])];
      if(!info.active) continue;

      try strategies[i].harvest() {} catch {}
      
      uint256 currentBalance = strategies[i].totalAssets();
      if(currentBalance > info.deposited){
        uint256 profit = currentBalance - info.deposited;
        info.deposited = currentBalance;

        uint256 fee = (profit * performanceFee)/ MAX_BPS;

        if(fee > 0){
          uint256 feeShares = convertToShares(fee);
          _mint(feeRecipient, feeShares);
          emit Harvested(profit, fee);   
        }

      }
    }
    lastHarvest = block.timestamp;
  } 


  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  function setPerformanceFee(uint256 newFee) external onlyOwner {
    require(newFee <= MAX_PERFORMANCE_FEE, "Fee too high");
    performanceFee = newFee;
    emit FeeUpdated(newFee);
  }

  function setFeeRecipient(address newRecipient) external onlyOwner {
    require(newRecipient != address(0), "Invalid address");
    feeRecipient = newRecipient;
  }

}