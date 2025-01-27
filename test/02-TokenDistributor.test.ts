import { expect } from "chai";
import { ethers } from "hardhat";
import { TestLogger } from "./helpers/TestLogger";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { token } from "../typechain-types/@openzeppelin/contracts";

describe("TokenDistributor", function () {
    const CONTRACT_NAME = "TokenDistributor";
    let tokenDistributor: any;
    let nbkToken: any;
    let owner: any;
    let addr1: any;
    let addr2: any;
    let addr3: any;
    let addrs: any[];

    // --- CHANGED daily limit from 10 to 100 so test distributions (100 NBK, etc.) won't revert ---
    const DAILY_LIMIT = ethers.parseEther("10"); 
    // If you want to keep daily limit = 10, reduce your distributions from 100 NBK -> 10 NBK in the tests below.

    const INITIAL_SUPPLY = ethers.parseEther("100");
    const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    const RATE = BigInt(1000);

    beforeEach(async function () {
        [owner, addr1, addr2, addr3, ...addrs] = await ethers.getSigners();
        
        // Deploy NBKToken first
        const NBKToken = await ethers.getContractFactory("NBKToken");
        nbkToken = await NBKToken.deploy("NeuroBlock", "NBK", owner.address);
        await nbkToken.waitForDeployment();

        // Deploy TokenDistributor
        const TokenDistributor = await ethers.getContractFactory("TokenDistributor");
        tokenDistributor = await TokenDistributor.deploy(
            await nbkToken.getAddress(),
            owner.address,
            DAILY_LIMIT
        );
        await tokenDistributor.waitForDeployment();

        // Mint tokens to TokenDistributor
        await nbkToken.mint(await tokenDistributor.getAddress(), INITIAL_SUPPLY);
        
        // Send ETH to TokenDistributor for withdrawal tests
        
    });

    after(function() {
        const results = {
            duration: this.currentTest?.duration || 0
        };
        TestLogger.writeSummary(results);
    });

    describe("Initial Setup and Configuration", function () {
        it("Should configure initial parameters correctly", async function () {
            try {
                expect(await tokenDistributor.token()).to.equal(await nbkToken.getAddress());
                expect(await tokenDistributor.owner()).to.equal(owner.address);

                // dailyLimit should be 100
                expect(await tokenDistributor.dailyLimit()).to.equal(DAILY_LIMIT);

                // The test contract checks "contract NBK balance" via getContractBalance(), 
                // which is an NBK balance (not ETH). Right after mint we have 100 NBK.
                expect(await tokenDistributor.getContractBalance()).to.equal(INITIAL_SUPPLY);

                // Confirm NBKToken's balanceOf distributor is 100
                expect(await nbkToken.balanceOf(await tokenDistributor.getAddress())).to.equal(INITIAL_SUPPLY);
                expect(tokenDistributor.setAllowedInteractors(ethers.ZeroAddress))
                .to.emit(tokenDistributor,"InvalidBeneficiary");

                await tokenDistributor.setAllowedInteractors(addr1.address);
                expect(await tokenDistributor.checkAllowed(addr1.address)).to.be.equal(true)
                expect(await tokenDistributor.connect(owner).checkAllowed(addr3.address)).to.be.equal(false)


                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", Number(0));
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", Number(0), error);
                throw error;
            }
        });

        it("Should handle daily limit updates correctly", async function () {
            try {
                const newLimit = ethers.parseEther("2000");
                await tokenDistributor.setDailyLimit(newLimit);
                expect(await tokenDistributor.dailyLimit()).to.equal(newLimit);

                // Only owner can update
                await expect(tokenDistributor.connect(addr1).setDailyLimit(newLimit))
                    .to.be.revertedWithCustomError(tokenDistributor, "OwnableUnauthorizedAccount");

                // Cannot set limit to 0
                await expect(tokenDistributor.setDailyLimit(0))
                    .to.be.revertedWithCustomError(tokenDistributor, "DailyLimitUpdateValueIncorrect")
                    .withArgs(0);

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", Number(0));
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", Number(0), error);
                throw error;
            }
        });

        it("Should validate constructor parameters", async function () {
            try {
                const TokenDistributor = await ethers.getContractFactory("TokenDistributor");
                
                // Should not initialize with zero token address
                await expect(TokenDistributor.deploy(
                    ZERO_ADDRESS,
                    owner.address,
                    DAILY_LIMIT
                )).to.be.reverted;

                // Should not initialize with zero owner
                await expect(TokenDistributor.deploy(
                    await nbkToken.getAddress(),
                    ZERO_ADDRESS,
                    DAILY_LIMIT
                )).to.be.reverted;

                // Should not initialize with dailyLimit = 0
                await expect(TokenDistributor.deploy(
                    await nbkToken.getAddress(),
                    owner.address,
                    0
                )).to.be.revertedWithCustomError(tokenDistributor, "DailyLimitUpdateValueIncorrect");

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", Number(0));
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", Number(0), error);
                throw error;
            }
        });

        it("Should emit events on configuration changes", async function () {
            try {
                const newLimit = ethers.parseEther("2000");
                
                // Check DailyLimitUpdated
                await expect(tokenDistributor.setDailyLimit(newLimit))
                    .to.emit(tokenDistributor, "DailyLimitUpdated")
                    .withArgs(newLimit);

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", Number(0));
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", Number(0), error);
                throw error;
            }
        });
    });

    describe("Token Distribution Functionality", function () {
        it("Should distribute tokens to a single user correctly", async function () {
            try {
                // Because dailyLimit = 100, distributing 100 once is fine
                const amount = ethers.parseEther("100");

                // First distribution
                await expect(tokenDistributor.distributeTokens(addr1.address, amount, RATE))
                .to.emit(tokenDistributor, "ActivityPerformed")
                .withArgs(owner.address, amount);
                
                expect(await nbkToken.balanceOf(addr1.address)).to.equal(amount).to.emit(tokenDistributor, "ActivityPerformed")
                    .withArgs(owner.address, amount)

                // Check ActivityPerformed event with 2 args: (actor, amount)
                

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", Number(0));
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", Number(0), error);
                throw error;
            }
        });

        // it("Should handle batch distribution correctly", async function () {
        //     try {
        //         // Because dailyLimit=100, let's keep total <= 100 in batch
        //         const addresses = [addr1.address, addr2.address, addr3.address];
        //         const amounts = [
        //             ethers.parseEther("30"),
        //             ethers.parseEther("20"),
        //             ethers.parseEther("50")
        //         ]; // sum = 100

        //         await tokenDistributor.distributeTokensBatch(addresses, amounts);

        //         // Check final balances
        //         for (let i = 0; i < addresses.length; i++) {
        //             expect(await nbkToken.balanceOf(addresses[i])).to.equal(amounts[i]);
        //         }

        //         // Check revert on mismatch arrays
        //         await expect(tokenDistributor.distributeTokensBatch(addresses, amounts.slice(0, 2)))
        //             .to.be.revertedWithCustomError(tokenDistributor, "ArrayMismatchBatchDistribution")
        //             .withArgs(3, 2);

        //         TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", Number(0));
        //     } catch (error) {
        //         TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", Number(0), error);
        //         throw error;
        //     }
        // });

        it("Should handle distribution limits and errors correctly", async function () {
            try {
                const exceedingAmount = ethers.parseEther("101");

                // Attempt distributing more tokens than contract has
                await expect(tokenDistributor.distributeTokens(addr1.address, exceedingAmount * RATE, RATE))
                    .to.be.revertedWithCustomError(tokenDistributor, "NotEnoughTokensOnDistributor");

                // Distribute entire INITIAL_SUPPLY (100)
                await tokenDistributor.distributeTokens(addr1.address, INITIAL_SUPPLY, RATE);
                
                // Attempt distributing after emptying contract
                const smallAmount = ethers.parseEther("1");
                await expect(tokenDistributor.distributeTokens(addr2.address, smallAmount, RATE))
                    .to.be.revertedWithCustomError(tokenDistributor, "NotEnoughTokensOnDistributor");

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", Number(0));
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", Number(0), error);
                throw error;
            }
        });

        it("Should handle distribution to contract addresses correctly", async function () {
            try {
                // Deploy a dummy NBKToken as a "receiver contract"
                const TestReceiver = await ethers.getContractFactory("NBKToken");
                const receiverContract = await TestReceiver.deploy("Test", "TEST", owner.address);
                await receiverContract.waitForDeployment();

                const amount = ethers.parseEther("50");
                await tokenDistributor.distributeTokens(await receiverContract.getAddress(), amount, RATE);
                
                expect(await nbkToken.balanceOf(await receiverContract.getAddress())).to.equal(amount);

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", Number(0));
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", Number(0), error);
                throw error;
            }
        });

        // it("Should optimize gas usage in batch distributions", async function () {
        //     try {
        //         const batchSize = 10;
        //         const addresses = Array(batchSize).fill(addr1.address);
        //         const amounts = Array(batchSize).fill(ethers.parseEther("1")); // sum=10, safe for dailyLimit=100

        //         // Gas measurement for single distributions
        //         let totalGasIndividual = BigInt(0);
        //         for (let i = 0; i < batchSize; i++) {
        //             const tx = await tokenDistributor.distributeTokens(addresses[i], amounts[i]);
        //             const receipt = await tx.wait();
        //             totalGasIndividual += receipt.gasUsed;
        //         }

        //         // Gas measurement for batch
        //         // Need to re-fund the distributor because it used tokens above
        //         // Re-mint or reset? For simplicity, let's just re-mint some tokens
        //         await nbkToken.mint(await tokenDistributor.getAddress(), ethers.parseEther("100"));

        //         // const batchTx = await tokenDistributor.distributeTokensBatch(addresses, amounts);
        //         const batchReceipt = await batchTx.wait();
        //         const batchGas = batchReceipt.gasUsed;

        //         // Check that batch uses less gas
        //         expect(batchGas).to.be.lt(totalGasIndividual);

        //         TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", Number(0));
        //     } catch (error) {
        //         TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", Number(0), error);
        //         throw error;
        //     }
        // });

        it("Should handle complex distribution patterns", async function () {
            try {
                // We'll do 3 distributions of 30, 40, 30 => total 100 (still within daily limit)
                const distributions = [
                    { address: addr1.address, amount: ethers.parseEther("30") },
                    { address: addr2.address, amount: ethers.parseEther("40") },
                    { address: addr3.address, amount: ethers.parseEther("30") }
                ];

                for (const dist of distributions) {
                    await tokenDistributor.distributeTokens(dist.address, dist.amount, RATE);
                    // Pause & unpause between calls
                    await tokenDistributor.pauseDistributor();
                    // revert reason from OpenZeppelin is "Pausable: paused"
                    await expect(tokenDistributor.distributeTokens(dist.address, dist.amount, RATE))
                        .to.be.revertedWithCustomError(tokenDistributor,"EnforcedPause");
                    await tokenDistributor.unpauseDistributor();
                }

                // Verify final balances
                expect(await nbkToken.balanceOf(addr1.address)).to.equal(ethers.parseEther("30"));
                expect(await nbkToken.balanceOf(addr2.address)).to.equal(ethers.parseEther("40"));
                expect(await nbkToken.balanceOf(addr3.address)).to.equal(ethers.parseEther("30"));

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", Number(0));
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", Number(0), error);
                throw error;
            }
        });
    });

    describe("Withdrawal and Daily Limits", function () {
        // We do not necessarily need a beforeEach for ETH here, 
        // you already do it in the global beforeEach. It's OK to keep if needed.
        // Removing to reduce confusion.

        it("Should handle withdrawals within daily limit correctly", async function () {
            try {
                await addr3.sendTransaction({
                    to: await tokenDistributor.getAddress(),
                    value: ethers.parseEther("600")
                })
                const withdrawAmount = ethers.parseEther("5"); // fully use daily limit = 100 or partially
                await tokenDistributor.withdrawFunds(withdrawAmount);

                // Check daily limit
                const remainingLimit = await tokenDistributor.getRemainingDailyLimit();
                expect(remainingLimit).to.equal(DAILY_LIMIT - withdrawAmount);

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", Number(0));
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", Number(0), error);
                throw error;
            }
        });

        it("Should enforce daily withdrawal limits correctly", async function () {
            try {
                // dailyLimit=100, so withdrawing 101 => revert
                await addr3.sendTransaction({
                    to: await tokenDistributor.getAddress(),
                    value: ethers.parseEther("600")
                })
                await nbkToken.mint(await tokenDistributor.getAddress(), INITIAL_SUPPLY);

                await expect(tokenDistributor.withdrawFunds(DAILY_LIMIT + ethers.parseEther("0.1")))
                    .to.be.revertedWithCustomError(tokenDistributor, "DailyLimitWithdrawReached");

                // withdraw multiple times until total 100
                const firstWithdraw = ethers.parseEther("4");
                const secondWithdraw = ethers.parseEther("6");
                await tokenDistributor.withdrawFunds(firstWithdraw);
                await tokenDistributor.withdrawFunds(secondWithdraw);

                // 3rd withdraw => daily limit reached
                const thirdWithdraw = ethers.parseEther("0.1");
                await expect(tokenDistributor.withdrawFunds(thirdWithdraw))
                    .to.be.revertedWithCustomError(tokenDistributor, "DailyLimitWithdrawReached");

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", Number(0));
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", Number(0), error);
                throw error;
            }
        });

        it("Should reset daily limits correctly after 24 hours", async function () {
            try {
                await addr3.sendTransaction({
                    to: await tokenDistributor.getAddress(),
                    value: ethers.parseEther("600")
                })
                const withdrawAmount = ethers.parseEther("8");
                await tokenDistributor.withdrawFunds(withdrawAmount);

                // Advance 24 hours
                await time.increase(24 * 60 * 60);

                // daily limit should reset to 100
                const after24hLimit = await tokenDistributor.getRemainingDailyLimit();
                expect(after24hLimit).to.equal(DAILY_LIMIT);

                // Withdraw again => should succeed
                await tokenDistributor.withdrawFunds(withdrawAmount);
                const newRemaining = await tokenDistributor.getRemainingDailyLimit();
                expect(newRemaining).to.equal(DAILY_LIMIT - withdrawAmount);

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle partial day withdrawals correctly", async function () {
            try {
                // We'll do 3 withdrawals of 3, spaced out, total 30, well under 100
                await addr3.sendTransaction({
                    to: await tokenDistributor.getAddress(),
                    value: ethers.parseEther("600")
                })
                const withdrawals = [
                    { amount: ethers.parseEther("3"), delay: 8 * 3600 },  // 8 hours
                    { amount: ethers.parseEther("3"), delay: 6 * 3600 },  // 6 more hours
                    { amount: ethers.parseEther("3"), delay: 9 * 3600 }   // 9 more hours
                ];

                for (const w of withdrawals) {
                    await time.increase(w.delay);
                    await tokenDistributor.withdrawFunds(w.amount);

                    const remain = await tokenDistributor.getRemainingDailyLimit();
                    // Should still be <= dailyLimit
                    expect(remain).to.be.lte(DAILY_LIMIT);
                }

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle withdrawal edge cases", async function () {
            try {
                // Because dailyLimit=100, withdrawing 101 => InvalidWithdrawAmount
                await addr3.sendTransaction({
                    to: await tokenDistributor.getAddress(),
                    value: ethers.parseEther("7")
                })

                const tooLarge = ethers.parseEther("9");
                await expect(tokenDistributor.withdrawFunds(tooLarge))
                    .to.be.revertedWithCustomError(tokenDistributor, "NotEnoughEtherToWithdraw");

                // Minimum possible amount (1 wei of NBK)
                const minAmount = BigInt(1);
                await tokenDistributor.withdrawFunds(minAmount);

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Emergency Controls and Recovery", function () {
        it("Should revert correctly on emergency recovery", async function () {
            await expect(
                tokenDistributor.emergencyTokenRecovery(
                    await nbkToken.getAddress(),
                    addr1.address,
                    ethers.parseEther("0")
                )).to.be.revertedWithCustomError(tokenDistributor, "InvalidWithdrawAmount").withArgs(
                    0
                )
            
            await expect(
                tokenDistributor.emergencyTokenRecovery(
                    await nbkToken.getAddress(),
                    ethers.ZeroAddress,
                    ethers.parseEther("1")
                )).to.be.revertedWithCustomError(tokenDistributor, "InvalidBeneficiary").withArgs(
                    ethers.ZeroAddress
                )

            await expect(
                tokenDistributor.emergencyTokenRecovery(
                    await nbkToken.getAddress(),
                    addr1.address,
                    ethers.parseEther("10000")
                )).to.be.revertedWithCustomError(tokenDistributor, "NotEnoughTokensOnDistributor").withArgs(
                    INITIAL_SUPPLY, ethers.parseEther("10000")
                )
            
            const recoveryAmount = ethers.parseEther("10")
            // Attempt recovery and expect revert
            await expect(
                tokenDistributor.emergencyTokenRecovery(
                    addr3.address,
                    addr1.address,
                    recoveryAmount
                )
            ).to.be.reverted

            await expect(
                tokenDistributor.emergencyTokenRecovery(
                    await nbkToken.getAddress(),
                    addr1.address,
                    recoveryAmount
                )).to.emit(tokenDistributor, "EmergencyTokenRecovery").to.emit(tokenDistributor,"ActivityPerformed")
        });
        it("Should handle emergency token recovery", async function () {
            try {
                // Send more NBK directly
                const amount = ethers.parseEther("50");
                const initialBalance = await nbkToken.balanceOf(await tokenDistributor.getAddress());
                
                // We'll just do a normal distribution from that extra 50
                await tokenDistributor.distributeTokens(addr1.address, amount, RATE);

                const finalBalance = await nbkToken.balanceOf(await tokenDistributor.getAddress());
                expect(finalBalance).to.equal(initialBalance - amount);

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });

        it("Should maintain security during emergency operations", async function () {
            try {
                const amount = ethers.parseEther("50");

                // Pause the contract => expect revert with "Pausable: paused" from OpenZeppelin
                await tokenDistributor.pauseDistributor();

                await expect(tokenDistributor.distributeTokens(addr1.address, amount, RATE))
                    .to.be.revertedWithCustomError(tokenDistributor,"EnforcedPause");

                // The setDailyLimit is still allowed if the contract doesn't block it. 
                // If your code allows onlyOwner calls while paused, that works:
                await tokenDistributor.setDailyLimit(ethers.parseEther("150"));
                
                // Check that only the owner can unpause
                await expect(tokenDistributor.connect(addr1).unpauseDistributor())
                    .to.be.revertedWithCustomError(tokenDistributor, "OwnableUnauthorizedAccount");

                // Now unpause as owner
                await tokenDistributor.unpauseDistributor();
                await tokenDistributor.distributeTokens(addr1.address, amount, RATE);

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Gas Optimization and Performance", function () {
        // it("Should optimize gas usage for bulk operations", async function () {
        //     try {
        //         const users = 5;
        //         const amount = ethers.parseEther("1");
                
        //         const addresses = Array(users).fill(addr1.address);
        //         const amounts = Array(users).fill(amount);

        //         let totalGasIndividual = BigInt(0);
        //         for (let i = 0; i < users; i++) {
        //             const tx = await tokenDistributor.distributeTokens(addresses[i], amounts[i]);
        //             const receipt = await tx.wait();
        //             totalGasIndividual += receipt.gasUsed;
        //         }

        //         // Replenish tokens
        //         await nbkToken.mint(await tokenDistributor.getAddress(), ethers.parseEther("50"));

        //         const batchTx = await tokenDistributor.distributeTokensBatch(addresses, amounts);
        //         const batchReceipt = await batchTx.wait();
        //         const batchGas = batchReceipt.gasUsed;

        //         expect(batchGas).to.be.lt(totalGasIndividual);

        //         TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
        //     } catch (error) {
        //         TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
        //         throw error;
        //     }
        // });

        it("Should handle high-frequency operations efficiently", async function () {
            try {
                const operations = 10;
                const amount = ethers.parseEther("2"); // total=20 < 100 dailyLimit

                for (let i = 0; i < operations; i++) {
                    await tokenDistributor.distributeTokens(addr1.address, amount, RATE);
                }

                const finalBalance = await nbkToken.balanceOf(addr1.address);
                expect(finalBalance).to.equal(amount * BigInt(operations));

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Event Emission and Logging", function () {
        it("Should emit correct events for all operations", async function () {
            try {
                const amount = ethers.parseEther("10");

                // distribution => ActivityPerformed
                await expect(tokenDistributor.distributeTokens(addr1.address, amount, RATE))
                    .to.emit(tokenDistributor, "ActivityPerformed")
                    .withArgs(owner.address, amount);

                // daily limit update => DailyLimitUpdated
                const newLimit = ethers.parseEther("150");
                await expect(tokenDistributor.setDailyLimit(newLimit))
                    .to.emit(tokenDistributor, "DailyLimitUpdated")
                    .withArgs(newLimit);

                // pause => "Paused" from OpenZeppelin 
                await expect(tokenDistributor.pauseDistributor())
                    .to.emit(tokenDistributor, "Paused")
                    .withArgs(owner.address);

                // send ETH => "FundsReceived"
                const ethAmount = ethers.parseEther("1");
                await expect(owner.sendTransaction({
                    to: await tokenDistributor.getAddress(),
                    value: ethAmount
                })).to.emit(tokenDistributor, "FundsReceived")
                    .withArgs(owner.address, ethAmount);

                await expect(tokenDistributor.unpauseDistributor())
                    .to.emit(tokenDistributor, "Unpaused")
                    .withArgs(owner.address);

                await expect(tokenDistributor.connect(addr2).distributeTokens(addr1.address, amount, RATE))
                    .to.revertedWithCustomError(tokenDistributor,"UnauthorizedCaller")

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });

        it("Should maintain event consistency under stress", async function () {
            try {
                const operations = 5;
                const amount = ethers.parseEther("1");
                
                for (let i = 0; i < operations; i++) {
                    await expect(tokenDistributor.distributeTokens(addr1.address, amount, RATE))
                        .to.emit(tokenDistributor, "ActivityPerformed")
                        .withArgs(owner.address, amount);

                    if (i % 2 === 0) {
                        await expect(tokenDistributor.pauseDistributor())
                            .to.emit(tokenDistributor, "Paused")
                            .withArgs(owner.address);
                        await expect(tokenDistributor.unpauseDistributor())
                            .to.emit(tokenDistributor, "Unpaused")
                            .withArgs(owner.address);
                    }
                }

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Security and Access Control", function () {
        it("Should prevent unauthorized access to critical functions", async function () {
            try {
                const newLimit = ethers.parseEther("2000");

                for (const account of [addr1, addr2, addr3]) {
                    await expect(tokenDistributor.connect(account).setDailyLimit(newLimit))
                        .to.be.revertedWithCustomError(tokenDistributor, "OwnableUnauthorizedAccount");

                    await expect(tokenDistributor.connect(account).pauseDistributor())
                        .to.be.revertedWithCustomError(tokenDistributor, "OwnableUnauthorizedAccount");

                    await expect(tokenDistributor.connect(account).unpauseDistributor())
                        .to.be.revertedWithCustomError(tokenDistributor, "OwnableUnauthorizedAccount");
                }

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle ownership transfer securely", async function () {
            try {
                // Transfer ownership to addr1
                await tokenDistributor.transferOwnership(addr1.address);
                expect(await tokenDistributor.owner()).to.equal(addr1.address);

                // old owner can't do onlyOwner calls
                await expect(tokenDistributor.connect(owner).setDailyLimit(ethers.parseEther("2000")))
                    .to.be.revertedWithCustomError(tokenDistributor, "OwnableUnauthorizedAccount");

                // new owner can do it
                await tokenDistributor.connect(addr1).setDailyLimit(ethers.parseEther("2000"));

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });

        // it("Should prevent malicious batch operations", async function () {
        //     try {
        //         // Attempt distributing to invalid addresses
        //         const invalidAddresses = [
        //             ZERO_ADDRESS,
        //             ethers.ZeroAddress,
        //             "0x000000000000000000000000000000000000dEaD"
        //         ];
        //         const amounts = Array(invalidAddresses.length).fill(ethers.parseEther("1"));

        //         await expect(tokenDistributor.distributeTokensBatch(invalidAddresses, amounts))
        //             .to.be.reverted;

        //         TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
        //     } catch (error) {
        //         TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
        //         throw error;
        //     }
        // });
        // it("Should revert batch operations correectly with amount over totalBalance or unauthorized caller", async function () {
        //     try {
        //         // Attempt distributing to invalid addresses
        //         const addresses = [
        //             addr1.address,
        //             addr2.address,
        //             addr3.address,
        //         ];
        //         const amounts = Array(addresses.length).fill(ethers.parseEther("1000"));

        //         await expect(tokenDistributor.connect(addr1).distributeTokensBatch(addresses, amounts))
        //             .to.be.revertedWithCustomError(tokenDistributor,"UnauthorizedCaller");


        //         await expect(tokenDistributor.distributeTokensBatch(addresses, amounts))
        //             .to.be.revertedWithCustomError(tokenDistributor,"NotEnoughTokensOnDistributor");

        //         TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
        //     } catch (error) {
        //         TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
        //         throw error;
        //     }
        // });
    });

    describe("Complex State Transitions", function () {
        it("Should handle rapid state changes correctly", async function () {
            try {
                const amount = ethers.parseEther("20"); 
                // total day usage can be up to 100
                await nbkToken.mint(await tokenDistributor.getAddress(), INITIAL_SUPPLY);


                for (let i = 0; i < 5; i++) {
                    // distribute
                    await tokenDistributor.distributeTokens(addr1.address, amount,RATE);

                    // Pause
                    await tokenDistributor.pauseDistributor();

                    // Attempt distributing while paused => "Pausable: paused"
                    await expect(tokenDistributor.distributeTokens(addr1.address, amount, RATE))
                        .to.be.revertedWithCustomError(tokenDistributor,"EnforcedPause");

                    // Unpause
                    await tokenDistributor.unpauseDistributor();

                    // distribute again
                    await tokenDistributor.distributeTokens(addr1.address, amount, RATE);
                }

                // final balance for addr1 => 5 * 2 calls * 20 each => 200
                const finalBalance = await nbkToken.balanceOf(addr1.address);
                expect(finalBalance).to.equal(ethers.parseEther("200"));

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });

        it("Should maintain consistent state during complex operations", async function () {
            try {
                const operations = [
                    {
                        action: "distribute",
                        amount: ethers.parseEther("30"),
                        recipient: addr1.address
                    },
                    {
                        action: "updateLimit",
                        newLimit: ethers.parseEther("200")
                    },
                    {
                        action: "pause"
                    },
                    {
                        action: "unpause"
                    },
                    {
                        action: "distribute",
                        amount: ethers.parseEther("50"),
                        recipient: addr2.address
                    }
                ];

                for (const op of operations) {
                    switch (op.action) {
                        case "distribute":
                            await tokenDistributor.distributeTokens(op.recipient!, op.amount!, RATE);
                            break;
                        case "updateLimit":
                            await tokenDistributor.setDailyLimit(op.newLimit!);
                            break;
                        case "pause":
                            await tokenDistributor.pauseDistributor();
                            break;
                        case "unpause":
                            await tokenDistributor.unpauseDistributor();
                            break;
                    }
                }

                // final checks
                expect(await tokenDistributor.dailyLimit()).to.equal(ethers.parseEther("200"));
                expect(await tokenDistributor.paused()).to.be.false;
                expect(await nbkToken.balanceOf(addr1.address)).to.equal(ethers.parseEther("30"));
                expect(await nbkToken.balanceOf(addr2.address)).to.equal(ethers.parseEther("50"));

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Recovery and Error Handling", function () {
        it("Should recover from failed operations gracefully", async function () {
            try {
                const amount = ethers.parseEther("20");
                
                // Pause => "Pausable: paused" revert
                await tokenDistributor.pauseDistributor();
                await expect(tokenDistributor.distributeTokens(addr1.address, amount, RATE))
                    .to.be.revertedWithCustomError(tokenDistributor,"EnforcedPause");;

                // Unpause
                await tokenDistributor.unpauseDistributor();
                await tokenDistributor.distributeTokens(addr1.address, amount, RATE);

                // final checks
                expect(await nbkToken.balanceOf(addr1.address)).to.equal(amount);
                expect(await tokenDistributor.paused()).to.be.false;

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle multiple failed transactions in sequence", async function () {
            try {
                const amount = ethers.parseEther("20");

                const failedOps = [
                    // Distribute to zero => now we expect custom error "InvalidBeneficiary"
                    {
                        op: () => tokenDistributor.distributeTokens(ZERO_ADDRESS, amount * RATE, RATE),
                        expectedError: "InvalidBeneficiary"
                    },
                    // Distribute more than contract has => "NotEnoughTokensOnDistributor"
                    {
                        op: () => tokenDistributor.distributeTokens(
                            addr1.address, 
                            (INITIAL_SUPPLY + ethers.parseEther("50")) * RATE,
                            RATE
                        ),
                        expectedError: "NotEnoughTokensOnDistributor"
                    }
                    // Distribute with mismatched arrays => "ArrayMismatchBatchDistribution"
                    // {
                    //     op: () => tokenDistributor.distributeTokensBatch([addr1.address, addr2.address], [amount]),
                    //     expectedError: "ArrayMismatchBatchDistribution"
                    // }
                ];

                for (const fop of failedOps) {
                    await expect(fop.op()).to.be.revertedWithCustomError(tokenDistributor, fop.expectedError);
                }

                // Should still work after fails
                await tokenDistributor.distributeTokens(addr1.address, amount, RATE);
                expect(await nbkToken.balanceOf(addr1.address)).to.equal(amount);

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Boundary Conditions and Edge Cases", function () {
        it("Should handle minimum and maximum values correctly", async function () {
            try {
                const minAmount = BigInt(1); 
                // await nbkToken.mint(await tokenDistributor.getAddress(), INITIAL_SUPPLY);
                // max is the entire supply for now, since dailyLimit=100 and supply=100 => we can do 100 in one go

                // distribute min
                await tokenDistributor.distributeTokens(addr1.address, minAmount * RATE, RATE);
                expect(await nbkToken.balanceOf(addr1.address)).to.equal(minAmount * RATE);
                

                const remain = (INITIAL_SUPPLY - minAmount) / RATE; // cantidad en wei
               
                await tokenDistributor.distributeTokens(addr2.address, remain * RATE, RATE);
                expect(await nbkToken.balanceOf(addr2.address)).to.equal(remain * RATE);
                // Now the contract is empty => distributing 1 more => NotEnoughTokensOnDistributor
                await expect(tokenDistributor.distributeTokens(addr3.address, minAmount * RATE, RATE))
                    .to.be.revertedWithCustomError(tokenDistributor, "NotEnoughTokensOnDistributor");

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle time-based edge cases", async function () {
            try {
                await nbkToken.mint(await tokenDistributor.getAddress(), INITIAL_SUPPLY);
                await nbkToken.mint(await tokenDistributor.getAddress(), INITIAL_SUPPLY);
                await nbkToken.mint(await tokenDistributor.getAddress(), INITIAL_SUPPLY);
                const amount = ethers.parseEther("2");
                const timeJumps = [
                    1,
                    60,
                    3600,
                    86400,     
                    86400 * 7,
                    86400 * 30,
                    86400 * 365
                ];

                await addr3.sendTransaction({
                    to: await tokenDistributor.getAddress(),
                    value: ethers.parseEther("600")
                })
                
                let withdrawToday:bigint = BigInt(0);
                for (const jump of timeJumps) {
                    await expect(await tokenDistributor.withdrawFunds(amount)).to.emit(tokenDistributor,"FundsWithdrawn").to.emit(tokenDistributor,"ActivityPerformed")
                    withdrawToday += amount
                    await ethers.provider.send("evm_increaseTime", [jump]); // 8 días
                    await ethers.provider.send("evm_mine");

                    const remain = await tokenDistributor.getRemainingDailyLimit();

                    if (jump >= 86400) {
                        expect(remain).to.equal(DAILY_LIMIT);
                    } else {
                        expect(remain).to.equal(DAILY_LIMIT - withdrawToday);
                    }
                }

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle concurrent operations correctly", async function () {
            try {
                const amount = ethers.parseEther("10");
                const ops = 5; 
                // 5 * 10 = 50 total => under daily limit 100

                const promises = [];
                for (let i = 0; i < ops; i++) {
                    promises.push(tokenDistributor.distributeTokens(addr1.address, amount, RATE));
                }

                await Promise.all(promises);

                const finalBalance = await nbkToken.balanceOf(addr1.address);
                expect(finalBalance).to.equal(amount * BigInt(ops));

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Integration and Interaction Patterns", function () {
        it("Should handle complex token distribution patterns", async function () {
            try {
                // We'll do 3 distributions with short delays, each <= dailyLimit total
                const distributions = [
                    { recipient: addr1.address, amount: ethers.parseEther("30"), delay: 0 },
                    { recipient: addr2.address, amount: ethers.parseEther("50"), delay: 1000 },
                    { recipient: addr3.address, amount: ethers.parseEther("20"), delay: 2000 }
                ];

                for (const dist of distributions) {
                    if (dist.delay > 0) {
                        await time.increase(dist.delay);
                    }
                    await tokenDistributor.distributeTokens(dist.recipient, dist.amount, RATE);
                }

                expect(await nbkToken.balanceOf(addr1.address)).to.equal(ethers.parseEther("30"));
                expect(await nbkToken.balanceOf(addr2.address)).to.equal(ethers.parseEther("50"));
                expect(await nbkToken.balanceOf(addr3.address)).to.equal(ethers.parseEther("20"));

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });

    //     it("Should maintain consistency during mixed operations", async function () {
    //         try {
    //             const amount = ethers.parseEther("30");
                
    //             const mixedOps = async () => {
    //                 // normal distribution
    //                 await tokenDistributor.distributeTokens(addr1.address, amount);
                    
    //                 // pause + dailyLimit update
    //                 await tokenDistributor.pauseDistributor();
    //                 await tokenDistributor.setDailyLimit(DAILY_LIMIT * BigInt(2));

    //                 // unpause + batch distribution
    //                 await tokenDistributor.unpauseDistributor();
    //                 const batchAddresses = [addr2.address, addr3.address];
    //                 const batchAmounts = [ethers.parseEther("20"), ethers.parseEther("20")];
    //                 await tokenDistributor.distributeTokensBatch(batchAddresses, batchAmounts);
    //             };

    //             await mixedOps();

    //             expect(await nbkToken.balanceOf(addr1.address)).to.equal(amount);
    //             expect(await nbkToken.balanceOf(addr2.address)).to.equal(ethers.parseEther("20"));
    //             expect(await nbkToken.balanceOf(addr3.address)).to.equal(ethers.parseEther("20"));
    //             expect(await tokenDistributor.dailyLimit()).to.equal(DAILY_LIMIT * BigInt(2));
    //             expect(await tokenDistributor.paused()).to.be.false;

    //             TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
    //         } catch (error) {
    //             TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
    //             throw error;
    //         }
    //     });
    });

    describe("Function Interactions and Dependencies", function () {
        interface OperationResult {
            type: string;
            recipient?: string;
            amount?: bigint;
            newLimit?: bigint;
        }

        it("Should verify contract state consistency", async function () {
            try {
                const amount = ethers.parseEther("50");
                
                // Sequence of ops
                const operations = [
                    async () => {
                        await tokenDistributor.distributeTokens(addr1.address, amount, RATE);
                        return { type: "distribution", recipient: addr1.address, amount } as OperationResult;
                    },
                    async () => {
                        await tokenDistributor.pauseDistributor();
                        return { type: "pause" } as OperationResult;
                    },
                    async () => {
                        await tokenDistributor.setDailyLimit(DAILY_LIMIT * BigInt(2));
                        return { type: "limitUpdate", newLimit: DAILY_LIMIT * BigInt(2) } as OperationResult;
                    },
                    async () => {
                        await tokenDistributor.unpauseDistributor();
                        return { type: "unpause" } as OperationResult;
                    }
                ];

                for (const op of operations) {
                    const result = await op();
                    switch (result.type) {
                        case "distribution":
                            expect(await nbkToken.balanceOf(result.recipient!)).to.equal(result.amount);
                            break;
                        case "pause":
                            expect(await tokenDistributor.paused()).to.be.true;
                            break;
                        case "unpause":
                            expect(await tokenDistributor.paused()).to.be.false;
                            break;
                        case "limitUpdate":
                            expect(await tokenDistributor.dailyLimit()).to.equal(result.newLimit);
                            break;
                    }
                }

                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult(CONTRACT_NAME, this.test?.parent?.title || "", this.test?.title || "", "failed", 0, error);
                throw error;
            }
        });
    });
});
