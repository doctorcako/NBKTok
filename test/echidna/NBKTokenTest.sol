// SPDX-License-Identifier: MIT
import "./Dependencies.sol";

/** 
 *  SourceUnit: /Users/carlos.rocamora/Desktop/NeuroBlock/NBK/contracts/NBKToken.sol
*/

////// SPDX-License-Identifier-FLATTEN-SUPPRESS-WARNING: MIT
pragma solidity ^0.8.20;


contract NBKTokenTest is NBKToken {
    constructor() NBKToken("NBKToken","NBK",address(this)) {}

    function echidna_test_token() public view returns (bool){
        if (owner() == address(this)) return true;
        return false;
    }

    function echidna_mint_to_correct_amount() public returns(bool){
        _mint(address(this), 10 * 10**18);
        if(balanceOf(address(this)) == 10 * 10**18) return true;
        return false;
    }

    function echidna_burn_correct_amount() public returns(bool){
        _mint(msg.sender, 10 * 10**18);
        if (balanceOf(msg.sender) == 0) {
            revert();
        }
        _burn(msg.sender, balanceOf(msg.sender));
        if(balanceOf(msg.sender) == 0) return true;
        return false;
    }
}



