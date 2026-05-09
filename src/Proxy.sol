//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Proxy {
  bytes32 private constant IMPLEMENTATION_SLOT = 
        bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
    
    bytes32 private constant ADMIN_SLOT = 
        bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);

  constructor(address _implmentation){
   _setImplementation(_implmentation);
   _setAdmin(msg.sender);
  }
   
  function _setImplementation(address _impl) private {
    bytes32 slot = IMPLEMENTATION_SLOT;
    assembly {
      sstore(slot, _impl)
    }
  }

  function _setAdmin(address _admin) private {
    bytes32 slot = ADMIN_SLOT;
    assembly {
      sstore(slot, _admin)
    }
  }

  function getImplementation() public view returns (address impl) {
    bytes32 slot = IMPLEMENTATION_SLOT;
    assembly {
      impl := sload(slot)
    }
  }

  function getAdmin() public view returns (address adm) {
    bytes32 slot = ADMIN_SLOT;
    assembly {
        adm := sload(slot)
    }
  }

  function upgrade(address newImplementation) external {
    require(msg.sender == getAdmin(), "Not admin");
    require(newImplementation != address(0), "Invalid address");
    _setImplementation(newImplementation);
  }



  fallback() external payable {
    address impl = getImplementation();
    (bool success, ) = impl.delegatecall(msg.data);

    require(success, "Delegatecall failed");

  }

  receive() external payable {}
}