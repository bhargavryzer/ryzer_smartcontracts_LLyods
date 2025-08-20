// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract UsdcMock is ERC20, Ownable, ERC20Permit {
    uint8 private _decimals;

    constructor() ERC20("USDC", "USDC") Ownable(msg.sender) ERC20Permit("USDC") {
        _decimals = 6;
        _mint(msg.sender, 1000_000_000);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
