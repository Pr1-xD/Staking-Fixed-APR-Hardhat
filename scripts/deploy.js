// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {
 

  const StakingContract = await hre.ethers.getContractFactory("StakingContract");
  const stakingContract = await StakingContract.deploy("0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0",3,"0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0",500,500);

  await stakingContract.deployed();

  console.log(
    ` deployed to ${stakingContract.address}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
