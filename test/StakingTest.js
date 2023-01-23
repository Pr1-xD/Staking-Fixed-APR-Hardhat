const { expect } = require("chai");
const hre = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

describe("Staking contract", function () {

  async function deployContractsFixture() {

    const TokenContract = await hre.ethers.getContractFactory("ERC20");
    const StakingContract = await hre.ethers.getContractFactory("StakingContract");
    const [owner, addr1, addr2] = await ethers.getSigners();

    const tokenContract = await TokenContract.deploy("ST","ST");
    const stakingContract = await StakingContract.deploy(tokenContract.address,1,addr1.address,500,5000);
    
    return {  tokenContract, stakingContract, owner, addr1, addr2 };
  }

  describe("Deployment", function () {

    it("Should set the right owner", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      expect(await stakingContract.owner()).to.equal(owner.address);
    });





  });

  describe("Deposit", function () {
    it("Should not allow deposit without starting staking", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      tokenContract._mint(owner.address,1000)
      tokenContract.approve(stakingContract.address,1000)
      await expect(stakingContract.deposit(1000)).to.be.revertedWith("Staking has not started");
    });

    it("Simple Deposit", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      await tokenContract._mint(owner.address,1000)
      await tokenContract.approve(stakingContract.address,1000)
      await stakingContract.startStaking();
      await stakingContract.deposit(1000);
      expect(await stakingContract.balanceOf(owner.address)).to.equal(1000);
    });

    it("Deposit more than max limit", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      await tokenContract._mint(owner.address,6000)
      await tokenContract.approve(stakingContract.address,6000)
      await stakingContract.startStaking();
      await expect(stakingContract.deposit(6000)).to.be.revertedWith("Exceeded maximum balance per user");
    });
  });

  describe("Withdrawal", function () {
    it("Simple Withdraw", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      await tokenContract._mint(owner.address,1000)
      await tokenContract.approve(stakingContract.address,1000)
      await stakingContract.startStaking();
      await stakingContract.deposit(1000);
      await stakingContract.withdraw(1000);
      expect(await stakingContract.balanceOf(owner.address)).to.equal(0);
    });

    it("Complex Withdraw", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      await tokenContract._mint(owner.address,4000)
      await tokenContract.approve(stakingContract.address,4000)
      await stakingContract.startStaking();
      await stakingContract.deposit(1000);
      await stakingContract.deposit(500);
      await stakingContract.deposit(2000);
      await stakingContract.withdraw(1700);
      expect(await tokenContract.balanceOf(owner.address)).to.equal(2200);
    });

    it("Checking withdrawal fee", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      await tokenContract._mint(owner.address,1000)
      await tokenContract.approve(stakingContract.address,1000)
      await stakingContract.startStaking();
      await stakingContract.deposit(1000);
      await stakingContract.setWithdrawalFee(100)
      await stakingContract.withdraw(1000);
      
      expect(await tokenContract.balanceOf(addr1.address)).to.equal(0.01*1000);
    });

    it("Checking withdrawal fee after lockup duration", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      await tokenContract._mint(owner.address,1000)
      await tokenContract.approve(stakingContract.address,1000)
      await stakingContract.startStaking();
      await stakingContract.deposit(1000);
      await stakingContract.setWithdrawalFee(100)
      await time.increase(3600*25);
      await stakingContract.withdraw(1000);
      
      expect(await tokenContract.balanceOf(addr1.address)).to.equal(0);
    });

    it("Checking withdrawal fee for fraction locked up deposit", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      await tokenContract._mint(owner.address,2000)
      await tokenContract.approve(stakingContract.address,2000)
      await stakingContract.startStaking();
      await stakingContract.deposit(1000);
      await stakingContract.setWithdrawalFee(100)
      await time.increase(3600*25);
      await stakingContract.deposit(1000);
      await stakingContract.withdraw(1500);
      
      expect(await tokenContract.balanceOf(addr1.address)).to.equal(0.01*500);
    });
  });

  describe("Rewards", function () {
   
    it("Checking claimable reward after 1 year", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      await tokenContract._mint(owner.address,1000)
      await tokenContract.approve(stakingContract.address,1000)
      await stakingContract.startStaking()
      await stakingContract.deposit(1000)
      await time.increase(3600*24*365)
      
      expect(await stakingContract.claimable(owner.address)).to.equal(1000*5/100);
    });

    it("Checking claimable reward per month", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      await tokenContract._mint(owner.address,1000)
      await tokenContract.approve(stakingContract.address,1000)
      await stakingContract.startStaking()
      await stakingContract.deposit(1000)
      await time.increase(3600*24*30)
      
      expect(await stakingContract.claimable(owner.address)).to.equal(Math.floor(1000*5/(100*12)));
    });

    it("Checking pending reward after withdraw", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      await tokenContract._mint(owner.address,1000)
      await tokenContract.approve(stakingContract.address,1000)
      await stakingContract.startStaking()
      await stakingContract.deposit(1000)
      await time.increase(3600*24*365)
      await stakingContract.withdrawAll()
      
      expect(await stakingContract.claimable(owner.address)).to.equal(1000*5/100);
    });
  });

  describe("Pausable", function () {
    it("Checking pause", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      await tokenContract._mint(owner.address,1000)
      await tokenContract.approve(stakingContract.address,1000)
      await stakingContract.startStaking()
      await stakingContract.deposit(1000)
      await stakingContract.pause()
      
      await expect(stakingContract.deposit(1000)).to.be.revertedWith("Pausable: paused");
    });

    it("Checking unpause", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      await tokenContract._mint(owner.address,2000)
      await tokenContract.approve(stakingContract.address,2000)
      await stakingContract.startStaking()
      await stakingContract.deposit(1000)
      await stakingContract.pause()
      await stakingContract.unpause()
      await stakingContract.deposit(1000)
      
      expect(await stakingContract.balanceOf(owner.address)).to.equal(2000)
    });
  });

  // describe("Pausable", function () {
   
  // });

});

//Add Comments
//Remove ;
//Change config
//add pk and ethkey