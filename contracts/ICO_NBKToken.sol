// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./libraries/VestingSchedule_NBKToken.sol";
import "./TokenDistributor_NBKToken.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract IcoNBKToken is Ownable, Pausable, ReentrancyGuard {

    uint256 public startTime;
    uint256 public endTime;
    uint256 public maxTokens;
    uint256 public maxTokensPerUser;
    uint256 public mintedTokens;
    uint256 public cliffDurationInMonths;
    uint256 public vestingDurationInMonths;
    mapping(address => uint256) private icoPublicUserBalances;
    address payable immutable private tokenDistributorAddress;

    bool public whitelistEnabled;
    bool public vestingEnabled;

    mapping(address => bool) public whitelist;
    mapping(address => VestingSchedule.VestingData) public vestings;
    mapping(address => uint256) public lastPurchaseTime;

    uint256 public timelockDuration;
    uint256 public rate;
    uint256 public minPurchaseAmount;

    TokenDistributor private immutable tokenDistributor;

    VestingSchedule.VestingInterval[] private unlockVestingIntervals;
    mapping(uint256 => mapping(address => VestingSchedule.VestingInterval[])) public phaseUserVestings;
    uint256 public currentPhaseInterval;

    event VestingAssigned(address indexed investor, uint256 amount, uint256 currentPhaseInterval);
    event VestingStatusUpdated(bool oldStatus, bool newStatus);
    event StartTimeUpdated(uint256 oldStartTime, uint256 newStartTime);
    event EndTimeUpdated(uint256 oldEndTime, uint256 newEndTime);
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
    event EthTransferSuccess(bool success);
    event MinAmountUpdated(uint256 minAmount);

    error AddressNotInWhitelist(address investor);
    error NoTokensAvailable(uint256 amount);
    error NoReleasableTokens(address investor);
    error ICONotInActivePeriod(uint256 currentTime);
    error NoMsgValueSent(uint256 value);
    error InsufficientETHForTokenPurchase(uint256 ethPurchase);
    error TotalAmountExceeded(address investor, uint256);
    error TimeLockNotPassed(address investor, uint256 time);
    error BalanceTransferFailed(uint256 ethAmount);
    error InvalidVestingIntervals();
    error InvalidIntervalSequence(uint256 index);
    error TotalPercentageNotEqualTo100(uint256 totalPercentage);
    error InvalidAddress(address account);
    error InvalidArrayInput();
    error InvalidRateValue(uint256 rate);
    error InvalidTimelockDuration(uint256 duration);
    error InvalidStartTime(uint256 startTime);
    error InvalidEndTime(uint256 endTime, uint256 startTime);
    error InvalidMaxTokens(uint256 maxTokens);
    error InvalidMaxTokensPerUser(uint256 maxTokensPerUser);
    error InvalidICOPeriod(uint256 startTime, uint256 endTime);
    error InvalidCliff(uint256 cliff);
    error InvalidVestingDuration(uint256 vestingDuration);
    error VestingNotEnabledForManualAssignment(address investor);
    error UnlockVestingIntervalsNotDefined();
    error InvalidMinAmount(uint256 minAmount);

    constructor(address payable tokenDistributorAddress_, address ownerWallet) Ownable(ownerWallet){
        if(tokenDistributorAddress_ == address(0)) revert InvalidAddress(tokenDistributorAddress_);
        if(ownerWallet == address(0)) revert InvalidAddress(ownerWallet);
        
        tokenDistributorAddress = tokenDistributorAddress_;
        tokenDistributor = TokenDistributor(tokenDistributorAddress);
        
        startTime = block.timestamp;
        endTime = block.timestamp + 30 days;
        rate = 1000; // 1 ETH = 1000 tokens
        maxTokens = 1_000_000 * 10**18; // 1 millón de tokens
        maxTokensPerUser = 10_000 * 10**18; // 10,000 tokens por usuario
        timelockDuration = 1 days; // 1 día entre compras  
        currentPhaseInterval = 0;
        vestingDurationInMonths = 12;
        cliffDurationInMonths = 3;
        vestingEnabled = false;
        whitelistEnabled = false;
        minPurchaseAmount = 333333 * 10**12; // 1€ con eth a 3000€
        
    }

    function buyTokens() external payable whenNotPaused nonReentrant {
        uint256 tokensToBuyInWei = (msg.value * rate);
        // bool purchaseIsValid = purchaseValid(msg.sender, tokensToBuy);
        if(purchaseValid(msg.sender, tokensToBuyInWei)){
            if (vestingEnabled) {
                if (unlockVestingIntervals.length == 0){
                    revert UnlockVestingIntervalsNotDefined();
                }else{
                    if(vestings[msg.sender].totalAmount != 0 && phaseUserVestings[currentPhaseInterval][msg.sender].length != 0){
                        uint256 newTotal = vestings[msg.sender].totalAmount + tokensToBuyInWei;
                        if (newTotal  <= maxTokensPerUser) {
                            vestings[msg.sender].totalAmount = newTotal;
                        } else {
                            revert TotalAmountExceeded(msg.sender, tokensToBuyInWei);
                        }
                    } else {
                        VestingSchedule.VestingData memory vesting = VestingSchedule.createVesting(tokensToBuyInWei, cliffDurationInMonths, vestingDurationInMonths);
                        vestings[msg.sender] = vesting;
                        phaseUserVestings[currentPhaseInterval][msg.sender] = unlockVestingIntervals;
                    }
                    emit VestingAssigned(msg.sender, tokensToBuyInWei, currentPhaseInterval);
                }
            } else {
                if (icoPublicUserBalances[msg.sender] != 0 && (icoPublicUserBalances[msg.sender]) + (tokensToBuyInWei)  > maxTokensPerUser){
                    revert TotalAmountExceeded(msg.sender, tokensToBuyInWei);
                }
                icoPublicUserBalances[msg.sender] += tokensToBuyInWei;
            }

            uint256 oldMintedTokens = mintedTokens;
            mintedTokens += tokensToBuyInWei;
            lastPurchaseTime[msg.sender] = block.timestamp;

            payable(tokenDistributorAddress).transfer(msg.value);
            emit MintedTokensUpdated(oldMintedTokens, mintedTokens);
            if(!vestingEnabled) tokenDistributor.distributeTokens(msg.sender, tokensToBuyInWei, rate);
        }
    }


    function purchaseValid(address investor, uint256 amount) internal view returns (bool) {
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
        if(amount < minPurchaseAmount){
            revert InsufficientETHForTokenPurchase(amount);
        }
        if(amount > getAvailableTokens()){
            revert NoTokensAvailable(amount);
        }
        if(amount > maxTokensPerUser){
            revert TotalAmountExceeded(investor, amount);
        }
        
        return true;
    }

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

    function claimTokens() external nonReentrant {
        VestingSchedule.VestingData storage vesting = vestings[msg.sender];
        uint256 releasable = 0;
        for (uint256 i=0; i<=currentPhaseInterval; i++){
            releasable += VestingSchedule.calculateReleasable(vesting, phaseUserVestings[i][msg.sender]);
        }
        if(releasable > 0){
            vesting.claimedAmount += releasable; // Actualizar tokens reclamados
            tokenDistributor.distributeTokens(msg.sender, releasable, rate);
        }else{
            revert NoReleasableTokens(msg.sender);
        }
    }

    function setVestingIntervals(VestingSchedule.VestingInterval[] memory intervals) external onlyOwner {
        if (intervals.length == 0) {
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
    function setWhitelist(address account, bool enabled) external onlyOwner {
        if (account == address(0)) {
            revert InvalidAddress(account);
        }
        whitelist[account] = enabled;
        emit WhitelistUpdated(account, enabled);
    }

    // Setter para la whitelist (por lotes)
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

    // Setter para el rate
    function setRate(uint256 newRate) external onlyOwner {
        if (newRate == 0) {
            revert InvalidRateValue(newRate);
        }
        emit RateUpdated(rate, newRate);
        rate = newRate;
    }

    // Setter para la duración del timelock
    function setTimelockDuration(uint256 timelockDuration_) external onlyOwner {
        if (timelockDuration_ == 0) {
            revert InvalidTimelockDuration(timelockDuration_);
        }
        emit TimelockDurationUpdated(timelockDuration, timelockDuration_);
        timelockDuration = timelockDuration_;
    }

    // Setter para maxTokens
    function setMaxTokens(uint256 maxTokens_) external onlyOwner {
        if (maxTokens_ == 0) {
            revert InvalidMaxTokens(maxTokens_);
        }
        emit MaxTokensUpdated(maxTokens, maxTokens_);
        maxTokens = maxTokens_;
    }

    // Setter para maxTokensPerUser
    function setMaxTokensPerUser(uint256 maxTokensPerUser_) external onlyOwner {
        if (maxTokensPerUser_ == 0) {
            revert InvalidMaxTokensPerUser(maxTokensPerUser_);
        }
        emit MaxTokensPerUserUpdated(maxTokensPerUser, maxTokensPerUser_);
        maxTokensPerUser = maxTokensPerUser_;
    }

    function setCliffDuration(uint256 cliffDurationInMonths_) external onlyOwner {
        if (cliffDurationInMonths_ == 0) {
            revert InvalidCliff(cliffDurationInMonths_);
        }
        emit CliffUpdated(cliffDurationInMonths_);
        cliffDurationInMonths = cliffDurationInMonths_;
    }

    function setVestingDuration(uint256 vestingDuration_) external onlyOwner {
        if (vestingDuration_ == 0) {
            revert InvalidVestingDuration(vestingDuration_);
        }
        emit VestingDurationUpdated(vestingDuration_);
        vestingDurationInMonths = vestingDuration_;
    }

    // Setter para whitelistEnabled
    function setWhitelistEnabled(bool whitelistEnabled_) external onlyOwner {
        emit WhitelistStatusUpdated(whitelistEnabled, whitelistEnabled_);
        whitelistEnabled = whitelistEnabled_;
    }

    // Setter para vestingEnabled
    function setVestingEnabled(bool vestingEnabled_) external onlyOwner {
        emit VestingStatusUpdated(vestingEnabled, vestingEnabled_);
        vestingEnabled = vestingEnabled_;
    }

    function setICOPeriod(uint256 startTime_, uint256 endTime_) external onlyOwner {
        if(endTime_ <= startTime_) revert InvalidICOPeriod(startTime_, endTime_);
        if(startTime_ < block.timestamp) revert InvalidICOPeriod(startTime_, endTime_);
        startTime = startTime_;
        endTime = endTime_;
        emit ICOPeriodUpdated(startTime_, endTime_);
    }

    function setMinimumPurchaseAmount(uint256 minPurchaseAmount_) external onlyOwner{
        if (minPurchaseAmount_ == 0) {
            revert InvalidMinAmount(minPurchaseAmount_);
        }
        emit MinAmountUpdated(minPurchaseAmount_);
        minPurchaseAmount = minPurchaseAmount_;
    }

    function getICOInfo() external view returns (
        uint256 _startTime,
        uint256 _endTime,
        uint256 _maxTokens,
        uint256 _maxTokensPerUser,
        uint256 _mintedTokens
    ) {
        return (startTime, endTime, maxTokens, maxTokensPerUser, mintedTokens);
    }

    function getAvailableTokens() public view returns (uint256) {
        return maxTokens - mintedTokens;
    }

    function getReleasableTokens(address beneficiary) public view returns (uint256) {
        VestingSchedule.VestingData storage vesting = vestings[beneficiary];
        uint256 releasable = 0;
        for (uint256 i=0; i<=currentPhaseInterval; i++){
            releasable += VestingSchedule.calculateReleasable(vesting, phaseUserVestings[i][beneficiary]);
        }
        return releasable;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
