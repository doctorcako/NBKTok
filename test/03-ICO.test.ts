import { expect } from "chai";
import { ethers } from "hardhat";
import { TestLogger } from "./helpers/TestLogger";
import { IcoNBKToken, NBKToken, TokenDistributor } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("ICO", () => {
    let ico: IcoNBKToken;
    let token: NBKToken;
    let distributor: TokenDistributor;
    let owner: SignerWithAddress;
    let addr1: SignerWithAddress;
    let addr2: SignerWithAddress;
    let addr3: SignerWithAddress;
    let addrs: SignerWithAddress[];

    // Constantes para la configuración
    const SECONDS_ICO_WILL_START = 1;
    const ICO_DURATION_IN_DAYS = 30;
    const RATE = BigInt(1000); // 1 ETH = 1000 tokens
    const MAX_TOKENS = BigInt(2500000000) // 2,5M tokens
    const MAX_TOKENS_PER_USER = BigInt(10000) // 10k tokens
    const TIMELOCK_DURATION_IN_HOURS = BigInt(24); // 1 día
    const VESTING_DURATION_IN_MONTHS = BigInt(12);
    const CLIFF_DURATION_IN_MONTHS = BigInt(3);
    const VESTING_ENABLED = false;
    const WHITELIST_ENABLED = false;

    const TIMELOCK_DURATION = TIMELOCK_DURATION_IN_HOURS * BigInt(60) * BigInt(60);
    const PURCHASE_AMOUNT = ethers.parseEther("1"); // 1 ETH
    const ZERO_ADDRESS = ethers.ZeroAddress;

    async function deployICOFixture() {
        const [owner, addr1, addr2, addr3, addr4, ...addrs] = await ethers.getSigners();

        // Deploy NBKToken
        const NBKToken = await ethers.getContractFactory("NBKToken");
        const nbkToken = await NBKToken.deploy("NeuroBlock", "NBK", owner.address);

        // Deploy TokenDistributor with owner
        const TokenDistributor = await ethers.getContractFactory("TokenDistributor");
        const tokenDistributor = await TokenDistributor.deploy(
            await nbkToken.getAddress(),
            owner.address,
            ethers.parseEther("10")
        );

        
        // Deploy ICO with owner
        const ICO = await ethers.getContractFactory("IcoNBKToken");
        const ico = await ICO.deploy(
            await tokenDistributor.getAddress(),
            owner.address,
            SECONDS_ICO_WILL_START,
            ICO_DURATION_IN_DAYS,
            RATE,
            MAX_TOKENS,
            MAX_TOKENS_PER_USER,
            TIMELOCK_DURATION_IN_HOURS,
            VESTING_DURATION_IN_MONTHS,
            CLIFF_DURATION_IN_MONTHS,
            VESTING_ENABLED,
            WHITELIST_ENABLED
        );

        return { nbkToken, tokenDistributor, ico, owner, addr1, addr2, addrs };
    }

    async function setupICOParameters(ico: IcoNBKToken, token: NBKToken, distributor: TokenDistributor) {
        const blockNumber = await ethers.provider.getBlockNumber();
        const block = await ethers.provider.getBlock(blockNumber);
        const currentTimestamp = block!.timestamp;
        
        const startTime = currentTimestamp + 3600; // 1 hora desde ahora
        const endTime = startTime + 90 * 24 * 60 * 60; // 30 días de duración
        await ico.setICOPeriod(startTime, endTime);

        // Mint tokens al distributor
        await token.mint(await distributor.getAddress(), ethers.parseEther("2500000000"));
        
        // Asignar permisos del distributor al ICO
        await distributor.setAllowedInteractors(await ico.getAddress());

        return { startTime, endTime };
    }

    beforeEach(async () => {
        [owner, addr1, addr2, addr3, ...addrs] = await ethers.getSigners();
        
        const deployment = await deployICOFixture();
        token = deployment.nbkToken;
        distributor = deployment.tokenDistributor;
        ico = deployment.ico;

        await setupICOParameters(ico, token, distributor);
    });

    describe("Deployment & Initial Setup", () => {
        it("Should configure initial parameters correctly", async () => {
            try {
                expect(await ico.getAddress()).to.not.equal(ZERO_ADDRESS);
                expect(await ico.owner()).to.equal(owner.address);
                expect(await ico.maxTokens()).to.equal(MAX_TOKENS * BigInt(1e18));
                expect(await ico.maxTokensPerUser()).to.equal(MAX_TOKENS_PER_USER * BigInt(1e18));
                expect(await ico.rate()).to.equal(RATE);
                expect(await ico.timelockDuration()).to.equal(TIMELOCK_DURATION);
                expect(await ico.whitelistEnabled()).to.equal(false);
                expect(await ico.vestingEnabled()).to.equal(false);
                expect(await ico.soldTokens()).to.equal(0);
                expect(distributor.setAllowedInteractors(await ico.getAddress()))
                .to.be.revertedWithCustomError(distributor, "InteractorAlreadyAllowed");

                TestLogger.logTestResult("ICO", "Deployment & Initial Setup", 
                    "Should configure initial parameters correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Deployment & Initial Setup", 
                    "Should configure initial parameters correctly", "failed", 0, error);
                throw error;
            }
        });

        it("Should have correct permissions set", async () => {
            try {
                // Verificar que el ICO es el owner del distributor
                expect(await distributor.checkAllowed(await ico.getAddress())).to.equal(true);
                
                TestLogger.logTestResult("ICO", "Deployment & Initial Setup", 
                    "Should have correct permissions set", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Deployment & Initial Setup", 
                    "Should have correct permissions set", "failed", 0, error);
                throw error;
            }
        });

        it("Should control vesting settings are ok", async () => {
            try {
                // Verificar que el ICO es el owner del distributor
                await ico.setVestingEnabled(true)
                await time.increase(3605)
                await expect(ico.connect(addr1).buyTokens({ value: ethers.parseEther("0.01") }))
                    .to.be.revertedWithCustomError(ico, "UnlockVestingIntervalsNotDefined")
                TestLogger.logTestResult("ICO", "Deployment & Initial Setup", 
                    "Should have correct permissions set", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Deployment & Initial Setup", 
                    "Should have correct permissions set", "failed", 0, error);
                throw error;
            }
        });

    });

    describe("Configuration Management", () => {
        describe("Rate Management", () => {
            it("Should update rate correctly", async () => {
                try {
                    const newRate = BigInt(200);
                    const oldRate = await ico.rate();
                    
                    await expect(ico.setRate(newRate))
                        .to.emit(ico, "RateUpdated")
                        .withArgs(oldRate, newRate);
                    
                    expect(await ico.rate()).to.equal(newRate);

                    TestLogger.logTestResult("ICO", "Rate Management", 
                        "Should update rate correctly", "passed", 0);
                } catch (error) {
                    TestLogger.logTestResult("ICO", "Rate Management", 
                        "Should update rate correctly", "failed", 0, error);
                    throw error;
                }
            });

            it("Should revert with invalid rate", async () => {
                try {
                    await expect(ico.setRate(0))
                        .to.be.revertedWithCustomError(ico, "InvalidRateValue")
                        .withArgs(0);

                    TestLogger.logTestResult("ICO", "Rate Management", 
                        "Should revert with invalid rate", "passed", 0);
                } catch (error) {
                    TestLogger.logTestResult("ICO", "Rate Management", 
                        "Should revert with invalid rate", "failed", 0, error);
                    throw error;
                }
            });

            it("Should only allow owner to update rate", async () => {
                try {
                    await expect(ico.connect(addr1).setRate(200))
                        .to.be.revertedWithCustomError(ico, "OwnableUnauthorizedAccount");

                    TestLogger.logTestResult("ICO", "Rate Management", 
                        "Should only allow owner to update rate", "passed", 0);
                } catch (error) {
                    TestLogger.logTestResult("ICO", "Rate Management", 
                        "Should only allow owner to update rate", "failed", 0, error);
                    throw error;
                }
            });
        });

        describe("Whitelist Management", () => {
            it("Should add and remove addresses from whitelist", async () => {
                try {
                    await ico.setWhitelistEnabled(true);
                    
                    await expect(ico.setWhitelist(addr1.address, true))
                        .to.emit(ico, "WhitelistUpdated")
                        .withArgs(addr1.address, true);

                    expect(await ico.whitelist(addr1.address)).to.be.true;

                    await expect(ico.setWhitelist(addr1.address, false))
                        .to.emit(ico, "WhitelistUpdated")
                        .withArgs(addr1.address, false);

                    expect(await ico.whitelist(addr1.address)).to.be.false;

                    TestLogger.logTestResult("ICO", "Whitelist Management", 
                        "Should add and remove addresses from whitelist", "passed", 0);
                } catch (error) {
                    TestLogger.logTestResult("ICO", "Whitelist Management", 
                        "Should add and remove addresses from whitelist", "failed", 0, error);
                    throw error;
                }
            });

            it("Should handle batch whitelist updates", async () => {
                try {
                    const addresses = [addr1.address, addr2.address, addr3.address];
                    
                    await expect(ico.setWhitelistBatch(addresses, true))
                        .to.emit(ico, "BatchWhitelistUpdated")
                        .withArgs(addresses.length, true);

                    for (const addr of addresses) {
                        expect(await ico.whitelist(addr)).to.be.true;
                    }

                    TestLogger.logTestResult("ICO", "Whitelist Management", 
                        "Should handle batch whitelist updates", "passed", 0);
                } catch (error) {
                    TestLogger.logTestResult("ICO", "Whitelist Management", 
                        "Should handle batch whitelist updates", "failed", 0, error);
                    throw error;
                }
            });

            it("Should revert batch update with empty array", async () => {
                try {
                    await expect(ico.setWhitelistBatch([], true))
                        .to.be.revertedWithCustomError(ico, "InvalidWhitelistArrayInput");

                    TestLogger.logTestResult("ICO", "Whitelist Management", 
                        "Should revert batch update with empty array", "passed", 0);
                } catch (error) {
                    TestLogger.logTestResult("ICO", "Whitelist Management", 
                        "Should revert batch update with empty array", "failed", 0, error);
                    throw error;
                }
            });
        });

        describe("Vesting Configuration", () => {
            it("Should set vesting intervals correctly", async () => {
                try {
                    const intervals = [
                        { endMonth: BigInt(6), unlockPerMonth: 7 },
                        { endMonth: BigInt(7), unlockPerMonth: 8 },
                        { endMonth: BigInt(12), unlockPerMonth: 10 }
                    ];
                    await expect(ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,intervals))
                        .to.emit(ico, "VestingConfigurationUpdated")
                        .withArgs(VESTING_DURATION_IN_MONTHS, intervals.length);

                    TestLogger.logTestResult("ICO", "Vesting Configuration", 
                        "Should set vesting intervals correctly", "passed", 0);
                } catch (error) {
                    TestLogger.logTestResult("ICO", "Vesting Configuration", 
                        "Should set vesting intervals correctly", "failed", 0, error);
                    throw error;
                }
            });

            it("Should revert with invalid vesting intervals", async () => {
                try {
                    const invalidIntervals = [
                        { endMonth: BigInt(6), unlockPerMonth: 10 },
                        { endMonth: BigInt(4), unlockPerMonth: 5 },
                        { endMonth: BigInt(12), unlockPerMonth: 5 }   // Mes final menor que el anterior
                    ];

                    await expect(ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,invalidIntervals))
                        .to.be.revertedWithCustomError(ico, "InvalidVestingIntervalSequence")
                        .withArgs(1);

                    const intervals = [
                        { endMonth: BigInt(6), unlockPerMonth: 7 },
                        { endMonth: BigInt(7), unlockPerMonth: 8 },
                        { endMonth: BigInt(13), unlockPerMonth: 10 }
                    ];

                    await expect(ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,intervals))
                        .to.be.revertedWithCustomError(ico, "InvalidVestingIntervals")

                    TestLogger.logTestResult("ICO", "Vesting Configuration", 
                        "Should revert with invalid vesting intervals", "passed", 0);
                } catch (error) {
                    TestLogger.logTestResult("ICO", "Vesting Configuration", 
                        "Should revert with invalid vesting intervals", "failed", 0, error);
                    throw error;
                }
            });

            it("Should revert when total percentage is not 100", async () => {
                try {
                    const invalidIntervals = [
                        { endMonth: BigInt(6), unlockPerMonth: 10 },  // 60%
                        { endMonth: BigInt(12), unlockPerMonth: 2 }   // 12% más = 72% total
                    ];

                    await expect(ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,invalidIntervals))
                        .to.be.revertedWithCustomError(ico, "TotalPercentageIntervalsNotEqualTo100")
                        .withArgs(72);

                    TestLogger.logTestResult("ICO", "Vesting Configuration", 
                        "Should revert when total percentage is not 100", "passed", 0);
                } catch (error) {
                    TestLogger.logTestResult("ICO", "Vesting Configuration", 
                        "Should revert when total percentage is not 100", "failed", 0, error);
                    throw error;
                }
            });
        });
    });

    describe("Token Purchase", () => {
        beforeEach(async () => {
            await ico.setWhitelistEnabled(true);
            await ico.setWhitelist(addr1.address, true);
            
            // Avanzar al período activo
            const startTime = await ico.startTime();
            await time.increaseTo(Number(startTime));
        });

        it("Should allow whitelisted purchase during active period", async () => {
            try {
                const ethAmount = PURCHASE_AMOUNT;
                const expectedTokens = ethAmount * RATE;
                
                await expect(ico.connect(addr1).buyTokens({ value: ethAmount }))
                    .to.emit(ico, "SoldTokensUpdated")
                    .withArgs(0, expectedTokens);

                expect(await token.balanceOf(addr1.address)).to.equal(expectedTokens);
                expect(await ico.soldTokens()).to.equal(expectedTokens);

                TestLogger.logTestResult("ICO", "Token Purchase", 
                    "Should allow whitelisted purchase during active period", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Token Purchase", 
                    "Should allow whitelisted purchase during active period", "failed", 0, error);
                throw error;
            }
        });

        it("Should revert vesting duration equal 0", async () => {
            try {
                // Verificar que el ICO es el owner del distributor
                await ico.setVestingEnabled(true)
                await time.increase(3601)
                await ico.setCliffDuration(100)
                const intervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 7 },
                    { endMonth: BigInt(7), unlockPerMonth: 8 },
                    { endMonth: BigInt(12), unlockPerMonth: 10 }
                ];
                await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,intervals);
                await expect(ico.connect(addr1).buyTokens({ value: ethers.parseEther("1") }))
                    .to.be.revertedWithCustomError(ico, "InvalidCliffTime")
                TestLogger.logTestResult("ICO", "Deployment & Initial Setup", 
                    "Should have correct permissions set", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Deployment & Initial Setup", 
                    "Should have correct permissions set", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle vesting purchase correctly", async () => {
            try {
                await ico.setVestingEnabled(true);
                expect(await ico.connect(addr1).currentPhaseInterval()).to.be.equal(0)
                const intervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 7 },
                    { endMonth: BigInt(7), unlockPerMonth: 8 },
                    { endMonth: BigInt(12), unlockPerMonth: 10 }
                ];
                await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,intervals);

                const ethAmount = PURCHASE_AMOUNT;
                const expectedTokens = ethAmount * RATE;
                expect(await ico.connect(addr1).currentPhaseInterval()).to.be.equal(1)
                await expect(ico.connect(addr1).buyTokens({ value: ethAmount }))
                    .to.emit(ico, "VestingAssigned")
                    .withArgs(addr1.address, expectedTokens, 1);

                const vesting = await ico.vestings(addr1.address);
                expect(vesting.totalAmount).to.equal(expectedTokens);
                expect(vesting.claimedAmount).to.equal(0);

                TestLogger.logTestResult("ICO", "Token Purchase", 
                    "Should handle vesting purchase correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Token Purchase", 
                    "Should handle vesting purchase correctly", "failed", 0, error);
                throw error;
            }
        });

        it("Should enforce timelock between purchases", async () => {
            try {
                // Primera compra
                await ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT });

                // Intentar comprar inmediatamente después
                await expect(ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT }))
                    .to.be.revertedWithCustomError(ico, "TimeLockNotPassed");

                // Avanzar más allá del timelock
                await time.increase(Number(TIMELOCK_DURATION) + 1);

                // Ahora debería permitir la compra
                await expect(ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT }))
                    .to.not.be.reverted;

                TestLogger.logTestResult("ICO", "Token Purchase", 
                    "Should enforce timelock between purchases", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Token Purchase", 
                    "Should enforce timelock between purchases", "failed", 0, error);
                throw error;
            }
        });
        it("Should enforce max tokens per user", async () => {
            try {
                // Intentar comprar más que el máximo permitido
                await ico.connect(owner).setWhitelistEnabled(false)
                await expect(ico.connect(addr3).buyTokens({ value: ethers.parseEther("4") }))
                    .to.emit(ico, "SoldTokensUpdated");
                await time.increase(Number(TIMELOCK_DURATION));

                await expect(ico.connect(addr3).buyTokens({ value: ethers.parseEther("5") }))
                    .to.emit(ico, "SoldTokensUpdated");
                
                await time.increase(Number(TIMELOCK_DURATION));
                await expect(ico.connect(addr3).buyTokens({ value: ethers.parseEther("7") }))
                    .to.be.revertedWithCustomError(ico, "TotalAmountPurchaseExceeded");
                TestLogger.logTestResult("ICO", "Token Purchase", 
                    "Should enforce max tokens per user", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Token Purchase", 
                    "Should enforce max tokens per user", "failed", 0, error);
                throw error;
            }
        });

        it("Should revert purchase from non-whitelisted address", async () => {
            try {
                await expect(ico.connect(addr2).buyTokens({ value: PURCHASE_AMOUNT }))
                    .to.be.revertedWithCustomError(ico, "AddressNotInWhitelist")
                    .withArgs(addr2.address);

                TestLogger.logTestResult("ICO", "Token Purchase", 
                    "Should revert purchase from non-whitelisted address", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Token Purchase", 
                    "Should revert purchase from non-whitelisted address", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Token Claiming", () => {
        beforeEach(async () => {
            await ico.setVestingEnabled(true);
            await ico.setWhitelistEnabled(true);
            await ico.setWhitelist(addr1.address, true);

            
            const intervals = [
                { endMonth: BigInt(6), unlockPerMonth: 7 },
                { endMonth: BigInt(7), unlockPerMonth: 8 },
                { endMonth: BigInt(12), unlockPerMonth: 10 }
            ];
            await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,intervals);

            // Avanzar al período activo
            const startTime = await ico.startTime();
            await time.increaseTo(Number(startTime));

            // Realizar compra
            await ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT });
        });

        it("Should allow claiming vested tokens after cliff", async () => {
            try {
                // Avanzar 3 meses (dentro del cliff)
                await time.increase(90 * 24 * 60 * 60);
                
                await expect(ico.connect(addr1).claimTokens())
                    .to.be.revertedWithCustomError(ico, "NoReleasableTokens");

                await time.increase(30 * 24 * 60 * 60);
                await ico.connect(addr1).claimTokens();
                const expectedTokens1 = PURCHASE_AMOUNT * RATE * BigInt(7) / BigInt(100);
                expect(await token.balanceOf(addr1.address)).to.equal(expectedTokens1);
                // Avanzar 6 meses más
                await time.increase(180 * 24 * 60 * 60);

                await ico.connect(addr1).claimTokens();
                const expectedTokens = PURCHASE_AMOUNT * RATE * BigInt(50) / BigInt(100);
                expect(await token.balanceOf(addr1.address)).to.equal(expectedTokens);

                TestLogger.logTestResult("ICO", "Token Claiming", 
                    "Should allow claiming vested tokens after cliff", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Token Claiming", 
                    "Should allow claiming vested tokens after cliff", "failed", 0, error);
                throw error;
            }
        });

        it("Should track claimed amounts correctly", async () => {
            try {
                // Avanzar 8 meses (3 meses cliff y 5 de vesting) 
                await time.increase(240 * 24 * 60 * 60);

                await ico.connect(addr1).claimTokens();
                const vesting = await ico.vestings(addr1.address);
                const expectedClaimed = PURCHASE_AMOUNT * RATE * BigInt(35) / BigInt(100);
                expect(vesting.claimedAmount).to.equal(expectedClaimed);

                TestLogger.logTestResult("ICO", "Token Claiming", 
                    "Should track claimed amounts correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Token Claiming", 
                    "Should track claimed amounts correctly", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Emergency Controls", () => {
        it("Should pause and unpause the ICO correctly", async () => {
            try {
                await ico.pause();
                expect(await ico.paused()).to.be.true;

                // Try to buy tokens while paused
                await expect(ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT }))
                    .to.be.revertedWithCustomError(ico,"EnforcedPause");

                await ico.unpause();
                expect(await ico.paused()).to.be.false;

                TestLogger.logTestResult("ICO", "Emergency Controls", 
                    "Should pause and unpause the ICO correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Emergency Controls", 
                    "Should pause and unpause the ICO correctly", "failed", 0, error);
                throw error;
            }
        });

        it("Should only allow owner to pause/unpause", async () => {
            try {
                await expect(ico.connect(addr1).pause())
                    .to.be.revertedWithCustomError(ico, "OwnableUnauthorizedAccount");
                await expect(ico.connect(addr1).unpause())
                    .to.be.revertedWithCustomError(ico, "OwnableUnauthorizedAccount");

                TestLogger.logTestResult("ICO", "Emergency Controls", 
                    "Should only allow owner to pause/unpause", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Emergency Controls", 
                    "Should only allow owner to pause/unpause", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("ETH Handling", () => {
        it("Should handle ETH transfers correctly", async () => {
            try {
                const initialBalance = await ethers.provider.getBalance(await distributor.getAddress());
                await time.increase(3600);
                await ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT });
                const finalBalance = await ethers.provider.getBalance(await distributor.getAddress());
                
                expect(finalBalance - initialBalance).to.equal(PURCHASE_AMOUNT);

                TestLogger.logTestResult("ICO", "ETH Handling", 
                    "Should handle ETH transfers correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "ETH Handling", 
                    "Should handle ETH transfers correctly", "failed", 0, error);
                throw error;
            }
        });

        it("Should revert on zero ETH sent", async () => {
            try {
                await time.increase(3600)
                await expect(ico.connect(addr1).buyTokens({ value: 0 }))
                    .to.be.revertedWithCustomError(ico, "NoMsgValueSent")
                    .withArgs(0);

                TestLogger.logTestResult("ICO", "ETH Handling", 
                    "Should revert on zero ETH sent", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "ETH Handling", 
                    "Should revert on zero ETH sent", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Vesting Schedule Edge Cases", () => {
        beforeEach(async () => {
            await ico.setVestingEnabled(true);
            await ico.setWhitelistEnabled(true);
            await ico.setWhitelist(addr1.address, true);
        });

        it("Should handle multiple vesting intervals correctly", async () => {
            try {
                const intervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 7 },
                    { endMonth: BigInt(7), unlockPerMonth: 8 },
                    { endMonth: BigInt(12), unlockPerMonth: 10 }
                ];

                await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,intervals);
                await time.increase(3600);
                // Buy tokens
                await ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT });
                
                // Advance 3 months de cliff y 3 de vesting
                await time.increase(180 * 24 * 60 * 60);
                await ico.connect(addr1).claimTokens();
                
                const expectedTokens = PURCHASE_AMOUNT * RATE * BigInt(21) / BigInt(100);
                expect(await token.balanceOf(addr1.address)).to.equal(expectedTokens);

                TestLogger.logTestResult("ICO", "Vesting Schedule Edge Cases", 
                    "Should handle multiple vesting intervals correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Vesting Schedule Edge Cases", 
                    "Should handle multiple vesting intervals correctly", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle vesting schedule updates correctly", async () => {
            try {
                const initialIntervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 7 },
                    { endMonth: BigInt(7), unlockPerMonth: 8 },
                    { endMonth: BigInt(12), unlockPerMonth: 10 }
                ];
                await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,initialIntervals);
                
                // Buy tokens
                await time.increase(3600);
                await ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT });
                
                // Update vesting schedule
                const newIntervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 10 },
                    { endMonth: BigInt(10), unlockPerMonth: 5 },
                    { endMonth: BigInt(12), unlockPerMonth: 10 }
                ];
                await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,newIntervals);
                
                // Advance 3 months
                await time.increase(180 * 24 * 60 * 60);
                await ico.connect(addr1).claimTokens();
                
                const expectedTokens = PURCHASE_AMOUNT * RATE * BigInt(21) / BigInt(100);
                expect(await token.balanceOf(addr1.address)).to.equal(expectedTokens);

                TestLogger.logTestResult("ICO", "Vesting Schedule Edge Cases", 
                    "Should handle vesting schedule updates correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Vesting Schedule Edge Cases", 
                    "Should handle vesting schedule updates correctly", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Contract State Transitions", () => {
        it("Should handle ICO lifecycle correctly", async () => {
            try {
                // Before start
                await expect(ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT }))
                    .to.be.revertedWithCustomError(ico, "ICONotInActivePeriod");

                // Start ICO
                await time.increaseTo(Number(await ico.startTime()));
                await ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT });

                // End ICO
                await time.increaseTo(Number(await ico.endTime()));
                await expect(ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT }))
                    .to.be.revertedWithCustomError(ico, "ICONotInActivePeriod");

                TestLogger.logTestResult("ICO", "Contract State Transitions", 
                    "Should handle ICO lifecycle correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Contract State Transitions", 
                    "Should handle ICO lifecycle correctly", "failed", 0, error);
                throw error;
            }
        });

        it("Should track token distribution limits correctly", async () => {
            try {
                await ico.setWhitelistEnabled(true);
                await ico.setWhitelist(addr1.address, true);
                
                const maxPurchase = ethers.parseEther("11")
                await time.increase(3600);

                // Try to buy more than max per user
                await expect(ico.connect(addr1).buyTokens({ value: maxPurchase + BigInt(1) }))
                    .to.be.revertedWithCustomError(ico, "TotalAmountPurchaseExceeded");
                
                const maxPurchaseLimit = ethers.parseEther("10")

                // Buy maximum allowed
                await ico.connect(addr1).buyTokens({ value: maxPurchaseLimit });
                expect(await ico.soldTokens()).to.equal(MAX_TOKENS_PER_USER*BigInt(1e18));

                TestLogger.logTestResult("ICO", "Contract State Transitions", 
                    "Should track token distribution limits correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Contract State Transitions", 
                    "Should track token distribution limits correctly", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Edge Cases and Boundary Testing", () => {
        it("Should handle minimum purchase amounts correctly", async () => {
            try {
                await expect(ico.connect(owner).setMinimumPurchaseAmount(ethers.parseEther("0"))).to.be.revertedWithCustomError(ico,"InvalidMinPurchaseAmount")
                await expect(await ico.connect(owner).setMinimumPurchaseAmount(ethers.parseEther("1"))).to.emit(ico,"MinAmountPurchaseUpdated")
                const minPurchase = ethers.parseEther("0.0003");
                await time.increase(3600);
                await expect(ico.connect(addr1).buyTokens({ value: minPurchase }))
                    .to.be.revertedWithCustomError(ico, "InsufficientETHForTokenPurchase");

                TestLogger.logTestResult("ICO", "Edge Cases and Boundary Testing", 
                    "Should handle minimum purchase amounts correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Edge Cases and Boundary Testing", 
                    "Should handle minimum purchase amounts correctly", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle maximum token supply correctly", async () => {
            try {
                await ico.setMaxTokens(BigInt(1000)); // Set small max for testing
                await ico.setMaxTokensPerUser(BigInt(1000));
                
                // Buy all available tokens
                const maxPurchase = ethers.parseEther("1")
                await time.increase(3600)
                await ico.connect(addr1).buyTokens({ value: maxPurchase });
                
                // Try to buy more
                await expect(ico.connect(addr2).buyTokens({ value: ethers.parseEther("1") }))
                    .to.be.revertedWithCustomError(ico, "NoTokensAvailable");

                TestLogger.logTestResult("ICO", "Edge Cases and Boundary Testing", 
                    "Should handle maximum token supply correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Edge Cases and Boundary Testing", 
                    "Should handle maximum token supply correctly", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle timelock between purchases correctly", async () => {
            try {
                // First purchase
                await time.increase(3600);
                await ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT });
                
                // Try to purchase immediately
                await expect(ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT }))
                    .to.be.revertedWithCustomError(ico, "TimeLockNotPassed");
                
                // Wait just under timelock duration
                await time.increase(Number(TIMELOCK_DURATION) - 60);
                await expect(ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT }))
                    .to.be.revertedWithCustomError(ico, "TimeLockNotPassed");
                
                // Wait remaining time
                await time.increase(61);
                await expect(await ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT }))
                    .to.emit(ico,"SoldTokensUpdated")

                TestLogger.logTestResult("ICO", "Edge Cases and Boundary Testing", 
                    "Should handle timelock between purchases correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Edge Cases and Boundary Testing", 
                    "Should handle timelock between purchases correctly", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Configuration Validation", () => {
        it("Should validate vesting interval configurations", async () => {
            try {
                // Invalid total percentage
                const invalidIntervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 5 },
                    { endMonth: BigInt(12), unlockPerMonth: 10 }
                ];
                await expect(ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,invalidIntervals))
                    .to.be.revertedWithCustomError(ico, "TotalPercentageIntervalsNotEqualTo100")
                    .withArgs(90);

                // Invalid sequence
                const invalidSequence = [
                    { endMonth: BigInt(7), unlockPerMonth: 50 },
                    { endMonth: BigInt(6), unlockPerMonth: 50 },
                    { endMonth: BigInt(12), unlockPerMonth: 50 }
                ];
                await expect(ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,invalidSequence))
                    .to.be.revertedWithCustomError(ico, "InvalidVestingIntervalSequence")
                    .withArgs(1);

                const intervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 7 },
                    { endMonth: BigInt(7), unlockPerMonth: 8 },
                    { endMonth: BigInt(13), unlockPerMonth: 10 }
                ];

                await expect(ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,intervals))
                    .to.be.revertedWithCustomError(ico, "InvalidVestingIntervals")

                const invalidSequence2 = [
                    { endMonth: BigInt(6), unlockPerMonth: 10 },
                    { endMonth: BigInt(12), unlockPerMonth: 0 }
                ];
                await expect(ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,invalidSequence2))
                    .to.be.revertedWithCustomError(ico, "InvalidVestingIntervals");

                // Empty intervals
                await expect(ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,[]))
                    .to.be.revertedWithCustomError(ico, "InvalidVestingIntervals");

                TestLogger.logTestResult("ICO", "Configuration Validation", 
                    "Should validate vesting interval configurations", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Configuration Validation", 
                    "Should validate vesting interval configurations", "failed", 0, error);
                throw error;
            }
        });

        it("Should validate ICO timing parameters", async () => {
            try {
                const currentTime = (await ethers.provider.getBlock("latest"))!.timestamp;
                
                // Invalid start time (in the past)
                const validStartTime = currentTime + 3600;

                await expect(ico.setICOPeriod(currentTime - 1,validStartTime))
                    .to.be.revertedWithCustomError(ico, "InvalidICOPeriod")
                    .withArgs(currentTime - 1,validStartTime);

                // Invalid end time (before start time)
                await ico.setICOPeriod(validStartTime, validStartTime+3600);
                await expect(ico.setICOPeriod(validStartTime,validStartTime-100))
                    .to.be.revertedWithCustomError(ico, "InvalidICOPeriod")
                    .withArgs(validStartTime, validStartTime-100);
                
                const intervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 7 },
                    { endMonth: BigInt(7), unlockPerMonth: 10 },
                    { endMonth: BigInt(13), unlockPerMonth: 8 }
                ];
                await expect(ico.setVestingConfiguration(0,intervals))
                    .to.be.revertedWithCustomError(ico, "InvalidVestingDuration")
                    .withArgs(0);
                
                expect(await ico.setVestingConfiguration(13, intervals))
                .to.emit(ico,"VestingDurationUpdated");

                await expect(ico.setCliffDuration(0))
                    .to.be.revertedWithCustomError(ico, "InvalidCliff")
                    .withArgs(0);

                expect(await ico.setCliffDuration(3))
                .to.emit(ico,"CliffUpdated");

                await expect(ico.setTimelockDurationInMinutes(0))
                    .to.be.revertedWithCustomError(ico, "InvalidTimelockDuration")
                    .withArgs(0);

                console.log(await ico.vestingDurationInMonths())
                
                await expect(ico.setTimelockDurationInMinutes(BigInt(24) * BigInt(60)))
                    .to.be.revertedWithCustomError(ico, "TimelockDurationNotChanged")
                    .withArgs(BigInt(24) * BigInt(60) * BigInt(60));

                expect(await ico.setTimelockDurationInMinutes(60))
                .to.emit(ico,"TimelockDurationUpdated");

                await ico.getICOInfo()

                // expect(await ico.getICOInfo())
                // .to.equal([BigInt(validStartTime),BigInt(validStartTime+3600),BigInt(MAX_TOKENS),BigInt(MAX_TOKENS_PER_USER),0]);


                TestLogger.logTestResult("ICO", "Configuration Validation", 
                    "Should validate ICO timing parameters", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Configuration Validation", 
                    "Should validate ICO timing parameters", "failed", 0, error);
                throw error;
            }
        });

        it("Should validate token limits", async () => {
            try {
                // Invalid max tokens
                await expect(ico.setMaxTokens(0))
                    .to.be.revertedWithCustomError(ico, "InvalidMaxTokens")
                    .withArgs(0);

                // Invalid max tokens per user
                await expect(ico.setMaxTokensPerUser(0))
                    .to.be.revertedWithCustomError(ico, "InvalidMaxTokensPerUser")
                    .withArgs(0);

                // Max tokens per user greater than total max tokens
                await ico.setMaxTokens(BigInt(1000));
                await ico.setMaxTokensPerUser(BigInt(100));
                
                // This should work
                await ico.setMaxTokensPerUser(BigInt(1000));
                
                TestLogger.logTestResult("ICO", "Configuration Validation", 
                    "Should validate token limits", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Configuration Validation", 
                    "Should validate token limits", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Error Handling and Recovery", () => {
        it("Should handle failed token transfers gracefully", async () => {
            try {
                // Set up a scenario where token transfer might fail
                await time.increase(3601);
                expect(await ico.connect(addr2).buyTokens({ value: ethers.parseEther("5") }))
                    .to.be.revertedWithCustomError(ico, "NoTokensAvailable")
                
                expect(await ico.connect(addr1).buyTokens({ value: ethers.parseEther("10") }))
                    .to.be.revertedWithCustomError(ico, "NoTokensAvailable")
                TestLogger.logTestResult("ICO", "Error Handling and Recovery", 
                    "Should handle failed token transfers gracefully", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Error Handling and Recovery", 
                    "Should handle failed token transfers gracefully", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle whitelist operations correctly", async () => {
            try {
                // Invalid address
                await expect(ico.setWhitelist(ethers.ZeroAddress, true))
                    .to.be.revertedWithCustomError(ico, "InvalidAddress")
                    .withArgs(ethers.ZeroAddress);

                // Empty batch
                await expect(ico.setWhitelistBatch([], true))
                    .to.be.revertedWithCustomError(ico, "InvalidWhitelistArrayInput");

                // Batch with invalid address
                await expect(ico.setWhitelistBatch([addr1.address, ethers.ZeroAddress], true))
                    .to.be.revertedWithCustomError(ico, "InvalidAddress")
                    .withArgs(ethers.ZeroAddress);

                TestLogger.logTestResult("ICO", "Error Handling and Recovery", 
                    "Should handle whitelist operations correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Error Handling and Recovery", 
                    "Should handle whitelist operations correctly", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle vesting claims correctly", async () => {
            try {
                await ico.setVestingEnabled(true);
                
                // Try to claim without any vesting
                await expect(ico.connect(addr1).claimTokens())
                    .to.be.revertedWithCustomError(ico, "NoReleasableTokens")
                    .withArgs(addr1.address);

                // Set up vesting but try to claim before cliff
                const intervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 7 },
                    { endMonth: BigInt(7), unlockPerMonth: 8 },
                    { endMonth: BigInt(12), unlockPerMonth: 10 }
                ];
                await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,intervals);
                await time.increase(3600);
                await ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT });
                
                await expect(ico.connect(addr1).claimTokens())
                    .to.be.revertedWithCustomError(ico, "NoReleasableTokens")
                    .withArgs(addr1.address);

                TestLogger.logTestResult("ICO", "Error Handling and Recovery", 
                    "Should handle vesting claims correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Error Handling and Recovery", 
                    "Should handle vesting claims correctly", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle manual vesting assing correctly", async () => {
            try {
                
                await ico.setVestingEnabled(true);
                const intervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 7 },
                    { endMonth: BigInt(7), unlockPerMonth: 8 },
                    { endMonth: BigInt(12), unlockPerMonth: 10 }
                ];
                await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,intervals);

                await expect(await ico.connect(owner).assignVesting(addr1.address,5000,3,12))
                    .to.emit(ico, "VestingAssigned")
                    .withArgs(addr1.address,5000,1);
                
                await expect(await ico.connect(owner).assignVesting(addr1.address,3000,3,12))
                    .to.emit(ico, "VestingAssigned")
                    .withArgs(addr1.address,3000,1);                

                await ico.setVestingEnabled(false);

                expect(ico.connect(owner).assignVesting(addr1.address,MAX_TOKENS_PER_USER,3,12))
                    .to.be.revertedWithCustomError(ico,"VestingNotEnabledForManualAssignment")
                    .withArgs(addr1.address)


                TestLogger.logTestResult("ICO", "Error Handling and Recovery", 
                    "Should handle vesting claims correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Error Handling and Recovery", 
                    "Should handle vesting claims correctly", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Multi-User Scenarios", () => {
        beforeEach(async () => {
            await ico.setWhitelistEnabled(true);
            await ico.setWhitelistBatch([addr1.address, addr2.address, addr3.address], true);
        });

        it("Should handle multiple users buying tokens simultaneously", async () => {
            try {
                await time.increase(3600);
                const purchasePromises = [
                    ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT }),
                    ico.connect(addr2).buyTokens({ value: PURCHASE_AMOUNT }),
                    ico.connect(addr3).buyTokens({ value: PURCHASE_AMOUNT })
                ];

                await Promise.all(purchasePromises);

                const expectedTokens = PURCHASE_AMOUNT * RATE;
                expect(await token.balanceOf(addr1.address)).to.equal(expectedTokens);
                expect(await token.balanceOf(addr2.address)).to.equal(expectedTokens);
                expect(await token.balanceOf(addr3.address)).to.equal(expectedTokens);

                TestLogger.logTestResult("ICO", "Multi-User Scenarios", 
                    "Should handle multiple users buying tokens simultaneously", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Multi-User Scenarios", 
                    "Should handle multiple users buying tokens simultaneously", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle vesting claims from multiple users", async () => {
            try {
                await ico.setVestingEnabled(true);
                const intervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 7 },
                    { endMonth: BigInt(7), unlockPerMonth: 8 },
                    { endMonth: BigInt(12), unlockPerMonth: 10 }
                ];
                await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,intervals);
                await time.increase(3600);
                // Multiple users buy tokens
                await ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT });
                await ico.connect(addr2).buyTokens({ value: PURCHASE_AMOUNT * BigInt(2) });
                await ico.connect(addr3).buyTokens({ value: PURCHASE_AMOUNT * BigInt(3) });

                // Advance 3 months and 5 months
                await time.increase(240 * 24 * 60 * 61);

                // All users claim tokens
                await ico.connect(addr1).claimTokens();
                await ico.connect(addr2).claimTokens();
                await ico.connect(addr3).claimTokens();

                // Verify correct amounts claimed
                const expectedTokens1 = PURCHASE_AMOUNT * RATE * BigInt(35) / BigInt(100);
                const expectedTokens2 = expectedTokens1 * BigInt(2);
                const expectedTokens3 = expectedTokens1 * BigInt(3);

                expect(await token.balanceOf(addr1.address)).to.equal(expectedTokens1);
                expect(await token.balanceOf(addr2.address)).to.equal(expectedTokens2);
                expect(await token.balanceOf(addr3.address)).to.equal(expectedTokens3);

                TestLogger.logTestResult("ICO", "Multi-User Scenarios", 
                    "Should handle vesting claims from multiple users", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Multi-User Scenarios", 
                    "Should handle vesting claims from multiple users", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Complex Vesting Scenarios", () => {
        beforeEach(async () => {
            await ico.setVestingEnabled(true);
            await ico.setWhitelistEnabled(true);
            await ico.setWhitelist(addr1.address, true);
        });

        it("Should handle partial claims across multiple intervals", async () => {
            try {
                const intervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 7 },
                    { endMonth: BigInt(7), unlockPerMonth: 8 },
                    { endMonth: BigInt(12), unlockPerMonth: 10 }
                ];
                await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,intervals);
                await time.increase(3600);
                await ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT });

                // Claim after 3 months (cliff over) and 2 month
                await time.increase(150 * 24 * 60 * 60);
                await ico.connect(addr1).claimTokens();
                let expectedTokens = PURCHASE_AMOUNT * RATE * BigInt(14) / BigInt(100);
                expect(await token.balanceOf(addr1.address)).to.equal(expectedTokens);

                // Claim after 4 months
                await time.increase(90 * 24 * 60 * 60);

                await ico.connect(addr1).claimTokens();
                expectedTokens = PURCHASE_AMOUNT * RATE * BigInt(35) / BigInt(100);
                expect(await token.balanceOf(addr1.address)).to.equal(expectedTokens);

                // Claim after full period
                await time.increase(210 * 24 * 60 * 60);
                await ico.connect(addr1).claimTokens();
                expectedTokens = PURCHASE_AMOUNT * RATE ;
                expect(await token.balanceOf(addr1.address)).to.equal(expectedTokens);

                TestLogger.logTestResult("ICO", "Complex Vesting Scenarios", 
                    "Should handle partial claims across multiple intervals", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Complex Vesting Scenarios", 
                    "Should handle partial claims across multiple intervals", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle multiple purchases with different vesting schedules", async () => {
            try {
                // First purchase with initial schedule
                const initialIntervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 7 },
                    { endMonth: BigInt(7), unlockPerMonth: 8 },
                    { endMonth: BigInt(12), unlockPerMonth: 10 }
                ];
                await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,initialIntervals);
                await time.increase(3600);
                await ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT });

                // Wait for timelock to pass and update schedule
                await time.increase(Number(TIMELOCK_DURATION));
                const newIntervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 10 },
                    { endMonth: BigInt(10), unlockPerMonth: 5 },
                    { endMonth: BigInt(12), unlockPerMonth: 10 }
                ];
                await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,newIntervals);
                await ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT });

                // Advance 3 months and claim
                await time.increase(120 * 24 * 60 * 60);
                const expectedTokens1 = PURCHASE_AMOUNT * RATE * BigInt(7) / BigInt(100); // 10% from first purchase month1
                const expectedTokens2 = PURCHASE_AMOUNT * RATE * BigInt(10) / BigInt(100); // 20% from second purchase month1
                
                expect(await ico.getReleasableTokens(addr1.address)).to.equal(expectedTokens1 + expectedTokens2)
                await ico.connect(addr1).claimTokens();
                expect(await token.balanceOf(addr1.address)).to.equal(expectedTokens1 + expectedTokens2);
                expect(await ico.getReleasableTokens(addr1.address)).to.equal(0)

                TestLogger.logTestResult("ICO", "Complex Vesting Scenarios", 
                    "Should handle multiple purchases with different vesting schedules", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Complex Vesting Scenarios", 
                    "Should handle multiple purchases with different vesting schedules", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Gas Optimization Tests", () => {
        it("Should optimize gas for batch whitelist operations", async () => {
            try {
                const users = Array.from({length: 10}, (_, i) => addrs[i].address);
                
                // Measure gas for individual operations
                let totalGasIndividual = BigInt(0);
                for (const user of users) {
                    const tx = await ico.setWhitelist(user, true);
                    const receipt = await tx.wait();
                    totalGasIndividual += receipt!.gasUsed;
                }

                // Measure gas for batch operation
                const batchTx = await ico.setWhitelistBatch(users, true);
                const batchReceipt = await batchTx.wait();
                const batchGas = batchReceipt!.gasUsed;

                // Batch operation should use less gas
                expect(batchGas).to.be.lessThan(totalGasIndividual);

                TestLogger.logTestResult("ICO", "Gas Optimization Tests", 
                    "Should optimize gas for batch whitelist operations", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Gas Optimization Tests", 
                    "Should optimize gas for batch whitelist operations", "failed", 0, error);
                throw error;
            }
        });

        it("Should maintain reasonable gas costs for token purchases", async () => {
            try {
                await ico.setWhitelistEnabled(true);
                await ico.setWhitelist(addr1.address, true);
                await time.increase(3600);

                await expect(ico.setWhitelist(addr1.address, true))
                    .to.be.revertedWithCustomError(ico,"AccountWhitelisted")

                // Measure gas for first purchase
                const tx1 = await ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT });
                const receipt1 = await tx1.wait();
                const gasUsed1 = receipt1!.gasUsed;

                // Wait for timelock
                await time.increase(Number(TIMELOCK_DURATION));

                // Measure gas for second purchase
                const tx2 = await ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT });
                const receipt2 = await tx2.wait();
                const gasUsed2 = receipt2!.gasUsed;

                // Gas costs should be consistent
                const gasDiff = gasUsed1 > gasUsed2 ? 
                    gasUsed1 - gasUsed2 : 
                    gasUsed2 - gasUsed1;
                expect(gasDiff).to.be.lessThan(75000); // Permitir una pequeña variación

                TestLogger.logTestResult("ICO", "Gas Optimization Tests", 
                    "Should maintain reasonable gas costs for token purchases", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Gas Optimization Tests", 
                    "Should maintain reasonable gas costs for token purchases", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Event Emission Tests", () => {
        it("Should emit correct events for token purchases", async () => {
            try {
                await ico.setWhitelistEnabled(true);
                await ico.setWhitelist(addr1.address, true);

                const purchaseAmount = PURCHASE_AMOUNT;
                const expectedTokens = purchaseAmount * RATE;
                await time.increase(3600);
                const intervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 10 },
                    { endMonth: BigInt(10), unlockPerMonth: 5 },
                    { endMonth: BigInt(12), unlockPerMonth: 10 }
                ];
                await ico.setVestingEnabled(true);
                await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,intervals);
                await expect(await ico.connect(addr1).buyTokens({ value: purchaseAmount }))
                    .to.emit(ico, "SoldTokensUpdated")
                    .withArgs(0, expectedTokens);

                await time.increase(Number(TIMELOCK_DURATION));

                await expect(ico.connect(addr1).buyTokens({ value: purchaseAmount }))
                    .to.emit(ico, "VestingAssigned")
                    .withArgs(addr1.address, expectedTokens, 1);
                
                await time.increase(Number(TIMELOCK_DURATION));

                await ico.connect(addr1).buyTokens({ value: ethers.parseEther("7") });
                await time.increase(Number(TIMELOCK_DURATION));

                await expect(ico.connect(addr1).buyTokens({ value: ethers.parseEther("7") }))
                    .to.be.revertedWithCustomError(ico, "TotalAmountPurchaseExceeded");

                TestLogger.logTestResult("ICO", "Event Emission Tests", 
                    "Should emit correct events for token purchases", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Event Emission Tests", 
                    "Should emit correct events for token purchases", "failed", 0, error);
                throw error;
            }
        });

        it("Should emit correct events for configuration changes", async () => {
            try {
                await expect(ico.setRate(RATE))
                    .to.be.revertedWithCustomError(ico, "RateNotChanged")
                    .withArgs(RATE);

                const newRate = BigInt(200);
                await expect(ico.setRate(newRate))
                    .to.emit(ico, "RateUpdated")
                    .withArgs(RATE, newRate);

                await expect(ico.setMaxTokens(MAX_TOKENS))
                    .to.be.revertedWithCustomError(ico,"MaxTokensNotChanged")


                const newMaxTokens = BigInt(2000000000);
                await expect(ico.setMaxTokens(newMaxTokens))
                    .to.emit(ico, "MaxTokensUpdated")
                    .withArgs(MAX_TOKENS * BigInt(1e18), newMaxTokens * BigInt(1e18));

                const newWhitelistStatus = true;
                await expect(ico.setWhitelistEnabled(newWhitelistStatus))
                    .to.emit(ico, "WhitelistStatusUpdated")
                    .withArgs(!newWhitelistStatus, newWhitelistStatus);

                TestLogger.logTestResult("ICO", "Event Emission Tests", 
                    "Should emit correct events for configuration changes", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Event Emission Tests", 
                    "Should emit correct events for configuration changes", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Integration and Stress Tests", () => {
        it("Should handle complex ICO lifecycle with multiple users and state changes", async () => {
            try {
                // Setup initial state
                await ico.setWhitelistEnabled(true);
                await ico.setVestingEnabled(true);
                const intervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 10 },
                    { endMonth: BigInt(10), unlockPerMonth: 5 },
                    { endMonth: BigInt(12), unlockPerMonth: 10 }
                ];
                await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,intervals);

                // Add multiple users to whitelist
                const users = [addr1, addr2, addr3, ...addrs.slice(0, 5)];
                await ico.setWhitelistBatch(users.map(u => u.address), true);
                await time.increase(3601);
                // Simulate multiple purchases with different amounts
                for (let i = 0; i < users.length; i++) {
                    const amount = PURCHASE_AMOUNT * BigInt(i + 1);
                    await ico.connect(users[i]).buyTokens({ value: amount });
                    if (i < users.length - 1) {
                        await time.increase(Number(TIMELOCK_DURATION));
                    }
                }

                // Change vesting schedule mid-ICO
                const newIntervals = [
                    { endMonth: BigInt(6), unlockPerMonth: 7 },
                    { endMonth: BigInt(7), unlockPerMonth: 8 },
                    { endMonth: BigInt(12), unlockPerMonth: 10 }
                ];
                await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,newIntervals);

                // More purchases with new schedule
                await time.increase(Number(TIMELOCK_DURATION));
                for (let i = 0; i < 3; i++) {
                    await ico.connect(users[i]).buyTokens({ value: PURCHASE_AMOUNT });
                    if (i < 2) await time.increase(Number(TIMELOCK_DURATION));
                }

                // Advance time and verify claims
                await time.increase(120 * 24 * 60 * 60); // 4 months
                for (const user of users.slice(0, 3)) {
                    await ico.connect(user).claimTokens();
                    expect(await token.balanceOf(user.address)).to.be.gt(0);
                }

                TestLogger.logTestResult("ICO", "Integration and Stress Tests", 
                    "Should handle complex ICO lifecycle with multiple users and state changes", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Integration and Stress Tests", 
                    "Should handle complex ICO lifecycle with multiple users and state changes", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle rapid state changes and edge conditions", async () => {
            try {
                // Enable/disable features rapidly
                await ico.setWhitelistEnabled(true);
                await ico.setVestingEnabled(true);
                await ico.setWhitelistEnabled(false);
                await ico.setVestingEnabled(false);
                await ico.setWhitelistEnabled(true);
                await ico.setVestingEnabled(true);

                // Rapid vesting schedule changes
                for (let i = 1; i <= 3; i++) {
                    const intervals = [
                        { endMonth: BigInt(6), unlockPerMonth: 10 },
                        { endMonth: BigInt(10), unlockPerMonth: 5 },
                        { endMonth: BigInt(12), unlockPerMonth: 10 }
                    ];
                    await ico.setVestingConfiguration(VESTING_DURATION_IN_MONTHS,intervals);
                }
                await time.increase(3601);
                // Multiple users buying at almost the same time
                await ico.setWhitelistBatch([addr1.address, addr2.address, addr3.address], true);
                const purchasePromises = [
                    ico.connect(addr1).buyTokens({ value: PURCHASE_AMOUNT }),
                    ico.connect(addr2).buyTokens({ value: PURCHASE_AMOUNT * BigInt(2) }),
                    ico.connect(addr3).buyTokens({ value: PURCHASE_AMOUNT * BigInt(3) })
                ];
                await Promise.all(purchasePromises);

                // Quick time jumps and claims
                await time.increase(120 * 24 * 60 * 60); // 3 month 1 day (cliff ended)
                for (let i = 0; i < 3; i++) {
                    await ico.connect(addr1).claimTokens();
                    await ico.connect(addr2).claimTokens();
                    await ico.connect(addr3).claimTokens();
                    await time.increase(30 * 24 * 60 * 60); // 3 month 1 day (cliff ended)
                }

                TestLogger.logTestResult("ICO", "Integration and Stress Tests", 
                    "Should handle rapid state changes and edge conditions", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Integration and Stress Tests", 
                    "Should handle rapid state changes and edge conditions", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle maximum capacity scenario", async () => {
            try {
                // Set up a smaller max supply for testing
                const testMaxSupply = BigInt(100);
                await ico.setMaxTokens(testMaxSupply);
                await ico.setMaxTokensPerUser(testMaxSupply);
                await ico.setWhitelistEnabled(true);

                const testMaxEth = BigInt(100) * BigInt(1e18)
                // Add multiple users
                const users = [addr1, addr2, addr3, ...addrs.slice(0, 5)];
                await ico.setWhitelistBatch(users.map(u => u.address), true);

                // Calculate purchase amount to reach max supply
                const tokensPerEth = RATE;
                const ethRequired = BigInt(testMaxEth) / BigInt(tokensPerEth);
                const purchaseAmount = ethRequired / BigInt(users.length);

                console.log(purchaseAmount)
                // Users buy tokens until max supply is reached
                time.increase(3600)
                for (let i = 0; i < users.length - 1; i++) {
                    await ico.connect(users[i]).buyTokens({ value: `${purchaseAmount}` });
                    // await time.increase(Number(TIMELOCK_DURATION));
                }

                // Last purchase should fail due to max supply
                const remainingTokens = testMaxEth - (purchaseAmount * tokensPerEth /  BigInt(users.length - 1));
                const lastPurchaseAmount = (remainingTokens + BigInt(1)) / tokensPerEth;
                
                await expect(ico.connect(users[users.length - 1]).buyTokens({ value: lastPurchaseAmount }))
                    .to.be.revertedWithCustomError(ico, "NoTokensAvailable");

                // Verify total supply
                expect(await ico.soldTokens()).to.be.lessThanOrEqual(testMaxSupply * BigInt(1e18));

                TestLogger.logTestResult("ICO", "Integration and Stress Tests", 
                    "Should handle maximum capacity scenario", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("ICO", "Integration and Stress Tests", 
                    "Should handle maximum capacity scenario", "failed", 0, error);
                throw error;
            }
        });
    });

    after(async () => {
        const summary = TestLogger.getSummary();
        TestLogger.writeSummary(summary);
    });
});
