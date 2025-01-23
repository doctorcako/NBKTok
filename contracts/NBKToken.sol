// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NBKToken is ERC20, Ownable {
    constructor(string memory tokenName, string memory tokenSymbol, address ownerWallet) 
        ERC20(tokenName, tokenSymbol) 
        Ownable(ownerWallet)
    {
        require(ownerWallet != address(0), "ERC20: owner is the zero address");
    }

    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "ERC20: mint to the zero address");
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        require(amount <= balanceOf(_msgSender()), "ERC20: burn amount exceeds balance");
        _burn(_msgSender(), amount);
    }
}
