// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Stable is ERC20 {
    constructor() ERC20("Stable", "STB") {
        _mint(msg.sender, 50000000000e18);
    }
}
