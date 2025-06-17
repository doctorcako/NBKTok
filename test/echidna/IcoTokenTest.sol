// SPDX-License-Identifier: MIT
import "./TokenDistributorTest.sol";
import "./Dependencies.sol";


pragma solidity ^0.8.20;

/**
 * @title VestingSchedule
 * @notice Library for managing vesting schedules, including the creation of vesting data and calculating releasable tokens.
 * 
 * Provides functionality to:
 * - Create a vesting schedule with a total amount, cliff time, and duration.
 * - Calculate how many tokens are releasable based on elapsed time and vesting intervals.
 */
library VestingSchedule {

    struct VestingData {
        uint256 totalAmount;      // Total amount of tokens to be vested
        uint256 claimedAmount;    // Amount of tokens already claimed
        uint256 startTime;        // Timestamp when the vesting started
        uint256 cliffInMonths;   // Cliff duration in months before any tokens can be claimed
        uint256 durationInMonths; // Total duration of the vesting period in months
    }

    struct VestingInterval {
        uint256 endMonth;         // The month ending this vesting interval
        uint256 unlockPerMonth;   // Percentage of totalAmount to unlock per month in this interval
    }

    error InvalidCliffTime(uint256 cliff, uint256 amount );

    /**
     * @dev Creates a vesting schedule for an address. Ensures that the cliff time is less than the total vesting duration.
     * 
     * @param totalAmount The total amount of tokens to be vested.
     * @param cliff Duration in months before any tokens are unlocked.
     * @param duration Total duration of the vesting period in months.
     * 
     * @return vestingData The created vesting data for the user.
     * 
     * @notice Reverts if the cliff time is greater than or equal to the total vesting duration.
     */
    function createVesting(uint256 totalAmount, uint256 cliff, uint256 duration) internal view returns (VestingData memory) {
        if(cliff >= duration){
            revert InvalidCliffTime(cliff, duration);
        }
        VestingData memory vestingData = VestingData({
            totalAmount: totalAmount,
            claimedAmount: 0,
            startTime: block.timestamp,
            cliffInMonths: cliff,
            durationInMonths: duration
        });

        return vestingData;
    }

    /**
     * @dev Calculates the amount of tokens that can be claimed based on the vesting schedule and vesting intervals.
     * 
     * @param vesting The vesting data for the user.
     * @param vestingIntervals The array of vesting intervals with unlock percentages.
     * 
     * @return releasableTokens The number of tokens that can be claimed based on the elapsed time and intervals.
     * 
     * @notice Reverts if the tokens are still locked due to the cliff.
     */
    function calculateReleasable(VestingData memory vesting, VestingInterval[] memory vestingIntervals) internal view returns (uint256) {
        // Verificar si estamos dentro del período de cliff
        if (block.timestamp < vesting.startTime + vesting.cliffInMonths * 30 days) {
            return 0; // Tokens aún bloqueados por el cliff
        }

        uint256 elapsedMonths = (block.timestamp - (vesting.startTime + (vesting.cliffInMonths * 30 days))) / 30 days; // Calcular meses transcurridos
        if (elapsedMonths > vesting.durationInMonths) {
            elapsedMonths = vesting.durationInMonths;
        }

        uint256 totalUnlockedPercentage = 0; // Porcentaje acumulado desbloqueado
        uint256 vestingIntervalsLength = vestingIntervals.length;

        for (uint256 i; i < vestingIntervalsLength; i++) {
            VestingInterval memory interval = vestingIntervals[i];

            if (elapsedMonths >= interval.endMonth) {
                totalUnlockedPercentage += (interval.endMonth - (i == 0 ? 0 : vestingIntervals[i - 1].endMonth)) * interval.unlockPerMonth;
            } else {
                // Si aún estamos dentro de este intervalo, desbloquear proporcionalmente
                uint256 monthsInInterval = elapsedMonths - (i == 0 ? 0 : vestingIntervals[i - 1].endMonth);
                totalUnlockedPercentage += monthsInInterval * interval.unlockPerMonth;
                break;
            }
        }
        // Calcular tokens desbloqueados basados en el porcentaje total desbloqueado
        uint256 totalUnlockedTokens = (vesting.totalAmount * totalUnlockedPercentage) / 100_000;
        return totalUnlockedTokens > vesting.claimedAmount ? totalUnlockedTokens - vesting.claimedAmount : 0;
    }
}

contract IcoNBKToken is Ownable, Pausable, ReentrancyGuard {

    // Chainlink Price Feed para MATIC/USD
    MockAggregatorV3Interface internal maticUsdPriceFeed;

    // Precio del token NBK en USD
    uint256 public tokenPriceInUSD;

    struct Purchase {
        uint256 timestamp;
        uint256 tokens;
    }

    /// @notice Address of the token distributor.
    /// @dev It is an immutable and payable address.
    address payable immutable public tokenDistributorAddress;

    /// @notice Instance of the TokenDistributor contract.
    /// @dev Used to manage the distribution of tokens.
    TokenDistributor public immutable tokenDistributor;

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
    mapping(address user => uint256 balance) public icoPublicUserBalances;

    /// @notice Whitelist mapping to check if an address is allowed to participate.
    mapping(address user => bool whitelisted) public whitelist;

    /// @notice Mapping of user vesting schedules.
    mapping(uint256 currentPhase => mapping(address user => VestingSchedule.VestingData vesting)) public vestings;

    /// @notice Stores the last purchase timestamp for each address.
    mapping(address user => Purchase purchase) public purchases;

    /// @notice Stores user vesting intervals for each phase.
    mapping(uint256 currentPhase => mapping(address user => VestingSchedule.VestingInterval[] vestingIntervalAssigned)) public phaseUserVestings;

    /// @notice Array of unlock vesting intervals.
    VestingSchedule.VestingInterval[] public unlockVestingIntervals;

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
        maticUsdPriceFeed = MockAggregatorV3Interface(maticUsdPriceFeedAddress);
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
    function setTokenPriceInUSD(uint256 newPrice) public onlyOwner {
        tokenPriceInUSD = newPrice;
    }

    /**
     * @dev Gets the latest MATIC/USD price from Chainlink.
     * @return The latest price with 8 decimals.
     */
    function getLatestMaticPrice() public view returns (uint256) {
        (, int256 price,,,) = maticUsdPriceFeed.latestRoundData();

        if (price <= 0) {
            revert("Invalid price from oracle");
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
    ) public payable whenNotPaused nonReentrant {
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
    function checkValidPurchase(address investor, uint256 tokensToBuyInWei) internal {
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
    function claimTokens(uint256 amount) public nonReentrant returns (bool tokensClaimed){
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

    function assignVesting(address investor, uint256 amount, uint256 cliff, uint256 duration, bool isPurchase, address referedUser) public onlyOwner {
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
    function assignVestingInternal(address investor, uint256 amount, uint256 cliff, uint256 duration, bool isPurchase, address referedUser) public {
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
    function setVestingConfiguration(uint256 vestingDurationInMonths_, VestingSchedule.VestingInterval[] memory intervals) public onlyOwner {
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
    function setWhitelist(address account, bool enabled) public onlyOwner {
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
    function setWhitelistBatch(address[] memory accounts, bool enabled) public onlyOwner{
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
    function setTimelockDurationInMinutes(uint256 timelockDurationinMinutes_) public onlyOwner {
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
    function setMaxTokens(uint256 maxTokens_) public onlyOwner {
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
    function setMaxTokensPerUser(uint256 maxTokensPerUser_) public onlyOwner {
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
    function setCliffDuration(uint256 cliffDurationInMonths_) public onlyOwner {
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
    function setWhitelistEnabled(bool whitelistEnabled_) public onlyOwner {
        if(whitelistEnabled == whitelistEnabled_) revert WhitelistEnabledConfigNotChanging(whitelistEnabled_);
        emit WhitelistStatusUpdated(whitelistEnabled, whitelistEnabled_);
        whitelistEnabled = whitelistEnabled_;
    }

    /**
     * @dev Enables or disables the vesting feature.
     * @param vestingEnabled_ Boolean value to enable or disable vesting.
     */
    /// #if_succeeds { :msg "Vesting enabled should change" } old(vestingEnabled) != vestingEnabled;
    function setVestingEnabled(bool vestingEnabled_) public onlyOwner {
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
    function setICOPeriod(uint256 startTime_, uint256 endTime_) public onlyOwner {
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
    function setMinimumPurchaseAmount(uint256 minPurchaseAmount_) public onlyOwner{
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
    function getICOInfo() public view returns (
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
    function getReleasableTokens(address beneficiary) public view returns (uint256 releasable) {
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
    function getVestedAmount(address beneficiary) public view returns (uint256 totalAmount) {
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
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause contract
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev This function withdraw the balance in the ico contract if some balance transfer to the distributor
     * on the purchase due to net problems. Use in case of internal balance transfer failures.
     */
    function withdraw() public onlyOwner whenNotPaused nonReentrant {
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
    function setReferrer(address user, address referrer) public {
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
    function setReferedPercentage(uint256 newPercentage) public onlyOwner {
        if (newPercentage > 100) revert InvalidReferedPercentage(newPercentage);
        referedPercentage = newPercentage;
    }
}



contract MockTokenDistributor is TokenDistributor {
    MockToken public testToken;
    constructor() TokenDistributor(address(new MockToken()), _msgSender(), 10 * 10**18) {
        testToken = MockToken(address(token)); // Guardar referencia al token
        testToken.mint(address(_msgSender()), 1_000_000);
    }
}

interface IAggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function getRoundData(uint80 _roundId) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

contract MockAggregatorV3Interface is IAggregatorV3Interface {
    int256 public price;
    uint8 public decimals_;
    uint256 public lastUpdateTime;
    uint80 public currentRoundId;
    uint80 public currentAnsweredInRound;

    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        decimals_ = _decimals;
        lastUpdateTime = block.timestamp;
        currentRoundId = 1;
        currentAnsweredInRound = 1;
    }

    function decimals() external view override returns (uint8) {
        return decimals_;
    }

    function description() external pure override returns (string memory) {
        return "Mock MATIC/USD Price Feed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 roundId) external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (roundId, price, block.timestamp - 1, lastUpdateTime, currentAnsweredInRound);
    }

    function latestRoundData() external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (currentRoundId, price, block.timestamp - 1, lastUpdateTime, currentAnsweredInRound);
    }
}

contract IcoNBKTokenTest is IcoNBKToken {
    MockTokenDistributor public mockTokenDistributor;
    MockAggregatorV3Interface public mockPriceFeed;

    constructor() IcoNBKToken(
        address(new MockTokenDistributor()),
        _msgSender(),
        address(new MockAggregatorV3Interface(100000000, 8)), // 1 MATIC = 1 USD
        100000000, // 1 USD por token
        0,
        30
    ) {
        mockTokenDistributor = MockTokenDistributor(tokenDistributorAddress);
        mockPriceFeed = MockAggregatorV3Interface(address(maticUsdPriceFeed));
        VestingSchedule.VestingInterval memory v = VestingSchedule.VestingInterval(10, 10);
        unlockVestingIntervals.push(v);
    }

    function echidna_test_invalid_cliff() public returns (bool) {
        (bool success, ) = address(this).call(
            abi.encodeWithSignature("createVesting(uint256,uint256,uint256)", 1000, 12, 6)
        );
        return !success;
    }

    function echidna_test_vesting_assignment() public returns (bool) {
        if(!vestingEnabled) {
            return true;
        }

        if(_msgSender() != owner() || _msgSender() != address(this)){
            return true;
        }

        assignVesting(_msgSender(),1000,3,12,false, address(0));
        VestingSchedule.VestingData memory vesting = vestings[0][_msgSender()];

        return (
            vesting.totalAmount == 1000 &&
            vesting.claimedAmount == 0 &&
            vesting.cliffInMonths == 3 &&
            vesting.durationInMonths == 12 &&
            vesting.startTime > 0
        );
    }

    function echidna_test_referrer_set() public returns (bool) {
        // Solo permitir que el owner o el contrato de prueba ejecuten esta función
        if (_msgSender() != owner() && _msgSender() != address(this)) {
            return true;
        }

        address user = address(0x123);
        address referrer = address(0xdeadbeef);
        
        // Verificar que las direcciones sean válidas y diferentes
        if (user == address(0) || referrer == address(0) || user == referrer) {
            return true;
        }

        // Verificar que el usuario no tenga ya un referido
        if (referrers[user] != address(0)) {
            return true;
        }

        setReferrer(user, referrer);
        return referrers[user] == referrer;
    }

    function echidna_test_invalid_referrer() public returns (bool) {
        address user = address(0x123);
        address referrer = address(0x123); // Intentar establecer el mismo usuario como referido

        (bool success,) = address(this).call(
            abi.encodeWithSignature("setReferrer(address,address)", user, referrer)
        );
        return !success;
    }

    function echidna_test_referrer_percentage() public returns (bool) {
        if (_msgSender() != owner()) return true;
        
        uint256 newPercentage = 10;
        setReferedPercentage(newPercentage);
        return referedPercentage == newPercentage;
    }

    function echidna_test_invalid_referrer_percentage() public returns (bool) {
        if (_msgSender() != owner()) return true;
        
        (bool success,) = address(this).call(
            abi.encodeWithSignature("setReferedPercentage(uint256)", 101)
        );
        return !success;
    }

    function echidna_test_token_price_update() public returns (bool) {
        if (_msgSender() != owner()) return true;
        
        uint256 newPrice = 200000000; // 2 USD
        setTokenPriceInUSD(newPrice);
        return tokenPriceInUSD == newPrice;
    }

    function echidna_test_matic_price_feed() public view returns (bool) {
        uint256 price = getLatestMaticPrice();
        return price > 0;
    }

    function echidna_test_buy_tokens_with_referrer() public payable returns (bool) {
        if (msg.value == 0) return true;
        
        address referrer = address(0x789);
        if (referrer == _msgSender()) return true;

        setReferrer(_msgSender(), referrer);
        
        (bool success,) = address(this).call{value: msg.value}(
            abi.encodeWithSignature("buyTokens(address)", referrer)
        );
        
        return success;
    }

    function echidna_test_buy_tokens_without_referrer() public payable returns (bool) {
        if (msg.value == 0) return true;
        
        (bool success,) = address(this).call{value: msg.value}(
            abi.encodeWithSignature("buyTokens(address)", address(0))
        );
        
        return success;
    }

    function echidna_test_ico_period_correct() public view returns (bool) {
        return startTime < endTime;
    }

    function echidna_test_max_tokens_per_user() public view returns (bool) {
        address investor = address(this);
        uint256 maxPerUser = maxTokensPerUser;
        uint256 tokensBought = icoPublicUserBalances[investor];

        return tokensBought <= maxPerUser;
    }

    function echidna_test_total_tokens_sold_does_not_exceed_max() public view returns (bool) {
        return soldTokens <= maxTokens;
    }

    function echidna_test_no_purchase_with_zero_eth() public returns (bool) {
        try this.buyTokens(address(0)) {
            return false; // Si la compra fue exitosa con 0 ETH, la prueba falla
        } catch {
            return true; // Si la compra falla con 0 ETH, la prueba pasa
        }
    }

    function echidna_test_claim_tokens() public view returns (bool) {
        if(_msgSender() != owner() || _msgSender() != address(this)){
            return true;
        }
        if (!vestingEnabled) return true;

        VestingSchedule.VestingData memory vesting = VestingSchedule.VestingData({
            totalAmount: 1000,
            claimedAmount: 0,
            startTime: block.timestamp - (180 days),
            cliffInMonths: 3,
            durationInMonths: 12
        });

        VestingSchedule.VestingInterval[] memory vestingIntervals;
        vestingIntervals[0] = VestingSchedule.VestingInterval({endMonth: 6, unlockPerMonth: 10});
        vestingIntervals[1] = VestingSchedule.VestingInterval({endMonth: 12, unlockPerMonth: 20});

        uint256 releasableTokens = getReleasableTokens(_msgSender());
        uint256 claimedTokens = vesting.claimedAmount + releasableTokens;

        return claimedTokens <= vesting.totalAmount;
    }

    function echidna_test_whitelist_restriction() public returns (bool) {
        if (whitelistEnabled) {
            if (_msgSender() != owner()){
                return true;
            }

            setWhitelist(_msgSender(), true);
            return whitelist[_msgSender()];
        }
        return true;
    }

    function echidna_test_add_remove_whitelist() public returns (bool) {
        if (_msgSender() != owner()){
            return true;
        }
        bool wasWhitelisted = whitelist[_msgSender()];

        setWhitelist(_msgSender(), !wasWhitelisted);
        return whitelist[_msgSender()] != wasWhitelisted;
    }

    function echidna_test_vesting_configuration() public returns (bool) {
        if(_msgSender() != owner() || _msgSender() != address(this)) return true;
        if(!vestingEnabled) return true;

        VestingSchedule.VestingInterval[] memory intervals;
        intervals[0] = VestingSchedule.VestingInterval({ endMonth: 6, unlockPerMonth: 7000 });
        intervals[1] = VestingSchedule.VestingInterval({ endMonth: 7, unlockPerMonth: 8000 });
        intervals[2] = VestingSchedule.VestingInterval({ endMonth: 12, unlockPerMonth: 10000 });

        setVestingConfiguration(12, intervals);
        return unlockVestingIntervals.length > 0 && vestingDurationInMonths == intervals[intervals.length-1].endMonth;
    }

    function echidna_test_whitelist_toggle() public returns (bool) {
        if(_msgSender() != owner()) return true;
        bool wasWhitelisted = whitelist[_msgSender()];
        setWhitelist(_msgSender(), !wasWhitelisted);
        return whitelist[_msgSender()] != wasWhitelisted;
    }

    function echidna_test_whitelist_batch() public returns (bool) {
        if(_msgSender() != owner() || _msgSender() != address(this)){
            return true;
        }
        if(!whitelistEnabled) return true;
        address[] memory accounts;
        accounts[0] = address(0x123);
        accounts[1] = address(0x456);
        
        setWhitelistBatch(accounts, true);
        return whitelist[accounts[0]] && whitelist[accounts[1]];
    }

    function echidna_test_set_timelock() public returns (bool) {
        if(_msgSender() != owner()) return true;
        setTimelockDurationInMinutes(5);
        return timelockDuration == 5 * 60;
    }

    function echidna_test_set_max_tokens() public returns (bool) {
        if(_msgSender() != owner()) return true;
        uint256 newMax = maxTokens + 10**18;
        setMaxTokens(newMax);
        return maxTokens != newMax;
    }

    function echidna_test_set_max_tokens_per_user() public returns (bool) {
        if(_msgSender() != owner()) return true;
        uint256 newMax = maxTokensPerUser + 10**18;
        setMaxTokensPerUser(newMax);
        return maxTokensPerUser != newMax;
    }

    function echidna_test_set_cliff_duration() public returns (bool) {
        if (owner() != _msgSender()) return true;
        setCliffDuration(5);
        return cliffDurationInMonths == 5;
    }

    function echidna_test_whitelist_enabled_toggle() public returns (bool) {
        if(_msgSender() != owner()) return true;
        bool oldStatus = whitelistEnabled;
        setWhitelistEnabled(!oldStatus);
        return whitelistEnabled != oldStatus;
    }

    function echidna_test_vesting_enabled_toggle() public returns (bool) {
        if(_msgSender() != owner()) return true;
        bool oldStatus = vestingEnabled;
        setVestingEnabled(!oldStatus);
        return vestingEnabled != oldStatus;
    }

    function echidna_test_set_ico_period() public returns (bool) {
        if(_msgSender() != owner()) return true;
        uint256 newStartTime = block.timestamp + 10;
        uint256 newEndTime = newStartTime + 100;
        setICOPeriod(newStartTime, newEndTime);
        return startTime == newStartTime && endTime == newEndTime;
    }

    function echidna_test_set_minimum_purchase() public returns (bool) {
        if(_msgSender() != owner()) return true;
        setMinimumPurchaseAmount(1 ether);
        return minPurchaseAmount == 1 ether;
    }
}