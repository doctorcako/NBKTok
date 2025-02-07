// SPDX-License-Identifier: MIT
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

    /// ----------------- ERRORS -----------------
    error InvalidCliffTime(uint256 cliff, uint256 duration); // Error for invalid cliff time
    error InvalidVestingPeriod(uint256 duration); // Error for invalid vesting period

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
        uint256 totalUnlockedTokens = (vesting.totalAmount * totalUnlockedPercentage) / 100;
        return totalUnlockedTokens > vesting.claimedAmount ? totalUnlockedTokens - vesting.claimedAmount : 0;
    }
}
