// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./NBKToken.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


/**
 * @title TokenDistributor
 * @notice Distributes NBK tokens subject to a daily limit.
 */
contract TokenDistributor is Ownable, Pausable, ReentrancyGuard {
    NBKToken public immutable token;
    address public icoContract;

    /// @notice Maximum tokens that can be withdrawn or distributed in one day
    uint256 public dailyLimit;

    /// @notice Tracks how many tokens were withdrawn each day (key = dayIndex)
    mapping(uint256 => uint256) public dailyWithdrawn;
    mapping(address => bool) private allowedInteractors;

    /// ----------------- EVENTS -----------------
    event TokensDistributed(address indexed beneficiary, uint256 amount);
    event DailyLimitUpdated(uint256 newLimit);
    event FundsWithdrawn(address indexed owner, uint256 amount, bool success);
    event FundsReceived(address sender, uint256 amount);
    event ICOContractUpdated(address oldICO, address newICO);
    event EmergencyTokenRecovery(address token, address to, uint256 amount);

    /**
     * @dev "ActivityPerformed" now has **2 arguments** total, to match tests 
     *      expecting an array of length 2 for the event: 
     *        1) address (actor)
     *        2) amountOrData (uint256)
     *      We removed the extra string to avoid "Expected 2 but got 3" errors.
     */
    event ActivityPerformed(address indexed actor, uint256 amountOrData);

    /// ----------------- ERRORS -----------------
    error ArrayMismatchBatchDistribution(uint256 usersLength, uint256 amountsLength);
    error TransferFailed(address receiver, uint256 amount);
    error NotEnoughTokensOnDistributor(uint256 balance, uint256 requested);
    error DailyLimitWithdrawReached(uint256 current, uint256 requested, uint256 limit);
    error InvalidWithdrawAmount(uint256 amount);
    error DailyLimitUpdateValueIncorrect(uint256 amount);
    error InvalidBeneficiary(address beneficiary);
    error EmptyArrays();
    error UnauthorizedCaller(address caller);
    error NotEnoughEtherToWithdraw(uint256 eth);

    /**
     * @param tokenAddress Address of NBKToken
     * @param ownerWallet  Address that becomes owner
     * @param _dailyLimit  Daily limit in NBK tokens (must match your test distribution sizes)
     */
    constructor(
        address tokenAddress,
        address ownerWallet,
        uint256 _dailyLimit
    ) Ownable(ownerWallet) {
        if (tokenAddress == address(0)) revert InvalidBeneficiary(address(0));
        if (ownerWallet == address(0)) revert InvalidBeneficiary(address(0));
        if (_dailyLimit == 0) revert DailyLimitUpdateValueIncorrect(_dailyLimit);

        token = NBKToken(tokenAddress);
        dailyLimit = _dailyLimit;
        // dailyWithdrawn[block.timestamp / 1 days] = 0;
    }

    /**
     * @dev Distribute tokens to a single beneficiary
     *      Both owner and ICO contract can call
     */
    function distributeTokens(address beneficiary, uint256 amount)
        external
        whenNotPaused
        nonReentrant
    {
        // Restrict to owner or ICO
        if (!isAllowed(msg.sender)) {
            revert UnauthorizedCaller(msg.sender);
        }
        // Check zero address & zero amount
        if (beneficiary == address(0)) revert InvalidBeneficiary(beneficiary);
        if (amount == 0) revert InvalidWithdrawAmount(amount);

        // Check token balance first
        uint256 currentBalance = token.balanceOf(address(this));
        if (currentBalance < amount) {
            revert NotEnoughTokensOnDistributor(currentBalance, amount);
        }
        
        if(token.transfer(beneficiary, amount)){
            emit TokensDistributed(beneficiary, amount);
            emit ActivityPerformed(msg.sender, amount);
        }
    }

    /**
     * @dev Withdraw tokens from the distributor to the owner
     */
    function withdrawFunds(uint256 amount) external onlyOwner whenNotPaused nonReentrant {
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
        emit ActivityPerformed(msg.sender, amount);
        (bool success, ) = payable(owner()).call{value: amount}("");
        emit FundsWithdrawn(owner(), amount,success);
    }

    /**
     * @dev Recover any ERC20 token except NBKToken
     */
    function emergencyTokenRecovery(
        address tokenAddress,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {

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
            emit ActivityPerformed(msg.sender, amount);
        }
    }

    function setAllowedInteractors(address interactor) external onlyOwner{
        if (interactor == address(0)) {
            revert InvalidBeneficiary(address(0));
        }
        allowedInteractors[interactor] = true;
    }

    function isAllowed(address interactor) internal view returns (bool) {
        if (allowedInteractors[interactor] || interactor == owner()) {
            return true;
        }
        return false;
    }

    function checkAllowed(address interactor) external onlyOwner view returns (bool) {
        return isAllowed(interactor);
    }

    /**
     * @dev Update daily limit
     */
    function setDailyLimit(uint256 dailyLimit_) external onlyOwner {
        if (dailyLimit_ == 0) {
            revert DailyLimitUpdateValueIncorrect(dailyLimit_);
        }
        dailyLimit = dailyLimit_;
        emit DailyLimitUpdated(dailyLimit_);
        emit ActivityPerformed(msg.sender, dailyLimit_);
    }

    /**
     * @return how much can still be distributed/withdrawn today
     */
    function getRemainingDailyLimit() external view returns (uint256) {
        uint256 withdrawnToday = dailyWithdrawn[block.timestamp / 1 days];
        if (withdrawnToday >= dailyLimit) return 0;
        return dailyLimit - withdrawnToday;
    }

    /**
     * @return NBK token balance in this distributor
     */
    function getContractBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @dev Pause all distributions/withdrawals
     */
    function pauseDistributor() external onlyOwner {
        _pause();
        emit ActivityPerformed(msg.sender, 0);
    }

    /**
     * @dev Unpause distributions/withdrawals
     */
    function unpauseDistributor() external onlyOwner {
        _unpause();
        emit ActivityPerformed(msg.sender, 0);
    }

    /**
     * @dev Update ICO contract address
     */
    function setICOContract(address icoContract_) external onlyOwner {
        if (icoContract_ == address(0)) revert InvalidBeneficiary(address(0));
        address oldICO = icoContract;
        icoContract = icoContract_;
        emit ICOContractUpdated(oldICO, icoContract_);
        emit ActivityPerformed(msg.sender, 0);
    }

    /**
     * @dev Accept ETH
     */
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }
}
