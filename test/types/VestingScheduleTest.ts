export interface VestingData {
    totalAmount: bigint;
    claimedAmount: bigint;
    startTime: bigint;
    cliffInMonths: bigint;
    durationInMonths: bigint;
}

export interface VestingInterval {
    endMonth: bigint;
    unlockPerMonth: number;
}

export interface VestingScheduleTest {
    testCreateVesting(totalAmount: bigint, cliff: bigint, duration: bigint): Promise<any>;
    testCalculateReleasable(): Promise<bigint>;
    getLastVestingData(): Promise<VestingData>;
    setVestingIntervals(intervals: VestingInterval[]): Promise<any>;
} 