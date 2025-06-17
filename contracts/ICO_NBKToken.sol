// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {VestingSchedule} from  "./libraries/VestingSchedule_NBKToken.sol";
import {TokenDistributor} from "./TokenDistributor_NBKToken.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title IcoNBKToken
 * @dev Contract that handles token sales in an ICO with options for vesting and whitelisting.
 * @custom:security-contact dariosansano@neuro-block.com
 */
contract IcoNBKToken is Ownable, Pausable, ReentrancyGuard {

    // Chainlink Price Feed para MATIC/USD
    AggregatorV3Interface immutable maticUsdPriceFeed;

    // Precio del token NBK en USD
    uint256 public tokenPriceInUSD;

    struct Purchase {
        uint256 timestamp;
        uint256 tokens;
    }

    /// @notice Address of the token distributor.
    /// @dev It is an immutable and payable address.
    address payable immutable private tokenDistributorAddress;

    /// @notice Instance of the TokenDistributor contract.
    /// @dev Used to manage the distribution of tokens.
    TokenDistributor private immutable tokenDistributor;

    /// @notice ICO start timestamp.
    /// @dev Stored as a Unix timestamp.
    uint256 public startTime;

    /// @notice ICO end timestamp.
    /// @dev Stored as a Unix timestamp.
    uint256 public endTime;

    /// @notice Maximum number of tokens available for sale.
    uint256 public maxTokens;

    /// @notice Maximum number of tokens a user can purchase.
    uint256 public maxTokensPerUser;

    /// @notice Percentage of tokens to give to referrers
    uint256 public referedPercentage;

    /// @notice Total number of tokens sold so far.
    uint256 public soldTokens;

    /// @notice Cliff duration in months before vesting starts.
    uint256 public cliffDurationInMonths;

    /// @notice Total vesting duration in months.
    uint256 public vestingDurationInMonths;

    /// @notice Time lock duration before tokens can be accessed.
    uint256 public timelockDuration;

    /// @notice Minimum purchase amount required.
    uint256 public minPurchaseAmount;

    /// @notice Interval for the current vesting phase.
    uint256 public currentPhaseInterval;

    /// @notice Indicates whether the whitelist feature is enabled.
    bool public whitelistEnabled;

    /// @notice Indicates whether the vesting feature is enabled.
    bool public vestingEnabled;

    /// @notice Stores public ICO user balances.
    mapping(address user => uint256 balance) private icoPublicUserBalances;

    /// @notice Whitelist mapping to check if an address is allowed to participate.
    mapping(address user => bool whitelisted) public whitelist;

    /// @notice Mapping of user vesting schedules.
    mapping(uint256 currentPhase => mapping(address user => VestingSchedule.VestingData vesting)) public vestings;

    /// @notice Stores the last purchase timestamp for each address.
    mapping(address user => Purchase purchase) public purchases;

    /// @notice Stores user vesting intervals for each phase.
    mapping(uint256 currentPhase => mapping(address user => VestingSchedule.VestingInterval[] vestingIntervalAssigned)) public phaseUserVestings;

    /// @notice Array of unlock vesting intervals.
    VestingSchedule.VestingInterval[] private unlockVestingIntervals;

    uint256 public uniqueInvestors;
   

    /// @notice Mapping para almacenar las relaciones de referidos
    mapping(address => address) public referrers;

    /// @notice Evento emitido cuando se establece un referido
    event ReferrerSet(address indexed user, address indexed referrer);

    /// @notice Error cuando el usuario ya tiene un referido
    error UserAlreadyHasReferrer(address user);

    /// @notice Error cuando el referido no está registrado
    error ReferrerNotRegistered(address referrer);

    /// @notice Error cuando percentage > 100
    error InvalidReferedPercentage(uint256 percentage);
    /// ----------------- EVENTS -----------------
    // Vesting related
    /// @notice Emitted when a vesting schedule is assigned to an investor.
    event VestingAssigned(address indexed investor, uint256 indexed amount, uint256 indexed currentPhaseInterval);
    
    /// @notice Emitted when the vesting status is updated.
    event VestingStatusUpdated(bool indexed oldStatus, bool indexed newStatus);
    
    /// @notice Emitted when vesting configuration is updated.
    event VestingConfigurationUpdated(uint256 indexed duration, uint256 indexed totalIntervals);

    // Token amounts related
    /// @notice Emitted when the maximum tokens limit is updated.
    event MaxTokensUpdated(uint256 indexed oldMaxTokens, uint256 indexed newMaxTokens);

    /// @notice Emitted when the per-user token limit is updated.
    event MaxTokensPerUserUpdated(uint256 indexed oldMaxTokensPerUser, uint256 indexed newMaxTokensPerUser);

    /// @notice Emitted when the total sold tokens count is updated.
    event SoldTokensUpdated(uint256 indexed oldSoldTokens, uint256 indexed newsoldTokens);

    // Whitelist related
    /// @notice Emitted when the whitelist status is updated.
    event WhitelistStatusUpdated(bool indexed oldStatus, bool indexed newStatus);

    /// @notice Emitted when an address is added or removed from the whitelist.
    event WhitelistUpdated(address indexed account, bool indexed enabled);

    /// @notice Emitted when multiple accounts are added or removed from the whitelist.
    event BatchWhitelistUpdated(uint256 indexed totalAccounts, bool indexed enabled);

    // ICO periods related
    /// @notice Emitted when the ICO start or end period is updated.
    event ICOPeriodUpdated(uint256 indexed startTime, uint256 indexed endTime);

    /// @notice Emitted when the timelock duration is updated.
    event TimelockDurationUpdated(uint256 indexed oldDuration, uint256 indexed newDuration);

    /// @notice Emitted when the cliff period is updated.
    event CliffUpdated(uint256 indexed cliff);

    // Purchase related
    /// @notice Emitted when the minimum purchase amount is updated.
    event MinAmountPurchaseUpdated(uint256 indexed minAmount);

    /// @notice Emitted when funds are received from an investor.
    event FundsReceived(address indexed sender, uint256 indexed amount);

    /// @notice Emitted when the token price in USD is updated.
    event TokenPriceUpdated(uint256 indexed oldPrice, uint256 indexed newPrice);

    /// @notice Emitted when the referral percentage is updated.
    event ReferralPercentageUpdated(uint256 indexed oldPercentage, uint256 indexed newPercentage);

    /// ----------------- ERRORS -----------------
    // Vesting related
    /// @notice Thrown when vesting intervals are invalid.
    error InvalidVestingIntervals(uint256 month, uint256 unlockPerMonth);

    /// @notice Thrown when the vesting duration is invalid.
    error InvalidVestingDuration(uint256 vestingDuration);

    /// @notice Thrown when vesting is not enabled for manual assignment.
    error VestingNotEnabledForManualAssignment(address investor);

    /// @notice Thrown when unlock vesting intervals are not defined.
    error UnlockVestingIntervalsNotDefined();

    /// @notice Thrown when the vesting configuration is unchanged.
    error VestingEnabledConfigNotChanging(bool vestingEnabled);

    /// @notice Thrown when the vesting interval sequence is invalid.
    error InvalidVestingIntervalSequence(uint256 index);

    /// @notice Thrown when total percentage intervals do not sum to 100%.
    error TotalPercentageIntervalsNotEqualTo100(uint256 totalPercentage);

    // Token amounts related
    /// @notice Thrown when there are no available tokens.
    error NoTokensAvailable(uint256 amount);

    /// @notice Thrown when an investor has no releasable tokens.
    error NoReleasableTokens(address investor);

    /// @notice Thrown when the max token limit is invalid.
    error InvalidMaxTokens(uint256 maxTokens);

    /// @notice Thrown when the max tokens per user limit is invalid.
    error InvalidMaxTokensPerUser(uint256 maxTokensPerUser);

    /// @notice Thrown when the max token limit remains unchanged.
    error MaxTokensNotChanged(uint256 maxTokens);

    // Whitelist related
    /// @notice Thrown when an address is not in the whitelist.
    error AddressNotInWhitelist(address investor);

    /// @notice Thrown when an account is already whitelisted.
    error AccountWhitelisted(bool enabled);

    /// @notice Thrown when the whitelist array input is invalid.
    error InvalidWhitelistArrayInput();

    /// @notice Thrown when the whitelist status remains unchanged.
    error WhitelistEnabledConfigNotChanging(bool whitelistEnabled);

    // ICO periods related
    /// @notice Thrown when the ICO is not in the active period.
    error ICONotInActivePeriod(uint256 currentTime);

    /// @notice Thrown when the ICO period configuration is invalid.
    error InvalidICOPeriod(uint256 startTime, uint256 endTime);

    /// @notice Thrown when the cliff duration is invalid.
    error InvalidCliff(uint256 cliff);

    // Purchase related 
    /// @notice Thrown when the time lock period has not passed.
    error TimeLockNotPassed(address investor, uint256 time);

    /// @notice Thrown when the timelock duration remains unchanged.
    error TimelockDurationNotChanged(uint256 time);

    /// @notice Thrown when no ETH value is sent in a transaction.
    error NoMsgValueSent(uint256 value);

    /// @notice Thrown when the minimum purchase amount is invalid.
    error InvalidMinPurchaseAmount(uint256 minAmount);

    /// @notice Thrown when there is insufficient ETH for token purchase.
    error InsufficientETHForTokenPurchase(uint256 ethPurchase);

    /// @notice Thrown when the total purchase amount exceeds the limit.
    error TotalAmountPurchaseExceeded(address investor, uint256 amount);

    // Other
    /// @notice Thrown when an invalid address is used.
    error InvalidAddress(address account);

    /// @notice Thrown when the timelock duration is invalid.
    error InvalidTimelockDuration(uint256 duration);

    /// @notice Throw when not ico is calling
    error NotICOorOwnerContractCalling(address sender);

    /// @notice Thrown when not correct referred address
    error InvalidReferedAddress(address refered);

    /**
     * @dev Constructor to initialize the ICO contract.
     * @param tokenDistributorAddress_ Address of the TokenDistributor contract.
     * @param ownerWallet Address of the contract owner.
     * @param maticUsdPriceFeedAddress Address of the Chainlink MATIC/USD price feed.
     * @param tokenPriceInUSD_ Initial price of the NBK token in USD (with 8 decimals).
     */
    constructor(
        address tokenDistributorAddress_,
        address ownerWallet,
        address maticUsdPriceFeedAddress,
        uint256 tokenPriceInUSD_,
        uint256 secondsICOwillStart_, 
        uint256 icoDurationInDays_
        ) 
        Ownable(ownerWallet)
        {
        if(tokenDistributorAddress_ == address(0)) revert InvalidAddress(tokenDistributorAddress_);
        if(maticUsdPriceFeedAddress == address(0)) revert InvalidAddress(maticUsdPriceFeedAddress);
        
        tokenDistributorAddress = payable(tokenDistributorAddress_);
        tokenDistributor = TokenDistributor(tokenDistributorAddress);
        maticUsdPriceFeed = AggregatorV3Interface(maticUsdPriceFeedAddress);
        tokenPriceInUSD = tokenPriceInUSD_;
        referedPercentage = 5; // 5% por defecto
        
        startTime = block.timestamp + secondsICOwillStart_; // dentro de x segundos
        endTime = startTime + (icoDurationInDays_ * 24 * 60 * 60); 
        maxTokens = 1_000_000 * 10**18; // 1 million tokens
        maxTokensPerUser = 10_000 * 10**18; // 10,000 tokens per user
        timelockDuration = 1 * 60 * 60; // 1 hour between purchases  
        vestingDurationInMonths = 12;
        cliffDurationInMonths = 3;
        vestingEnabled = false;
        whitelistEnabled = false;
        currentPhaseInterval = 0;
        minPurchaseAmount = 333333 * 10**12; // 1€ with ETH at 3000€
        uniqueInvestors=0;
    }

    /**
     * @dev Updates the token price in USD.
     * @param newPrice New price of the token in USD (with 8 decimals).
     */
    function setTokenPriceInUSD(uint256 newPrice) external onlyOwner {
        uint256 oldPrice = tokenPriceInUSD;
        tokenPriceInUSD = newPrice;
        emit TokenPriceUpdated(oldPrice, newPrice);
    }

    /**
     * @dev Gets the latest MATIC/USD price from Chainlink.
     * @return The latest price with 8 decimals.
     */
    function getLatestMaticPrice() public view returns (uint256) {
        (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = maticUsdPriceFeed.latestRoundData();

        if (price <= 0) {
            revert ("Invalid price from oracle");
        }

        return uint256(price);
    }

    /**
     * @dev Allows an investor to purchase tokens with MATIC. The number of tokens purchased is based on the current MATIC/USD price.
     * @param referedUser Address of the referrer.
     *
     * @notice Reverts with custom errors if any conditions fail:
     * - `UnlockVestingIntervalsNotDefined`: if vesting is enabled but intervals are not set.
     * - `TotalAmountPurchaseExceeded`: if the investor exceeds their token limit.
     * - `NoTokensAvailable`: if there are insufficient tokens available.
     * - `AddressNotInWhitelist`: if the investor is not whitelisted (if whitelist is enabled).
     * - `ICONotInActivePeriod`: if the ICO is not in the active time window.
     * 
     * @dev This function is protected with `whenNotPaused` and `nonReentrant` modifiers.
     */
    function buyTokens(
        address referedUser
    ) external payable whenNotPaused nonReentrant {
        // Obtener el precio de MATIC y verificar que sea válido
        
        uint256 maticPrice = getLatestMaticPrice();
        

        // Calcular tokens basado en el precio de MATIC y el precio del token NBK
        // msg.value está en wei (18 decimals), maticPrice tiene 8 decimals, tokenPriceInUSD tiene 8 decimals
        uint256 tokensToBuyInWei = (msg.value * maticPrice * 10**8) / (tokenPriceInUSD * 10**8);
        address investor = _msgSender();

        // Control de referido
        bool hasReferrer = referrers[investor] != address(0);
        address actualReferrer = hasReferrer ? referrers[investor] : address(0);

        // Si se proporciona un referido en la llamada, debe coincidir con el registrado
        if (referedUser == investor) revert InvalidReferedAddress(referedUser);
        else if (hasReferrer && (referedUser != address(0) && referedUser != actualReferrer)) revert ReferrerNotRegistered(referedUser);

        checkValidPurchase(investor, tokensToBuyInWei);

        if (vestingEnabled) {
            assignVestingInternal(
                investor,
                tokensToBuyInWei,
                cliffDurationInMonths,
                vestingDurationInMonths,
                true,
                actualReferrer
            );
        } else {
            if (
                icoPublicUserBalances[investor] != 0 &&
                (icoPublicUserBalances[investor] + tokensToBuyInWei > maxTokensPerUser)
            ) {
                revert TotalAmountPurchaseExceeded(investor, tokensToBuyInWei);
            }

            icoPublicUserBalances[investor] += tokensToBuyInWei;
        }

        // Efectos antes de interacciones
        soldTokens += tokensToBuyInWei;

        if (purchases[investor].tokens == 0) {
            ++uniqueInvestors;
            purchases[investor].timestamp = block.timestamp;
            purchases[investor].tokens = tokensToBuyInWei;
        }

        emit SoldTokensUpdated(soldTokens - tokensToBuyInWei, soldTokens);

        // 🔒 Todas las interacciones después del estado

        // 1. Transferir fondos al distributor
        Address.sendValue(tokenDistributorAddress, msg.value);

        // 2. Distribuir tokens si NO hay vesting
        if (!vestingEnabled) {
            if (hasReferrer) {
                uint256 tokensForReferred = Math.mulDiv(tokensToBuyInWei, referedPercentage, 100);
                tokenDistributor.distributeTokens(actualReferrer, tokensForReferred);
            }

            tokenDistributor.distributeTokens(investor, tokensToBuyInWei);
        }
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
    function checkValidPurchase(address investor, uint256 tokensToBuyInWei) private {
        if(purchases[investor].timestamp != 0 && block.timestamp < purchases[investor].timestamp + timelockDuration){
            revert TimeLockNotPassed(investor, purchases[investor].timestamp + timelockDuration);
        }
        if(block.timestamp < startTime || block.timestamp > endTime){
            revert ICONotInActivePeriod(block.timestamp);
        }
        if(whitelistEnabled && !whitelist[investor]){
            revert AddressNotInWhitelist(investor);
        }
        if(msg.value < 1){
            revert NoMsgValueSent(msg.value);
        }
        if(tokensToBuyInWei < minPurchaseAmount){
            revert InsufficientETHForTokenPurchase(tokensToBuyInWei);
        }
        if(tokensToBuyInWei > getAvailableTokens()){
            revert NoTokensAvailable(tokensToBuyInWei);
        }
        if(tokensToBuyInWei > maxTokensPerUser){
            revert TotalAmountPurchaseExceeded(investor, tokensToBuyInWei);
        }
    }

    /**
     * @dev Allows the investor to claim the released tokens.
     * @notice Tokens are released according to the vesting schedule.
     * @return Success if claimed some tokens
     */
    /// #if_succeeds {:msg "Tokens successfully claimed"} old(vestings[_msgSender()].claimedAmount) < vestings[_msgSender()].claimedAmount;
    function claimTokens(uint256 amount) external nonReentrant returns (bool tokensClaimed){
        uint256 totalReleasable = 0;

        for (uint256 i; i<=currentPhaseInterval;++i){
            VestingSchedule.VestingData storage vesting = vestings[i][_msgSender()];
            uint256 releasable = VestingSchedule.calculateReleasable(vesting, phaseUserVestings[i][_msgSender()]);
            if (releasable != 0) {
                vesting.claimedAmount += releasable;
                totalReleasable += releasable;
            }
        }
        if(totalReleasable >= amount){
            tokenDistributor.distributeTokens(_msgSender(), amount);
        }else{
            revert NoReleasableTokens(_msgSender());
        }
        return true;
    }

    function assignVesting(address investor, uint256 amount, uint256 cliff, uint256 duration, bool isPurchase, address referedUser) external onlyOwner {
        assignVestingInternal(investor, amount, cliff, duration, isPurchase, referedUser);
    }


    /**
     * @dev Manually assigns tokens with a vesting schedule to an investor.
     * @param investor Address of the investor.
     * @param amount Amount of tokens to be assigned.
     * @param cliff Duration of the cliff in months.
     * @param duration Duration of the vesting in months.
     */
    /// #if_succeeds { :msg "Vesting assigned manually" } old(vestings[investor].totalAmount) < vestings[investor].totalAmount;
    function assignVestingInternal(address investor, uint256 amount, uint256 cliff, uint256 duration, bool isPurchase, address referedUser) private {
        if (vestingEnabled) {
            if(unlockVestingIntervals.length != 0){
                if(vestings[currentPhaseInterval][investor].totalAmount != 0 && phaseUserVestings[currentPhaseInterval][investor].length != 0){
                    uint256 newTotal = vestings[currentPhaseInterval][investor].totalAmount + amount;
                    if(isPurchase){
                        if (newTotal  <= maxTokensPerUser) {
                            vestings[currentPhaseInterval][investor].totalAmount = newTotal;
                        } else {
                            revert TotalAmountPurchaseExceeded(investor, amount);
                        }
                    }else{
                        vestings[currentPhaseInterval][investor].totalAmount = newTotal;
                    }
                }else {
                    VestingSchedule.VestingData memory vesting = VestingSchedule.createVesting(amount, cliff, duration);
                    vestings[currentPhaseInterval][investor] = vesting;
                    phaseUserVestings[currentPhaseInterval][investor] = unlockVestingIntervals;
                }

                if (address(referedUser) != address(0) && address(referedUser) != address(investor)){
                    uint256 tokensForReferred = Math.mulDiv(amount,referedPercentage,100);                
                    VestingSchedule.VestingData memory referredVesting = VestingSchedule.createVesting(tokensForReferred, cliff, duration);
                    vestings[currentPhaseInterval][referedUser] = referredVesting;
                    phaseUserVestings[currentPhaseInterval][referedUser] = unlockVestingIntervals;
                    emit VestingAssigned(referedUser, tokensForReferred, currentPhaseInterval);
                }

                emit VestingAssigned(investor, amount, currentPhaseInterval);
            }else{
                revert UnlockVestingIntervalsNotDefined();
            }
        }else{
            revert VestingNotEnabledForManualAssignment(investor);
        }

        
    }

    /**
     * @dev Updates the vesting duration and intervals for the ICO.
     * @param intervals The array of vesting intervals to be set.
     * @param vestingDuration_ Duration of the vesting in months.
     * @notice Only the owner can update vesting intervals.
     */
    /// #if_succeeds { :msg "Vesting configuration set " } intervals[intervals.length -1].endMonth == vestingDurationInMonths;
    function setVestingConfiguration(uint256 vestingDurationInMonths_, VestingSchedule.VestingInterval[] memory intervals) external onlyOwner {
        uint256 totalPercentage;
        uint256 lastEndMonth;
        uint256 intervalsLength = intervals.length;
        
        if (vestingDurationInMonths_ < 1) {
            revert InvalidVestingDuration(vestingDurationInMonths_);
        }

        if (intervalsLength == 0) {
            revert InvalidVestingIntervals(0,0);
        }


        if (intervals[intervalsLength -1].endMonth != vestingDurationInMonths_){
            revert InvalidVestingIntervals(intervals[intervalsLength -1].endMonth, intervals[intervalsLength -1].unlockPerMonth);
        }

        for (uint256 i; i < intervalsLength; ++i) {
            if (intervals[i].endMonth <= lastEndMonth) {
                revert InvalidVestingIntervalSequence(i);
            }
            if (intervals[i].unlockPerMonth < 1) {
                revert InvalidVestingIntervals(intervals[i].endMonth, intervals[i].unlockPerMonth);
            }
            
            uint256 monthsInInterval = intervals[i].endMonth - (i == 0 ? 0 : intervals[i-1].endMonth);
            uint256 intervalPercentage = intervals[i].unlockPerMonth * monthsInInterval;
            
            totalPercentage += intervalPercentage;
            lastEndMonth = intervals[i].endMonth;
        }

        uint256 percentageTotal = totalPercentage/1000;
        if ( percentageTotal != 100) { // 3 decimales
            revert TotalPercentageIntervalsNotEqualTo100(totalPercentage);
        }

        delete unlockVestingIntervals;
        for (uint256 i; i < intervalsLength; ++i) {
            unlockVestingIntervals.push(intervals[i]);
        }
        vestingDurationInMonths = vestingDurationInMonths_;
        currentPhaseInterval++;
        emit VestingConfigurationUpdated(vestingDurationInMonths_, intervalsLength);
    }

    /**
     * @dev Adds or removes an address from the whitelist.
     * @param account Address to be whitelisted.
     * @param enabled Boolean value to enable or disable the address.
     */
    /// #if_succeeds { :msg "Account added to whitelist" } old(whitelist[account]) != whitelist[account];
    function setWhitelist(address account, bool enabled) external onlyOwner {
        if (account == address(0)) {
            revert InvalidAddress(account);
        }

        if (whitelist[account] == enabled) {
            revert AccountWhitelisted(enabled);
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
    /// #if_succeeds { :msg "Perform batch whitelist" } batchPerformed == true;
    function setWhitelistBatch(address[] memory accounts, bool enabled) external onlyOwner{
        uint256 accountsLength = accounts.length;
        if (accountsLength == 0) {
            revert InvalidWhitelistArrayInput();
        }

        for (uint256 i; i < accountsLength; ++i) {
            if (accounts[i] == address(0)) {
                revert InvalidAddress(accounts[i]);
            }
            whitelist[accounts[i]] = enabled;
        }

        emit BatchWhitelistUpdated(accountsLength, enabled);
    }

    /**
     * @dev Sets the duration of the timelock between purchases.
     * @param timelockDuration_ The new timelock duration in seconds.
     */
    /// #if_succeeds { :msg "Timelock duration change correctly" } old(timelockDuration) != timelockDuration;
    function setTimelockDurationInMinutes(uint256 timelockDurationinMinutes_) external onlyOwner {
        uint256 timelockDurationUpdated = timelockDurationinMinutes_ * 60;
        if (timelockDurationinMinutes_ < 1) {
            revert InvalidTimelockDuration(timelockDurationinMinutes_);
        }
        if (timelockDuration == timelockDurationUpdated) {
            revert TimelockDurationNotChanged(timelockDurationUpdated);
        }
        emit TimelockDurationUpdated(timelockDuration, timelockDurationUpdated);
        timelockDuration = timelockDurationUpdated;
    }

    /**
     * @dev Sets the maximum number of tokens that can be minted.
     * @param maxTokens_ The maximum token supply.
     */
    /// #if_succeeds { :msg "Max tokens updated correctly" } old(maxTokens) != maxTokens;
    function setMaxTokens(uint256 maxTokens_) external onlyOwner {
        uint256 updatedTokens = maxTokens_ * 10**18;
        if (updatedTokens < 1 * 10 ** 18) {
            revert InvalidMaxTokens(maxTokens_);
        }
        if (maxTokens == updatedTokens) {
            revert MaxTokensNotChanged(maxTokens_);
        }
        emit MaxTokensUpdated(maxTokens , updatedTokens);
        maxTokens = updatedTokens;
    }

    /**
     * @dev Sets the maximum tokens an individual can purchase.
     * @param maxTokensPerUser_ The maximum token limit per user.
     */
    /// #if_succeeds { :msg "Max tokens updated correctly" } old(maxTokens) != maxTokens;
    function setMaxTokensPerUser(uint256 maxTokensPerUser_) external onlyOwner {
        if (maxTokensPerUser_ < 1) {
            revert InvalidMaxTokensPerUser(maxTokensPerUser_);
        }
        emit MaxTokensPerUserUpdated(maxTokensPerUser, maxTokensPerUser_);
        maxTokensPerUser = maxTokensPerUser_ * 10**18;
    }

    /**
     * @dev Sets the cliff duration for vesting.
     * @param cliffDurationInMonths_ Duration of the cliff in months.
     */
    function setCliffDuration(uint256 cliffDurationInMonths_) external onlyOwner {
        if (cliffDurationInMonths_ < 1) {
            revert InvalidCliff(cliffDurationInMonths_);
        }
        emit CliffUpdated(cliffDurationInMonths_);
        cliffDurationInMonths = cliffDurationInMonths_;
    }

    /**
     * @dev Enables or disables the whitelist.
     * @param whitelistEnabled_ Boolean value to enable or disable the whitelist.
     */
    /// #if_succeeds { :msg "Whitelist enabled should change" } old(whitelistEnabled) != whitelistEnabled;
    function setWhitelistEnabled(bool whitelistEnabled_) external onlyOwner {
        if(whitelistEnabled == whitelistEnabled_) revert WhitelistEnabledConfigNotChanging(whitelistEnabled_);
        emit WhitelistStatusUpdated(whitelistEnabled, whitelistEnabled_);
        whitelistEnabled = whitelistEnabled_;
    }

    /**
     * @dev Enables or disables the vesting feature.
     * @param vestingEnabled_ Boolean value to enable or disable vesting.
     */
    /// #if_succeeds { :msg "Vesting enabled should change" } old(vestingEnabled) != vestingEnabled;
    function setVestingEnabled(bool vestingEnabled_) external onlyOwner {
        if(vestingEnabled == vestingEnabled_) revert VestingEnabledConfigNotChanging(vestingEnabled_);
        emit VestingStatusUpdated(vestingEnabled, vestingEnabled_);
        vestingEnabled = vestingEnabled_;
    }

    /**
     * @dev Sets the ICO period's start and end time.
     * @param startTime_ The start time of the ICO.
     * @param endTime_ The end time of the ICO.
     */
    /// #if_succeeds { :msg "Set ICO Period Correctly " } startTime < endTime && startTime > block.timestamp;
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
    /// #if_succeeds { :msg "Set price minimum correctly" } minPurchaseAmount > 0 && old(minPurchaseAmount) != minPurchaseAmount;
    function setMinimumPurchaseAmount(uint256 minPurchaseAmount_) external onlyOwner{
        if (minPurchaseAmount_ < 1) {
            revert InvalidMinPurchaseAmount(minPurchaseAmount_);
        }
        emit MinAmountPurchaseUpdated(minPurchaseAmount_);
        minPurchaseAmount = minPurchaseAmount_;
    }

    /**
     * @dev Retrieves ICO-related information.
     * @return _startTime ICO start time.
     * @return _endTime ICO end time.
     * @return _maxTokens Max tokens for the ICO.
     * @return _maxTokensPerUser Max tokens an individual can purchase.
     * @return _soldTokens Number of tokens minted so far.
     */
    /// #if_succeeds { :msg "Get ICO info correct" } _startTime > block.timestamp && _endTime < block.timestamp && _maxTokensPerUser > 0 && _maxTokens >= soldTokens;
    function getICOInfo() external view returns (
        uint256 _startTime,
        uint256 _endTime,
        uint256 _maxTokens,
        uint256 _maxTokensPerUser,
        uint256 _soldTokens,
        uint256 _uniqueInvestors
    ) {
        return (startTime, endTime, maxTokens, maxTokensPerUser, soldTokens, uniqueInvestors);
    }

    /**
     * @dev Retrieves the available tokens that can still be purchased.
     * @return The number of available tokens.
     */
    /// #if_succeeds { :msg "Get tokens available" }  soldTokens <= maxTokens ;
    function getAvailableTokens() public view returns (uint256 availableTokens) {
        return maxTokens - soldTokens;
    }

    /**
     * @dev Retrieves the releasable tokens for a beneficiary based on the vesting schedule.
     * @param beneficiary The address of the beneficiary.
     * @return The number of releasable tokens.
     */
    /// #if_succeeds { :msg "getReleasableTokens correctly" } releasable >= 0;
    function getReleasableTokens(address beneficiary) external view returns (uint256 releasable) {
        uint256 totalReleasable;

        for (uint256 i; i <= currentPhaseInterval; ++i) {
            VestingSchedule.VestingData memory vestingData = vestings[i][beneficiary];
            totalReleasable += VestingSchedule.calculateReleasable(vestingData, phaseUserVestings[i][beneficiary]);
        }

        return totalReleasable;
    }

    /**
     * @dev Retrieves the purchased tokens for a beneficiary based on all vestings schedules.
     * @param beneficiary The address of the beneficiary.
     * @return The number of purchased tokens.
     */
    /// #if_succeeds { :msg "getReleasableTokens correctly" } releasable >= 0;
    function getVestedAmount(address beneficiary) external view returns (uint256 totalAmount) {
        uint256 totalVested;
        //get all vestings from all phases
        for (uint256 i; i <= currentPhaseInterval; ++i){
            VestingSchedule.VestingData memory vestingData = vestings[i][beneficiary];
            totalVested += vestingData.totalAmount;
        }
        return totalVested;
    }

    /**
     * @dev Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev This function withdraw the balance in the ico contract if some balance transfer to the distributor
     * on the purchase due to net problems. Use in case of internal balance transfer failures.
     */
    function withdraw() external onlyOwner whenNotPaused nonReentrant {
        Address.sendValue(payable(owner()),address(this).balance);
    }

    /**
     * @dev Receive funds
     */
    receive() external payable {
        emit FundsReceived(_msgSender(), msg.value);
    }

    /**
     * @dev Establece el referido para un usuario
     * @param user Dirección del usuario
     * @param referrer Dirección del referido
     */
    function setReferrer(address user, address referrer) external {
        if (user == address(0) || referrer == address(0)) {
            revert InvalidAddress(user == address(0) ? user : referrer);
        }
        if (user == referrer) {
            revert InvalidReferedAddress(referrer);
        }
        if (referrers[user] != address(0)) {
            revert UserAlreadyHasReferrer(user);
        }
        referrers[user] = referrer;
        emit ReferrerSet(user, referrer);
    }

    /**
     * @dev Sets the referral percentage
     * @param newPercentage New percentage for referrals
     */
    function setReferedPercentage(uint256 newPercentage) external onlyOwner {
        if (newPercentage > 100) revert InvalidReferedPercentage(newPercentage);
        uint256 oldPercentage = referedPercentage;
        referedPercentage = newPercentage;
        emit ReferralPercentageUpdated(oldPercentage, newPercentage);
    }
}

