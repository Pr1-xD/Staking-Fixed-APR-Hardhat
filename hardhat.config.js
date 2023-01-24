require('dotenv').config();
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
    },
    polygon_mumbai: {
      url: "https://rpc-mumbai.maticvigil.com",
      accounts: [process.env.PRIVATE_KEY]
    }
  },
  etherscan: {
    apiKey: process.env.POLYGONSCAN_API_KEY
  },
  solidity: {
    compilers: [
      {
        version:"0.8.13",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          }
      }},
      {
        version:"0.7.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          }
      }
      }
  ]
},
}

