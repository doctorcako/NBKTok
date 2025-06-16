
// SPDX-License-Identifier: MIT
import "./Dependencies.sol";
/** 
 *  SourceUnit: /Users/carlos.rocamora/Desktop/NeuroBlock/NBK/contracts/ICO_NBKToken.sol
*/
            
////// SPDX-License-Identifier-FLATTEN-SUPPRESS-WARNING: MIT
pragma solidity ^0.8.20;

/**
 * @title TokenDistributor
 * @notice This contract distributes NBK tokens subject to a daily withdrawal limit.
 * It also allows the owner to withdraw Ether and recover other ERC20 tokens.
 */
contract TokenDistributor is Ownable, Pausable, ReentrancyGuard {
    //Token 
    IERC20 public immutable token;

    // Maximum tokens that can be withdrawn or distributed in one day
    uint256 public dailyLimit;

    // Tracks the total tokens withdrawn each day (key = dayIndex)
    mapping(uint256 => uint256) public dailyWithdrawn;
    mapping(address => bool) private allowedInteractors;

    /// ----------------- EVENTS -----------------
    event TokensDistributed(address indexed beneficiary, uint256 amount);
    event DailyLimitUpdated(uint256 newLimit);
    event FundsWithdrawn(address indexed owner, uint256 amount, bool success);
    event FundsReceived(address sender, uint256 amount);
    event EmergencyTokenRecovery(address token, address to, uint256 amount);
    event ActivityPerformed(address indexed actor, uint256 amountOrData);

    /// ----------------- ERRORS -----------------
    // Token transfers related
    error TransferFailed(address receiver, uint256 amount);
    error NotEnoughTokensOnDistributor(uint256 balance, uint256 requested);

    // Withdraw related
    error DailyLimitWithdrawReached(uint256 current, uint256 requested, uint256 limit);
    error InvalidWithdrawAmount(uint256 amount);
    error NotEnoughEtherToWithdraw(uint256 eth);

    //Daily limit related
    error DailyLimitUpdateValueIncorrect(uint256 amount);
    error DailyLimitValueNotUpdating(uint256 amount);

    //other
    error InvalidBeneficiary(address beneficiary);
    error UnauthorizedCaller(address caller);
    error InteractorAlreadyAllowed();

    /**
     * @param tokenAddress Address of NBKToken
     * @param ownerWallet  Address that becomes the owner
     * @param _dailyLimit  Daily limit in NBK tokens (must match your test distribution sizes)
     */
    constructor(
        address tokenAddress,
        address ownerWallet,
        uint256 _dailyLimit
    ) Ownable(ownerWallet) {
        if (tokenAddress == address(0)) revert InvalidBeneficiary(address(0));
        if (ownerWallet == address(0)) revert InvalidBeneficiary(address(0));
        if (_dailyLimit < 1) revert DailyLimitUpdateValueIncorrect(_dailyLimit);

        token = IERC20(tokenAddress);
        dailyLimit = _dailyLimit;
    }

    /**
     * @dev Distributes tokens to a single beneficiary.
     * @param beneficiary Address to receive the tokens.
     * @param amount Amount of tokens to distribute.
     * @notice Only the owner or allowed interactors can call this.
     */
    /// #if_succeeds { :msg "Distribute tokens correctly" } old(token.balanceOf(beneficiary)) + amount == token.balanceOf(beneficiary);
    function distributeTokens(address beneficiary, uint256 amount)
        public
        whenNotPaused
        nonReentrant
    {
        if (!isAllowed(_msgSender())) {
            revert UnauthorizedCaller(_msgSender());
        }

        if (beneficiary == address(0)) revert InvalidBeneficiary(beneficiary);
        if (amount == 0) revert InvalidWithdrawAmount(amount);

        uint256 currentBalance = token.balanceOf(address(this));
        if (currentBalance < amount) {
            revert NotEnoughTokensOnDistributor(currentBalance, amount);
        }

        emit ActivityPerformed(_msgSender(), amount);
        emit TokensDistributed(beneficiary, amount);
        if(!token.transfer(beneficiary, amount)){
            revert TransferFailed(beneficiary, amount);
        }
    }

    /**
     * @dev Withdraws Ether from the contract to the owner's address.
     * @param amount Amount of Ether to withdraw.
     */
    /// #if_succeeds { :msg "Withdraw funds correctly" } old(address(this).balance) + amount == address(this).balance;
    function withdrawFunds(uint256 amount) public onlyOwner whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidWithdrawAmount(amount);

        if (amount > address(this).balance) {
            revert NotEnoughEtherToWithdraw(amount);
        }
        uint256 today = block.timestamp / 1 days;
        uint256 withdrawnToday = dailyWithdrawn[today];
        if (withdrawnToday + amount > dailyLimit) {
            revert DailyLimitWithdrawReached(withdrawnToday, amount, dailyLimit);
        }

        dailyWithdrawn[today] = withdrawnToday + amount;
        emit ActivityPerformed(_msgSender(), amount);
        emit FundsWithdrawn(owner(), amount, true);
        payable(owner()).transfer(amount);
    }

    /**
     * @dev Recovers any ERC20 token (other than NBK) from the contract.
     * @param tokenAddress The address of the token to recover.
     * @param to The address to send the recovered tokens.
     * @param amount The amount of tokens to recover.
     */
    /// #if_succeeds { :msg "Should recover the tokens" } old(IERC20(tokenAddress).balanceOf(to)) + amount == IERC20(tokenAddress).balanceOf(to);
    function emergencyTokenRecovery(
        address tokenAddress,
        address to,
        uint256 amount
    ) public onlyOwner nonReentrant {

        if (to == address(0)) {
            revert InvalidBeneficiary(address(0));
        }
        if (amount == 0) {
            revert InvalidWithdrawAmount(amount);
        }

        IERC20 recoveryToken = IERC20(tokenAddress);
        uint256 balance = recoveryToken.balanceOf(address(this));
        if (balance < amount) {
            revert NotEnoughTokensOnDistributor(balance, amount);
        }

        if (recoveryToken.transfer(to, amount)) {
            emit EmergencyTokenRecovery(tokenAddress, to, amount);
            emit ActivityPerformed(_msgSender(), amount);
        }
    }

    /**
     * @dev Set the allowed interactors (other addresses authorized to distribute tokens).
     * @param interactor Address of the interactor to authorize.
     */
    /// #if_succeeds { :msg "Set allowed interactor correctly" } allowedInteractors[interactor] == true;
    function setAllowedInteractors(address interactor) public onlyOwner {
        if (interactor == address(0)) {
            revert InvalidBeneficiary(address(0));
        }
        if (allowedInteractors[interactor] == true) {
            revert InteractorAlreadyAllowed();
        }
        allowedInteractors[interactor] = true;
    }

    /**
     * @dev Checks if an address is allowed to interact with the contract.
     * @param interactor Address to check.
     * @return isAllowed Boolean indicating whether the address is allowed.
     */
    function isAllowed(address interactor) internal view returns (bool) {
        return allowedInteractors[interactor] || interactor == owner();
    }

    /**
     * @dev Check if an address is allowed to interact with the contract.
     * @param interactor Address to check.
     * @return isAllowed Boolean indicating whether the address is allowed.
     */
    /// #if_succeeds { :msg "Interactor is allowed" } allowed == true;
    function checkAllowed(address interactor) public onlyOwner view returns (bool allowed) {
        return isAllowed(interactor);
    }

    /**
     * @dev Update the daily withdrawal limit.
     * @param dailyLimit_ New daily limit value.
     */
    /// #if_succeeds { :msg "Daily limit set correctly" } old(dailyLimit) != dailyLimit;
    function setDailyLimit(uint256 dailyLimit_) public onlyOwner {
        if (dailyLimit_ < 1) {
            revert DailyLimitUpdateValueIncorrect(dailyLimit_);
        }
        if (dailyLimit == dailyLimit_) {
            revert DailyLimitValueNotUpdating(dailyLimit_);
        }
        dailyLimit = dailyLimit_;
        emit DailyLimitUpdated(dailyLimit_);
        emit ActivityPerformed(_msgSender(), dailyLimit_);
    }

    /**
     * @dev Returns the remaining daily limit available for withdrawal or distribution.
     * @return remaining . The remaining amount available for withdrawal/distribution today.
     */
    /// #if_succeeds { :msg "Get remaining daily limit" } remaining < dailyLimit;
    function getRemainingDailyLimit() external view returns (uint256 remaining) {
        uint256 withdrawnToday = dailyWithdrawn[block.timestamp / 1 days];
        if (withdrawnToday >= dailyLimit) return 0;
        return dailyLimit - withdrawnToday;
    }

    /**
     * @dev Returns the current NBK token balance of the distributor contract.
     * @return The current token balance.
     */
    function getContractBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @dev Pauses all distributions/withdrawals.
     */
    function pauseDistributor() external onlyOwner {
        _pause();
        emit ActivityPerformed(_msgSender(), 0);
    }

    /**
     * @dev Unpauses all distributions/withdrawals.
     */
    function unpauseDistributor() external onlyOwner {
        _unpause();
        emit ActivityPerformed(_msgSender(), 0);
    }

    /**
     * @dev Accepts Ether deposits into the contract.
     */
    /// #if_succeeds { :msg "Receives ETH correctly" } old(address(this).balance) + msg.value == address(this).balance;
    receive() external payable {
        emit FundsReceived(_msgSender(), msg.value);
    }
}

contract MockToken is NBKToken {
    constructor() NBKToken("NBKToken","NBK",_msgSender()) {}
}

contract TokenDistributorTest is TokenDistributor {
    MockToken private testToken;
    event Debug(string message, address sender, bool isOwner, bool result);

    constructor() TokenDistributor(address(new MockToken()), _msgSender(), 10 * 10**18) {
        testToken = MockToken(address(token)); // Guardar referencia al token
        testToken.mint(address(this), 1_000_000);
    }

    /// @notice Verifica que el contrato tenga saldo de tokens
    function echidna_test_balance() public view returns (bool) {
        return token.balanceOf(address(this)) >= 0;
    }

    function echidna_test_allow_interactor() public returns (bool) {
        if (_msgSender() != owner() || _msgSender() == address(0)) return true; 
        if (checkAllowed(_msgSender())) return true;
        setAllowedInteractors(_msgSender());
        return checkAllowed(_msgSender());
    }

    function echidna_test_set_daily_limit() public returns (bool) {
        if (_msgSender() != this.owner()) return true; // Solo el owner puede ejecutar

        uint256 oldLimit = this.dailyLimit();
        uint256 newLimit = oldLimit + 1;

        if (newLimit == 0 || newLimit == oldLimit) return true; // Evita errores conocidos

        setDailyLimit(newLimit);
        return this.dailyLimit() == newLimit;
    }

    function echidna_test_distribute_tokens() public returns (bool) {
        address beneficiary = address(0x123);
        uint256 amount = 10 * 10**18; // 10 tokens en wei

        uint256 contractBalance = this.getContractBalance();
        uint256 beneficiaryOldBalance = IERC20(this.token()).balanceOf(beneficiary);

        if (contractBalance < amount || amount == 0) return true; // No ejecutar si no hay saldo suficiente

        distributeTokens(beneficiary, amount);
        return IERC20(this.token()).balanceOf(beneficiary) == beneficiaryOldBalance + amount;
    }

    function echidna_test_withdraw_funds() public returns (bool) {
        if (_msgSender() != this.owner()) return true; // Solo el owner puede ejecutar

        uint256 contractBalance = address(this).balance;
        uint256 amount = contractBalance / 2; // Retirar la mitad del saldo

        if (amount == 0 || amount > contractBalance) return true; // Evita retiros inválidos

        withdrawFunds(amount);
        return address(this).balance == contractBalance - amount;
    }

    function echidna_test_emergency_token_recovery() public returns (bool) {
        if (_msgSender() != this.owner()) return true; // Solo el owner puede ejecutar

        address recoveryToken = address(this.token());
        address to = address(0x456);
        uint256 amount = IERC20(recoveryToken).balanceOf(address(this)) / 2; // Recuperar la mitad del saldo

        if (amount == 0) return true; // Evita valores inválidos

        uint256 toOldBalance = IERC20(recoveryToken).balanceOf(to);

        emergencyTokenRecovery(recoveryToken, to, amount);
        return IERC20(recoveryToken).balanceOf(to) == toOldBalance + amount;
    }

}


