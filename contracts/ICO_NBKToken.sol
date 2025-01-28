// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./libraries/VestingSchedule_NBKToken.sol";
import "./TokenDistributor_NBKToken.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title IcoNBKToken
 * @dev Contract that handles token sales in an ICO with options for vesting and whitelisting.
 */
contract IcoNBKToken is Ownable, Pausable, ReentrancyGuard {

    address payable immutable private tokenDistributorAddress;
    TokenDistributor private immutable tokenDistributor;

    uint256 public startTime;
    uint256 public endTime;
    uint256 public maxTokens;
    uint256 public maxTokensPerUser;
    uint256 public mintedTokens;
    uint256 public cliffDurationInMonths;
    uint256 public vestingDurationInMonths;
    uint256 public timelockDuration;
    uint256 public rate;
    uint256 public minPurchaseAmount;
    uint256 public currentPhaseInterval;

    bool public whitelistEnabled;
    bool public vestingEnabled;

    mapping(address => uint256) private icoPublicUserBalances;
    mapping(address => bool) public whitelist;
    mapping(address => VestingSchedule.VestingData) public vestings;
    mapping(address => uint256) public lastPurchaseTime;
    mapping(uint256 => mapping(address => VestingSchedule.VestingInterval[])) public phaseUserVestings;

    VestingSchedule.VestingInterval[] private unlockVestingIntervals;

    /// ----------------- EVENTS -----------------
    event VestingAssigned(address indexed investor, uint256 amount, uint256 currentPhaseInterval);
    event VestingStatusUpdated(bool oldStatus, bool newStatus);
    event MaxTokensUpdated(uint256 oldMaxTokens, uint256 newMaxTokens);
    event MaxTokensPerUserUpdated(uint256 oldMaxTokensPerUser, uint256 newMaxTokensPerUser);
    event MintedTokensUpdated(uint256 oldMintedTokens, uint256 newMintedTokens);
    event WhitelistStatusUpdated(bool oldStatus, bool newStatus);
    event VestingIntervalsUpdated(uint256 indexed totalIntervals);
    event WhitelistUpdated(address indexed account, bool enabled);
    event BatchWhitelistUpdated(uint256 totalAccounts, bool enabled);
    event RateUpdated(uint256 oldRate, uint256 newRate);
    event TimelockDurationUpdated(uint256 oldDuration, uint256 newDuration);
    event ICOPeriodUpdated(uint256 startTime, uint256 endTime);
    event CliffUpdated(uint256 cliff);
    event VestingDurationUpdated(uint256 vestingDuration);
    event MinAmountUpdated(uint256 minAmount);

    /// ----------------- ERRORS -----------------
    error AddressNotInWhitelist(address investor);
    error NoTokensAvailable(uint256 amount);
    error NoReleasableTokens(address investor);
    error ICONotInActivePeriod(uint256 currentTime);
    error NoMsgValueSent(uint256 value);
    error InsufficientETHForTokenPurchase(uint256 ethPurchase);
    error TotalAmountExceeded(address investor, uint256);
    error TimeLockNotPassed(address investor, uint256 time);
    error InvalidVestingIntervals();
    error InvalidIntervalSequence(uint256 index);
    error TotalPercentageNotEqualTo100(uint256 totalPercentage);
    error InvalidAddress(address account);
    error InvalidArrayInput();
    error InvalidRateValue(uint256 rate);
    error InvalidTimelockDuration(uint256 duration);
    error InvalidMaxTokens(uint256 maxTokens);
    error InvalidMaxTokensPerUser(uint256 maxTokensPerUser);
    error InvalidICOPeriod(uint256 startTime, uint256 endTime);
    error InvalidCliff(uint256 cliff);
    error InvalidVestingDuration(uint256 vestingDuration);
    error VestingNotEnabledForManualAssignment(address investor);
    error UnlockVestingIntervalsNotDefined();
    error InvalidMinAmount(uint256 minAmount);

    /**
     * @dev Constructor to initialize the ICO contract.
     * @param tokenDistributorAddress_ Address of the TokenDistributor contract.
     * @param ownerWallet Address of the contract owner.
     */
    constructor(
        address payable tokenDistributorAddress_, 
        address ownerWallet) 
        Ownable(ownerWallet)
        {
        if(tokenDistributorAddress_ == address(0)) revert InvalidAddress(tokenDistributorAddress_);
        if(ownerWallet == address(0)) revert InvalidAddress(ownerWallet);
        
        tokenDistributorAddress = tokenDistributorAddress_;
        tokenDistributor = TokenDistributor(tokenDistributorAddress_);
        
        startTime = block.timestamp;
        endTime = block.timestamp + 30 days;
        rate = 1000; // 1 ETH = 1000 tokens
        maxTokens = 1_000_000 * 10**18; // 1 million tokens
        maxTokensPerUser = 10_000 * 10**18; // 10,000 tokens per user
        timelockDuration = 1 days; // 1 day between purchases  
        currentPhaseInterval = 0;
        vestingDurationInMonths = 12;
        cliffDurationInMonths = 3;
        vestingEnabled = false;
        whitelistEnabled = false;
        minPurchaseAmount = 333333 * 10**12; // 1€ with ETH at 3000€
    }

    /**
     * @dev Allows an investor to purchase tokens with Ether. The number of tokens purchased is based on the current rate.
     * Sent msg.value Amount of Ether by the investor.
     * @return success A boolean indicating if the purchase was successful.
     *
     * @notice Reverts with custom errors if any conditions fail:
     * - `UnlockVestingIntervalsNotDefined`: if vesting is enabled but intervals are not set.
     * - `TotalAmountExceeded`: if the investor exceeds their token limit.
     * - `NoTokensAvailable`: if there are insufficient tokens available.
     * - `AddressNotInWhitelist`: if the investor is not whitelisted (if whitelist is enabled).
     * - `ICONotInActivePeriod`: if the ICO is not in the active time window.
     * 
     * @dev This function is protected with `whenNotPaused` and `nonReentrant` modifiers.
     */
    function buyTokens() external payable whenNotPaused nonReentrant returns (bool) {
        uint256 tokensToBuyInWei = (msg.value * rate);
        address investor = _msgSender();
        checkValidPurchase(investor, tokensToBuyInWei);

        if (vestingEnabled) {
            if (unlockVestingIntervals.length == 0){
                revert UnlockVestingIntervalsNotDefined();
            }else{
                if(vestings[investor].totalAmount != 0 && phaseUserVestings[currentPhaseInterval][investor].length != 0){
                    uint256 newTotal = vestings[investor].totalAmount + tokensToBuyInWei;
                    if (newTotal  <= maxTokensPerUser) {
                        vestings[investor].totalAmount = newTotal;
                    } else {
                        revert TotalAmountExceeded(investor, tokensToBuyInWei);
                    }
                } else {
                    VestingSchedule.VestingData memory vesting = VestingSchedule.createVesting(tokensToBuyInWei, cliffDurationInMonths, vestingDurationInMonths);
                    vestings[investor] = vesting;
                    phaseUserVestings[currentPhaseInterval][investor] = unlockVestingIntervals;
                }
                emit VestingAssigned(investor, tokensToBuyInWei, currentPhaseInterval);
            }
        } else {
            if (icoPublicUserBalances[investor] != 0 && (icoPublicUserBalances[investor]) + (tokensToBuyInWei)  > maxTokensPerUser){
                revert TotalAmountExceeded(investor, tokensToBuyInWei);
            }
            icoPublicUserBalances[investor] += tokensToBuyInWei;
        }

        uint256 oldMintedTokens = mintedTokens;
        mintedTokens += tokensToBuyInWei;
        lastPurchaseTime[investor] = block.timestamp;
        emit MintedTokensUpdated(oldMintedTokens, mintedTokens);
        payable(tokenDistributorAddress).transfer(msg.value);
        if(!vestingEnabled) tokenDistributor.distributeTokens(investor, tokensToBuyInWei, rate);
        return true;
    }

    /**
     * @dev Validates if a purchase request from an investor meets all necessary conditions.
     * @param investor Address of the investor trying to purchase tokens.
     * @param tokensToBuyInWei Amount of tokens the investor wishes to buy, expressed in Wei.
     * 
     * @notice This function checks several conditions:
     *  - The investor is not within the time lock period from their last purchase.
     *  - The current time is within the ICO's active start and end time.
     *  - The investor is on the whitelist if whitelisting is enabled.
     *  - The investor has sent a non-zero Ether value.
     *  - The purchase amount meets the minimum purchase requirement.
     *  - There are enough tokens available for the purchase.
     *  - The purchase does not exceed the maximum allowable amount per user.
     * 
     * @dev Reverts with custom errors if any of the conditions are violated:
     */
    function checkValidPurchase(address investor, uint256 tokensToBuyInWei) internal {
        if(lastPurchaseTime[investor] != 0 && block.timestamp < lastPurchaseTime[investor] + timelockDuration){
            revert TimeLockNotPassed(investor, lastPurchaseTime[investor] + timelockDuration);
        }
        if(block.timestamp < startTime || block.timestamp > endTime){
            revert ICONotInActivePeriod(block.timestamp);
        }
        if(whitelistEnabled && !whitelist[investor]){
            revert AddressNotInWhitelist(investor);
        }
        if(msg.value == 0){
            revert NoMsgValueSent(msg.value);
        }
        if(tokensToBuyInWei < minPurchaseAmount){
            revert InsufficientETHForTokenPurchase(tokensToBuyInWei);
        }
        if(tokensToBuyInWei > getAvailableTokens()){
            revert NoTokensAvailable(tokensToBuyInWei);
        }
        if(tokensToBuyInWei > maxTokensPerUser){
            revert TotalAmountExceeded(investor, tokensToBuyInWei);
        }
    }

    /**
     * @dev Allows the investor to claim the released tokens.
     * @notice Tokens are released according to the vesting schedule.
     * @return Success if claimed some tokens
     */
    function claimTokens() external nonReentrant returns (bool){
        VestingSchedule.VestingData storage vesting = vestings[_msgSender()];
        uint256 releasable = 0;
        for (uint256 i=0; i<=currentPhaseInterval; i++){
            releasable += VestingSchedule.calculateReleasable(vesting, phaseUserVestings[i][_msgSender()]);
        }
        if(releasable > 0){
            vesting.claimedAmount += releasable; // Update claimed tokens
            tokenDistributor.distributeTokens(_msgSender(), releasable, rate);
        }else{
            revert NoReleasableTokens(_msgSender());
        }
        return true;
    }

    /**
     * @dev Manually assigns tokens with a vesting schedule to an investor.
     * @param investor Address of the investor.
     * @param amount Amount of tokens to be assigned.
     * @param cliff Duration of the cliff in months.
     * @param duration Duration of the vesting in months.
     */
    function assignVesting(address investor, uint256 amount, uint256 cliff, uint256 duration) external onlyOwner nonReentrant{
        if (vestingEnabled && unlockVestingIntervals.length != 0) {
                if(vestings[investor].totalAmount != 0 && phaseUserVestings[currentPhaseInterval][investor].length != 0){
                    uint256 newTotal = vestings[investor].totalAmount + amount;
                    vestings[investor].totalAmount = newTotal;
                }else {
                    VestingSchedule.VestingData memory vesting = VestingSchedule.createVesting(amount, cliff, duration);
                    vestings[investor] = vesting;
                    phaseUserVestings[currentPhaseInterval][investor] = unlockVestingIntervals;
                }
                emit VestingAssigned(investor, amount, currentPhaseInterval);  
        }else{
            revert VestingNotEnabledForManualAssignment(investor);
        }
    }

    /**
     * @dev Updates the vesting intervals for the ICO.
     * @param intervals The array of vesting intervals to be set.
     * @notice Only the owner can update vesting intervals.
     */
    function setVestingIntervals(VestingSchedule.VestingInterval[] memory intervals) external onlyOwner {
        if (intervals.length == 0) {
            revert InvalidVestingIntervals();
        }

        if (intervals[intervals.length -1].endMonth != vestingDurationInMonths){
            revert InvalidVestingIntervals();
        }

        uint256 totalPercentage = 0;
        uint256 lastEndMonth = 0;

        for (uint256 i = 0; i < intervals.length; i++) {
            if (intervals[i].endMonth <= lastEndMonth) {
                revert InvalidIntervalSequence(i);
            }
            if (intervals[i].unlockPerMonth == 0) {
                revert InvalidVestingIntervals();
            }
            
            uint256 monthsInInterval = intervals[i].endMonth - (i == 0 ? 0 : intervals[i-1].endMonth);
            uint256 intervalPercentage = intervals[i].unlockPerMonth * monthsInInterval;
            
            totalPercentage += intervalPercentage;
            lastEndMonth = intervals[i].endMonth;
        }

        if (totalPercentage != 100) {
            revert TotalPercentageNotEqualTo100(totalPercentage);
        }

        delete unlockVestingIntervals;
        for (uint256 i = 0; i < intervals.length; i++) {
            unlockVestingIntervals.push(intervals[i]);
        }

        currentPhaseInterval++;
        emit VestingIntervalsUpdated(intervals.length);
    }

    /**
     * @dev Adds or removes an address from the whitelist.
     * @param account Address to be whitelisted.
     * @param enabled Boolean value to enable or disable the address.
     */
    function setWhitelist(address account, bool enabled) external onlyOwner {
        if (account == address(0)) {
            revert InvalidAddress(account);
        }
        whitelist[account] = enabled;
        emit WhitelistUpdated(account, enabled);
    }

    // Batch whitelist setter
    /**
     * @dev Adds or removes multiple addresses from the whitelist.
     * @param accounts Array of addresses to be whitelisted.
     * @param enabled Boolean value to enable or disable the addresses.
     */
    function setWhitelistBatch(address[] memory accounts, bool enabled) external onlyOwner {
        if (accounts.length == 0) {
            revert InvalidArrayInput();
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == address(0)) {
                revert InvalidAddress(accounts[i]);
            }
            whitelist[accounts[i]] = enabled;
        }

        emit BatchWhitelistUpdated(accounts.length, enabled);
    }

    /**
     * @dev Sets the rate at which tokens are purchased.
     * @param newRate The new rate of token purchase per ETH.
     * @notice Only the owner can change the rate.
     */
    function setRate(uint256 newRate) external onlyOwner {
        if (newRate == 0) {
            revert InvalidRateValue(newRate);
        }
        emit RateUpdated(rate, newRate);
        rate = newRate;
    }

    /**
     * @dev Sets the duration of the timelock between purchases.
     * @param timelockDuration_ The new timelock duration in seconds.
     */
    function setTimelockDuration(uint256 timelockDuration_) external onlyOwner {
        if (timelockDuration_ == 0) {
            revert InvalidTimelockDuration(timelockDuration_);
        }
        emit TimelockDurationUpdated(timelockDuration, timelockDuration_);
        timelockDuration = timelockDuration_;
    }

    /**
     * @dev Sets the maximum number of tokens that can be minted.
     * @param maxTokens_ The maximum token supply.
     */
    function setMaxTokens(uint256 maxTokens_) external onlyOwner {
        if (maxTokens_ == 0) {
            revert InvalidMaxTokens(maxTokens_);
        }
        emit MaxTokensUpdated(maxTokens, maxTokens_);
        maxTokens = maxTokens_;
    }

    /**
     * @dev Sets the maximum tokens an individual can purchase.
     * @param maxTokensPerUser_ The maximum token limit per user.
     */
    function setMaxTokensPerUser(uint256 maxTokensPerUser_) external onlyOwner {
        if (maxTokensPerUser_ == 0) {
            revert InvalidMaxTokensPerUser(maxTokensPerUser_);
        }
        emit MaxTokensPerUserUpdated(maxTokensPerUser, maxTokensPerUser_);
        maxTokensPerUser = maxTokensPerUser_;
    }

    /**
     * @dev Sets the cliff duration for vesting.
     * @param cliffDurationInMonths_ Duration of the cliff in months.
     */
    function setCliffDuration(uint256 cliffDurationInMonths_) external onlyOwner {
        if (cliffDurationInMonths_ == 0) {
            revert InvalidCliff(cliffDurationInMonths_);
        }
        emit CliffUpdated(cliffDurationInMonths_);
        cliffDurationInMonths = cliffDurationInMonths_;
    }

    /**
     * @dev Sets the vesting duration in months.
     * @param vestingDuration_ Duration of the vesting in months.
     */
    function setVestingDuration(uint256 vestingDuration_) external onlyOwner {
        if (vestingDuration_ == 0) {
            revert InvalidVestingDuration(vestingDuration_);
        }
        emit VestingDurationUpdated(vestingDuration_);
        vestingDurationInMonths = vestingDuration_;
    }

    /**
     * @dev Enables or disables the whitelist.
     * @param whitelistEnabled_ Boolean value to enable or disable the whitelist.
     */
    function setWhitelistEnabled(bool whitelistEnabled_) external onlyOwner {
        emit WhitelistStatusUpdated(whitelistEnabled, whitelistEnabled_);
        whitelistEnabled = whitelistEnabled_;
    }

    /**
     * @dev Enables or disables the vesting feature.
     * @param vestingEnabled_ Boolean value to enable or disable vesting.
     */
    function setVestingEnabled(bool vestingEnabled_) external onlyOwner {
        emit VestingStatusUpdated(vestingEnabled, vestingEnabled_);
        vestingEnabled = vestingEnabled_;
    }

    /**
     * @dev Sets the ICO period's start and end time.
     * @param startTime_ The start time of the ICO.
     * @param endTime_ The end time of the ICO.
     */
    function setICOPeriod(uint256 startTime_, uint256 endTime_) external onlyOwner {
        if(endTime_ <= startTime_) revert InvalidICOPeriod(startTime_, endTime_);
        if(startTime_ < block.timestamp) revert InvalidICOPeriod(startTime_, endTime_);
        startTime = startTime_;
        endTime = endTime_;
        emit ICOPeriodUpdated(startTime_, endTime_);
    }

    /**
     * @dev Sets the minimum purchase amount in ETH.
     * @param minPurchaseAmount_ The minimum purchase amount in wei.
     */
    function setMinimumPurchaseAmount(uint256 minPurchaseAmount_) external onlyOwner{
        if (minPurchaseAmount_ == 0) {
            revert InvalidMinAmount(minPurchaseAmount_);
        }
        emit MinAmountUpdated(minPurchaseAmount_);
        minPurchaseAmount = minPurchaseAmount_;
    }

    /**
     * @dev Retrieves ICO-related information.
     * @return _startTime ICO start time.
     * @return _endTime ICO end time.
     * @return _maxTokens Max tokens for the ICO.
     * @return _maxTokensPerUser Max tokens an individual can purchase.
     * @return _mintedTokens Number of tokens minted so far.
     */
    function getICOInfo() external view returns (
        uint256 _startTime,
        uint256 _endTime,
        uint256 _maxTokens,
        uint256 _maxTokensPerUser,
        uint256 _mintedTokens
    ) {
        return (startTime, endTime, maxTokens, maxTokensPerUser, mintedTokens);
    }

    /**
     * @dev Retrieves the available tokens that can still be purchased.
     * @return The number of available tokens.
     */
    function getAvailableTokens() public view returns (uint256) {
        return maxTokens - mintedTokens;
    }

    /**
     * @dev Retrieves the releasable tokens for a beneficiary based on the vesting schedule.
     * @param beneficiary The address of the beneficiary.
     * @return The number of releasable tokens.
     */
    function getReleasableTokens(address beneficiary) public view returns (uint256) {
        VestingSchedule.VestingData memory vestingData = vestings[beneficiary];
        uint256 totalReleasable = 0;

        for (uint256 i = 0; i <= currentPhaseInterval; i++) {
            totalReleasable += VestingSchedule.calculateReleasable(vestingData, phaseUserVestings[i][beneficiary]);
        }

        return totalReleasable;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
