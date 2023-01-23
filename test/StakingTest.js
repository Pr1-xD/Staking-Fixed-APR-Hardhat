const { expect } = require("chai");
const hre = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("Staking contract", function () {
  // We define a fixture to reuse the same setup in every test. We use
  // loadFixture to run this setup once, snapshot that state, and reset Hardhat
  // Network to that snapshot in every test.
  async function deployContractsFixture() {
    // Get the ContractFactory and Signers here.
    const TokenContract = await hre.ethers.getContractFactory("ERC20");
    const StakingContract = await hre.ethers.getContractFactory("StakingContract");
    const [owner, addr1, addr2] = await ethers.getSigners();

    // To deploy our contract, we just have to call Token.deploy() and await
    // its deployed() method, which happens once its transaction has been
    // mined.
    const tokenContract = await TokenContract.deploy("ST","ST");
    const stakingContract = await StakingContract.deploy(tokenContract.address,3,addr1.address,500,500);
    

    

    // Fixtures can return anything you consider useful for your tests
    return {  tokenContract, stakingContract, owner, addr1, addr2 };
  }

  describe("Deployment", function () {

    it("Should set the right owner", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      expect(await stakingContract.owner()).to.equal(owner.address);
    });

    it("Should set the withdrawal fee", async function () {
      const { tokenContract,stakingContract, owner,addr1 } = await loadFixture(deployContractsFixture);
      stakingContract.setWithdrawalFee(100)
      expect(await stakingContract.withdrawalFee()).to.equal(100);
    });


  });

});