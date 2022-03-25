// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IALP.sol";

contract ALP is ERC20, IALP {
    using SafeERC20 for IERC20;

    IERC20 public ggr;

    mapping(address => bool) public allowedAddresses;

    // Define the ggr token contract and set allowed address
    constructor(IERC20 _ggr) ERC20("AllocationPower", "ALP") {
        ggr = _ggr;
        allowedAddresses[msg.sender] = true;
    }

    modifier onlyAllowed() {
        require(allowedAddresses[msg.sender] == true, "Allowed: caller is not from allowed adresses list");
        _;
    }

    function setAllowed (address[] memory _allowedAddr) public onlyAllowed {
        for (uint256 i = 0; i < _allowedAddr.length; i++) {
            allowedAddresses[_allowedAddr[i]] = true;
        }
    }

    function removeAllowed(address[] memory _removeAddr) public onlyAllowed {
        for (uint256 i = 0; i < _removeAddr.length; i++) {
            allowedAddresses[_removeAddr[i]] = false;
        }
    }

    function mint(address _to, uint256 _amount) external onlyAllowed override {
        _mint(_to, _amount);
    }

    function burn(address from, uint256 _share) external onlyAllowed override {
        _burn(from, _share);
    }
}
