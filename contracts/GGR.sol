pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GGR is ERC20, Ownable {
    using SafeERC20 for IERC20;
    
    mapping(address => bool) public allowedAddresses;

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

    constructor() ERC20("Gagarin", "GGR") {
        _mint(msg.sender, 50000e18);
        allowedAddresses[msg.sender] = true;
    }

    function mint(address _to, uint256 _amount) public onlyAllowed {
        _mint(_to, _amount);
    }
}
