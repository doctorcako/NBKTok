// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library VestingSchedule {

    struct VestingData {
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 startTime;
        uint256 cliffInMonths;
        uint256 durationInMonths;
    }

    struct VestingInterval {
        uint256 endMonth; // Mes final del intervalo
        uint256 unlockPerMonth; // Porcentaje desbloqueado por mes en este intervalo
    }

    error InvalidTotalAmount(uint256 amount);
    error InvalidCliffTime(uint256 cliff, uint256 duration);
    error InvalidVestingPeriod(uint256 duration);

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

        // Iterar sobre los intervalos para calcular el porcentaje desbloqueado
        for (uint256 i = 0; i < vestingIntervals.length; i++) {
            VestingInterval memory interval = vestingIntervals[i];

            if (elapsedMonths >= interval.endMonth) {
                // Si el intervalo completo ha pasado, desbloquear todo el porcentaje del intervalo
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

        // Retornar tokens desbloqueados menos los tokens ya reclamados
        return totalUnlockedTokens > vesting.claimedAmount ? totalUnlockedTokens - vesting.claimedAmount : 0;
    }
}
