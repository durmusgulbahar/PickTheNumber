require("@nomicfoundation/hardhat-toolbox");

require('dotenv').config();
require("@nomiclabs/hardhat-etherscan");

const {API_KEY, PRIVATE_KEY} = process.env;
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.17",
  settings: {
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
  networks:{
    goerli:{
      url:API_KEY,
      accounts: [PRIVATE_KEY]
    }
  },
  etherscan:{
    apiKey: {
      goerli : "N31ZW5IWSUW315WPRDGJ95RMSBVKCWEJ95",
    }
  }
};
