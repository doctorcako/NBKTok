// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title NBKToken
 * @dev Custom ERC20 Token with mint and burn functionality.
 * @custom:security-contact dariosansano@neuro-block.com
 */
contract NBKToken is ERC20, Ownable {
    
    // Custom Errors
    error InvalidOwner(address owner);
    error MintToZeroAddress();
    error BurnAmountExceedsBalance(uint256 balance, uint256 burnAmount);
    
    /**
     * @dev Constructor for the NBKToken contract.
     * @param tokenName The name of the token.
     * @param tokenSymbol The symbol of the token.
     * @param ownerWallet The address of the contract owner.
     * @notice Initializes the ERC20 token with provided name and symbol.
     * @dev Only the owner can mint new tokens.
     */
    constructor(string memory tokenName, string memory tokenSymbol, address ownerWallet) 
        ERC20(tokenName, tokenSymbol) 
        Ownable(ownerWallet)
    {
        if (ownerWallet == address(0)) {
            revert InvalidOwner(ownerWallet);
        }
    }

    /**
     * @dev Mints new tokens and assigns them to the specified address.
     * @param to The address to receive the newly minted tokens.
     * @param amount The amount of tokens to mint.
     * @notice Only the owner can mint tokens.
     * @dev Emits a `Transfer` event as per the ERC20 standard.
     * @custom:error MintToZeroAddress Cannot mint tokens to the zero address.
     */
    /// #if_succeeds { :msg "Mint correct amount to address" }  balanceOf(to) == amount;
    function mint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) {
            revert MintToZeroAddress();
        }
        _mint(to, amount);
    }

    /**
     * @dev Burns tokens from the caller's account.
     * @param amount The amount of tokens to burn.
     * @notice The caller can burn tokens from their own balance.
     * @dev Emits a `Transfer` event as per the ERC20 standard.
     * @custom:error BurnAmountExceedsBalance The burn amount exceeds the caller's balance.
    */
    function burn(uint256 amount) external {
        uint256 callerBalance = balanceOf(_msgSender());
        if (amount > callerBalance) {
            revert BurnAmountExceedsBalance(callerBalance, amount);
        }
        _burn(_msgSender(), amount);
    }
}
