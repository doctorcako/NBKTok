import { expect } from "chai";
import { ethers } from "hardhat";
import { TestLogger } from "./helpers/TestLogger";
import { NBKToken } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { MaxUint256 } from "ethers";

describe("NBKToken", () => {
  let token: NBKToken;
    let owner: SignerWithAddress;
    let addr1: SignerWithAddress;
    let addr2: SignerWithAddress;
    let addr3: SignerWithAddress;
    let addrs: SignerWithAddress[];

    const TOKEN_NAME = "NBK Token";
    const TOKEN_SYMBOL = "NBK";
    const INITIAL_SUPPLY = ethers.parseEther("0");
    const MINT_AMOUNT = ethers.parseEther("1000");
    const TRANSFER_AMOUNT = ethers.parseEther("100");
    const ZERO_ADDRESS = ethers.ZeroAddress;

    beforeEach(async () => {
        [owner, addr1, addr2, addr3, ...addrs] = await ethers.getSigners();
        const NBKToken = await ethers.getContractFactory("NBKToken");
        token = await NBKToken.deploy(TOKEN_NAME, TOKEN_SYMBOL, owner.address) as NBKToken;
    });

    describe("Deployment & Basic Configuration", () => {
        it("Should set the right name and symbol", async () => {
            try {
                expect(await token.name()).to.equal(TOKEN_NAME);
                expect(await token.symbol()).to.equal(TOKEN_SYMBOL);
                expect(await token.decimals()).to.equal(18);
                TestLogger.logTestResult("NBKToken", "Deployment & Basic Configuration", 
                    "Should set the right name and symbol", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Deployment & Basic Configuration", 
                    "Should set the right name and symbol", "failed", 0, error);
                throw error;
            }
        });

        it("Should have zero initial supply", async () => {
            try {
                expect(await token.totalSupply()).to.equal(INITIAL_SUPPLY);
                expect(await token.balanceOf(owner.address)).to.equal(INITIAL_SUPPLY);
                TestLogger.logTestResult("NBKToken", "Deployment & Basic Configuration", 
                    "Should have zero initial supply", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Deployment & Basic Configuration", 
                    "Should have zero initial supply", "failed", 0, error);
                throw error;
            }
        });

        it("Should set the right owner", async () => {
            try {
                expect(await token.owner()).to.equal(owner.address);
                expect(await token.owner()).to.not.equal(addr1.address);
                TestLogger.logTestResult("NBKToken", "Deployment & Basic Configuration", 
                    "Should set the right owner", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Deployment & Basic Configuration", 
                    "Should set the right owner", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Minting Functionality", () => {
        it("Should allow owner to mint tokens", async () => {
            try {
                const initialSupply = await token.totalSupply();
                await token.mint(addr1.address, MINT_AMOUNT);
                
                expect(await token.balanceOf(addr1.address)).to.equal(MINT_AMOUNT);
                expect(await token.totalSupply()).to.equal(initialSupply + MINT_AMOUNT);

                // Verificar emisión del evento Transfer
                await expect(token.mint(addr1.address, MINT_AMOUNT))
                    .to.emit(token, "Transfer")
                    .withArgs(ZERO_ADDRESS, addr1.address, MINT_AMOUNT);

                TestLogger.logTestResult("NBKToken", "Minting Functionality", 
                    "Should allow owner to mint tokens", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Minting Functionality", 
                    "Should allow owner to mint tokens", "failed", 0, error);
                throw error;
            }
        });

        it("Should allow owner to mint multiple times", async () => {
            try {
                await token.mint(addr1.address, MINT_AMOUNT);
                await token.mint(addr1.address, MINT_AMOUNT);
                
                expect(await token.balanceOf(addr1.address)).to.equal(MINT_AMOUNT * BigInt(2));
                expect(await token.totalSupply()).to.equal(MINT_AMOUNT * BigInt(2));

                TestLogger.logTestResult("NBKToken", "Minting Functionality", 
                    "Should allow owner to mint multiple times", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Minting Functionality", 
                    "Should allow owner to mint multiple times", "failed", 0, error);
                throw error;
            }
        });

        it("Should not allow non-owner to mint", async () => {
            try {
                await expect(
                    token.connect(addr1).mint(addr2.address, MINT_AMOUNT)
                ).to.be.revertedWithCustomError(token, "OwnableUnauthorizedAccount");

                TestLogger.logTestResult("NBKToken", "Minting Functionality", 
                    "Should not allow non-owner to mint", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Minting Functionality", 
                    "Should not allow non-owner to mint", "failed", 0, error);
                throw error;
            }
        });

        it("Should not allow minting to zero address", async () => {
            try {
                await expect(
                    token.mint(ZERO_ADDRESS, MINT_AMOUNT)
                ).to.be.revertedWithCustomError(token,"ERC20InvalidReceiver");

                TestLogger.logTestResult("NBKToken", "Minting Functionality", 
                    "Should not allow minting to zero address", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Minting Functionality", 
                    "Should not allow minting to zero address", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle minting of maximum possible amount", async () => {
            try {
                const maxAmount = MaxUint256;
                await token.mint(addr1.address, maxAmount);
                expect(await token.balanceOf(addr1.address)).to.equal(maxAmount);

                TestLogger.logTestResult("NBKToken", "Minting Functionality", 
                    "Should handle minting of maximum possible amount", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Minting Functionality", 
                    "Should handle minting of maximum possible amount", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Burning Functionality", () => {
        beforeEach(async () => {
            await token.mint(addr1.address, MINT_AMOUNT);
        });

        it("Should allow burning tokens", async () => {
            try {
                const burnAmount = ethers.parseEther("500");
                const initialSupply = await token.totalSupply();
                const initialBalance = await token.balanceOf(addr1.address);
                
                await token.connect(addr1).burn(burnAmount);
                
                expect(await token.balanceOf(addr1.address)).to.equal(initialBalance - burnAmount);
                expect(await token.totalSupply()).to.equal(initialSupply - burnAmount);

                // Verificar emisión del evento Transfer
                await expect(token.connect(addr1).burn(burnAmount))
                    .to.emit(token, "Transfer")
                    .withArgs(addr1.address, ZERO_ADDRESS, burnAmount);

                TestLogger.logTestResult("NBKToken", "Burning Functionality", 
                    "Should allow burning tokens", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Burning Functionality", 
                    "Should allow burning tokens", "failed", 0, error);
                throw error;
            }
        });

        it("Should allow burning entire balance", async () => {
            try {
                await token.connect(addr1).burn(MINT_AMOUNT);
                expect(await token.balanceOf(addr1.address)).to.equal(0);
                
                TestLogger.logTestResult("NBKToken", "Burning Functionality", 
                    "Should allow burning entire balance", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Burning Functionality", 
                    "Should allow burning entire balance", "failed", 0, error);
                throw error;
            }
        });

        it("Should not allow burning more than balance", async () => {
            try {
                const excessAmount = MINT_AMOUNT + ethers.parseEther("1");
                await expect(
                    token.connect(addr1).burn(excessAmount)
                ).to.be.revertedWithCustomError(token,"ERC20InsufficientBalance");

                TestLogger.logTestResult("NBKToken", "Burning Functionality", 
                    "Should not allow burning more than balance", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Burning Functionality", 
                    "Should not allow burning more than balance", "failed", 0, error);
                throw error;
            }
        });

        it("Should not allow burning when balance is zero", async () => {
            try {
                await expect(
                    token.connect(addr2).burn(TRANSFER_AMOUNT)
                ).to.be.revertedWithCustomError(token,"ERC20InsufficientBalance");

                TestLogger.logTestResult("NBKToken", "Burning Functionality", 
                    "Should not allow burning when balance is zero", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Burning Functionality", 
                    "Should not allow burning when balance is zero", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Transfer Functionality", () => {
        beforeEach(async () => {
            await token.mint(addr1.address, MINT_AMOUNT);
        });

        it("Should transfer tokens between accounts", async () => {
            try {
                const initialSenderBalance = await token.balanceOf(addr1.address);
                const initialReceiverBalance = await token.balanceOf(addr2.address);
                
                await token.connect(addr1).transfer(addr2.address, TRANSFER_AMOUNT);
                
                expect(await token.balanceOf(addr2.address)).to.equal(initialReceiverBalance + TRANSFER_AMOUNT);
                expect(await token.balanceOf(addr1.address)).to.equal(initialSenderBalance - TRANSFER_AMOUNT);

                // Verificar emisión del evento Transfer
                await expect(token.connect(addr1).transfer(addr2.address, TRANSFER_AMOUNT))
                    .to.emit(token, "Transfer")
                    .withArgs(addr1.address, addr2.address, TRANSFER_AMOUNT);

                TestLogger.logTestResult("NBKToken", "Transfer Functionality", 
                    "Should transfer tokens between accounts", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Transfer Functionality", 
                    "Should transfer tokens between accounts", "failed", 0, error);
                throw error;
            }
        });

        it("Should allow transferring entire balance", async () => {
            try {
                await token.connect(addr1).transfer(addr2.address, MINT_AMOUNT);
                expect(await token.balanceOf(addr1.address)).to.equal(0);
                expect(await token.balanceOf(addr2.address)).to.equal(MINT_AMOUNT);

                TestLogger.logTestResult("NBKToken", "Transfer Functionality", 
                    "Should allow transferring entire balance", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Transfer Functionality", 
                    "Should allow transferring entire balance", "failed", 0, error);
                throw error;
            }
        });

        it("Should fail when transferring more than balance", async () => {
            try {
                const excessAmount = MINT_AMOUNT + ethers.parseEther("1");
                await expect(
                    token.connect(addr1).transfer(addr2.address, excessAmount)
                ).to.be.revertedWithCustomError(token,"ERC20InsufficientBalance");

                TestLogger.logTestResult("NBKToken", "Transfer Functionality", 
                    "Should fail when transferring more than balance", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Transfer Functionality", 
                    "Should fail when transferring more than balance", "failed", 0, error);
                throw error;
            }
        });

        it("Should fail when transferring to zero address", async () => {
            try {
                await expect(
                    token.connect(addr1).transfer(ZERO_ADDRESS, TRANSFER_AMOUNT)
                ).to.be.revertedWithCustomError(token,"ERC20InvalidReceiver");

                TestLogger.logTestResult("NBKToken", "Transfer Functionality", 
                    "Should fail when transferring to zero address", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Transfer Functionality", 
                    "Should fail when transferring to zero address", "failed", 0, error);
                throw error;
            }
        });

        it("Should fail when transferring with insufficient balance", async () => {
            try {
                await expect(
                    token.connect(addr2).transfer(addr1.address, TRANSFER_AMOUNT)
                ).to.be.revertedWithCustomError(token,"ERC20InsufficientBalance");

                TestLogger.logTestResult("NBKToken", "Transfer Functionality", 
                    "Should fail when transferring with insufficient balance", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Transfer Functionality", 
                    "Should fail when transferring with insufficient balance", "failed", 0, error);
                throw error;
            }
        });
    });

    describe("Allowance Functionality", () => {
        beforeEach(async () => {
            await token.mint(addr1.address, MINT_AMOUNT);
        });

        it("Should approve and allow transferFrom", async () => {
            try {
                await token.connect(addr1).approve(addr2.address, TRANSFER_AMOUNT);
                expect(await token.allowance(addr1.address, addr2.address)).to.equal(TRANSFER_AMOUNT);

                // Verificar emisión del evento Approval
                await expect(token.connect(addr1).approve(addr2.address, TRANSFER_AMOUNT))
                    .to.emit(token, "Approval")
                    .withArgs(addr1.address, addr2.address, TRANSFER_AMOUNT);

                // Ejecutar transferFrom
                await token.connect(addr2).transferFrom(addr1.address, addr3.address, TRANSFER_AMOUNT);
                expect(await token.balanceOf(addr3.address)).to.equal(TRANSFER_AMOUNT);
                expect(await token.allowance(addr1.address, addr2.address)).to.equal(0);

                TestLogger.logTestResult("NBKToken", "Allowance Functionality", 
                    "Should approve and allow transferFrom", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Allowance Functionality", 
                    "Should approve and allow transferFrom", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle multiple approvals correctly", async () => {
            try {
                // Primera aprobación
                await token.connect(addr1).approve(addr2.address, TRANSFER_AMOUNT);
                expect(await token.allowance(addr1.address, addr2.address)).to.equal(TRANSFER_AMOUNT);

                // Segunda aprobación (debe sobrescribir la primera)
                const newAmount = TRANSFER_AMOUNT * BigInt(2);
                await token.connect(addr1).approve(addr2.address, newAmount);
                expect(await token.allowance(addr1.address, addr2.address)).to.equal(newAmount);

                TestLogger.logTestResult("NBKToken", "Allowance Functionality", 
                    "Should handle multiple approvals correctly", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Allowance Functionality", 
                    "Should handle multiple approvals correctly", "failed", 0, error);
                throw error;
            }
        });

        it("Should fail when transferFrom amount exceeds allowance", async () => {
            try {
                await token.connect(addr1).approve(addr2.address, TRANSFER_AMOUNT);
                const excessAmount = TRANSFER_AMOUNT + ethers.parseEther("1");
                
                await expect(
                    token.connect(addr2).transferFrom(addr1.address, addr3.address, excessAmount)
                ).to.be.revertedWithCustomError(token,"ERC20InsufficientAllowance");

                TestLogger.logTestResult("NBKToken", "Allowance Functionality", 
                    "Should fail when transferFrom amount exceeds allowance", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Allowance Functionality", 
                    "Should fail when transferFrom amount exceeds allowance", "failed", 0, error);
                throw error;
            }
        });

        it("Should fail when transferFrom amount exceeds balance", async () => {
            try {
                const excessAmount = MINT_AMOUNT + ethers.parseEther("1");
                await token.connect(addr1).approve(addr2.address, excessAmount);
                
                await expect(
                    token.connect(addr2).transferFrom(addr1.address, addr3.address, excessAmount)
                ).to.be.revertedWithCustomError(token,"ERC20InsufficientBalance");

                TestLogger.logTestResult("NBKToken", "Allowance Functionality", 
                    "Should fail when transferFrom amount exceeds balance", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Allowance Functionality", 
                    "Should fail when transferFrom amount exceeds balance", "failed", 0, error);
                throw error;
            }
        });

        it("Should handle approval to zero address", async () => {
            try {
                await expect(
                    token.connect(addr1).approve(ZERO_ADDRESS, TRANSFER_AMOUNT)
                ).to.be.revertedWithCustomError(token,"ERC20InvalidSpender");

                TestLogger.logTestResult("NBKToken", "Allowance Functionality", 
                    "Should handle approval to zero address", "passed", 0);
            } catch (error) {
                TestLogger.logTestResult("NBKToken", "Allowance Functionality", 
                    "Should handle approval to zero address", "failed", 0, error);
                throw error;
            }
  });
});

    after(async () => {
        const summary = TestLogger.getSummary();
        TestLogger.writeSummary(summary);
    });
});