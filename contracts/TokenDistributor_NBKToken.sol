// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
/**
 * @title TokenDistributor
 * @notice This contract distributes NBK tokens subject to a daily withdrawal limit.
 * It also allows the owner to withdraw Ether and recover other ERC20 tokens.
 * @custom:security-contact dariosansano@neuro-block.com
 */
contract TokenDistributor is Ownable, Pausable, ReentrancyGuard {
    /// @notice Token used for distribution and withdrawals.
    /// @dev This is an ERC-20 token contract.
    IERC20 public immutable TOKEN;

    /// @notice Maximum number of tokens that can be withdrawn or distributed in a single day.
    uint256 public dailyLimit;

    /// @notice Tracks the total tokens withdrawn each day.
    /// @dev Key = `dayIndex` (number of days since epoch), Value = amount withdrawn on that day.
    mapping(uint256 day => uint256 amount) public dailyWithdrawn;

    /// @notice Stores addresses allowed to interact with the contract.
    mapping(address interactor => bool isAllowed) private allowedInteractors;

    /// ----------------- EVENTS -----------------

    /// @notice Emitted when tokens are distributed to a beneficiary.
    /// @param beneficiary Address receiving the tokens.
    /// @param amount Number of tokens distributed.
    event TokensDistributed(address indexed beneficiary, uint256 amount);

    /// @notice Emitted when the daily withdrawal limit is updated.
    /// @param newLimit The new daily limit value.
    event DailyLimitUpdated(uint256 newLimit);

    /// @notice Emitted when funds are withdrawn from the contract.
    /// @param owner The address that performed the withdrawal.
    /// @param amount The amount of tokens withdrawn.
    /// @param success Whether the withdrawal was successful.
    event FundsWithdrawn(address indexed owner, uint256 amount, bool success);

    /// @notice Emitted when funds are received by the contract.
    /// @param sender The address sending funds.
    /// @param amount The amount of tokens received.
    event FundsReceived(address sender, uint256 amount);

    /// @notice Emitted when tokens are recovered in case of emergency.
    /// @param token Address of the recovered token.
    /// @param to Address receiving the recovered tokens.
    /// @param amount Amount of tokens recovered.
    event EmergencyTokenRecovery(address token, address to, uint256 amount);

    /// @notice Emitted when an allowed actor performs an activity.
    /// @param actor The address performing the action.
    /// @param amountOrData Amount of tokens involved or additional data.
    event ActivityPerformed(address indexed actor, uint256 amountOrData);

    /// ----------------- ERRORS -----------------

    // Token transfers related

    /// @notice Thrown when a token transfer fails.
    /// @param receiver The intended recipient of the transfer.
    /// @param amount The amount of tokens that failed to be transferred.
    error TransferFailed(address receiver, uint256 amount);

    /// @notice Thrown when there are not enough tokens in the distributor for a requested transfer.
    /// @param balance The available token balance in the contract.
    /// @param requested The amount of tokens requested for transfer.
    error NotEnoughTokensOnDistributor(uint256 balance, uint256 requested);

    // Withdraw related

    /// @notice Thrown when the daily withdrawal limit is reached.
    /// @param current The amount already withdrawn today.
    /// @param requested The amount being requested.
    /// @param limit The daily withdrawal limit.
    error DailyLimitWithdrawReached(uint256 current, uint256 requested, uint256 limit);

    /// @notice Thrown when an invalid withdrawal amount is requested.
    /// @param amount The invalid withdrawal amount.
    error InvalidWithdrawAmount(uint256 amount);

    /// @notice Thrown when there is not enough Ether available for withdrawal.
    /// @param eth The requested Ether amount.
    error NotEnoughEtherToWithdraw(uint256 eth);

    // Daily limit related

    /// @notice Thrown when an incorrect value is provided for updating the daily limit.
    /// @param amount The incorrect amount.
    error DailyLimitUpdateValueIncorrect(uint256 amount);

    /// @notice Thrown when attempting to update the daily limit but the value remains unchanged.
    /// @param amount The unchanged limit value.
    error DailyLimitValueNotUpdating(uint256 amount);

    // Other

    /// @notice Thrown when a beneficiary address is invalid.
    /// @param beneficiary The invalid address.
    error InvalidBeneficiary(address beneficiary);

    /// @notice Thrown when an unauthorized caller attempts to interact with the contract.
    /// @param caller The unauthorized address.
    error UnauthorizedCaller(address caller);

    /// @notice Thrown when attempting to add an already allowed interactor.
    error InteractorAlreadyAllowed();

    /**
     * @param token Address of NBKToken
     * @param ownerWallet_  Address that becomes the owner
     * @param dailyLimit_  Daily limit in NBK tokens (must match your test distribution sizes)
     */
    constructor(
        address token,
        address ownerWallet_,
        uint256 dailyLimit_
    ) Ownable(ownerWallet_) {
        if (token == address(0)) revert InvalidBeneficiary(address(0));
        if (ownerWallet_ == address(0)) revert InvalidBeneficiary(address(0));
        if (dailyLimit_ < 1) revert DailyLimitUpdateValueIncorrect(dailyLimit_);

        TOKEN = IERC20(token);
        dailyLimit = dailyLimit_;
    }

    /**
     * @dev Distributes tokens to a single beneficiary.
     * @param beneficiary Address to receive the tokens.
     * @param amount Amount of tokens to distribute.
     * @notice Only the owner or allowed interactors can call this.
     */
    function distributeTokens(address beneficiary, uint256 amount)
        external
        whenNotPaused
        nonReentrant
    {
        if (!isAllowed(_msgSender())) {
            revert UnauthorizedCaller(_msgSender());
        }

        if (beneficiary == address(0)) revert InvalidBeneficiary(beneficiary);
        if (amount < 1) revert InvalidWithdrawAmount(amount);

        uint256 currentBalance = TOKEN.balanceOf(address(this));
        if (currentBalance < amount) {
            revert NotEnoughTokensOnDistributor(currentBalance, amount);
        }

        emit ActivityPerformed(_msgSender(), amount);
        emit TokensDistributed(beneficiary, amount);
        if(!TOKEN.transfer(beneficiary, amount)){
            revert TransferFailed(beneficiary, amount);
        }
    }

    /**
     * @dev Withdraws Ether from the contract to the owner's address.
     * @param amount Amount of Ether to withdraw.
     */
    function withdrawFunds(uint256 amount) external onlyOwner whenNotPaused nonReentrant {
        if (amount < 1) revert InvalidWithdrawAmount(amount);

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
        Address.sendValue(payable(owner()),amount);
    }

    /**
     * @dev Recovers any ERC20 token (other than NBK) from the contract.
     * @param tokenAddress The address of the token to recover.
     * @param to The address to send the recovered tokens.
     * @param amount The amount of tokens to recover.
     */
    function emergencyTokenRecovery(
        address tokenAddress,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {

        if (to == address(0)) {
            revert InvalidBeneficiary(address(0));
        }
        if (amount < 1) {
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
    function setAllowedInteractors(address interactor) external onlyOwner {
        if (interactor == address(0)) {
            revert InvalidBeneficiary(address(0));
        }
        if (allowedInteractors[interactor]) {
            revert InteractorAlreadyAllowed();
        }
        allowedInteractors[interactor] = true;
    }

    /**
     * @dev Checks if an address is allowed to interact with the contract.
     * @param interactor Address to check.
     * @return allowed Boolean indicating whether the address is allowed.
     */
    function isAllowed(address interactor) internal view returns (bool allowed) {
        return allowedInteractors[interactor] || interactor == owner();
    }

    /**
     * @dev Check if an address is allowed to interact with the contract.
     * @param interactor Address to check.
     * @return isAllowed Boolean indicating whether the address is allowed.
     */
    /// #if_succeeds { :msg "Interactor is allowed" } allowed == true;
    function checkAllowed(address interactor) external onlyOwner view returns (bool allowed) {
        return isAllowed(interactor);
    }

    /**
     * @dev Update the daily withdrawal limit.
     * @param dailyLimit_ New daily limit value.
     */
    /// #if_succeeds { :msg "Daily limit set correctly" } old(dailyLimit) != dailyLimit;
    function setDailyLimit(uint256 dailyLimit_) external onlyOwner {
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
        return TOKEN.balanceOf(address(this));
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
    receive() external payable {
        emit FundsReceived(_msgSender(), msg.value);
    }
}
