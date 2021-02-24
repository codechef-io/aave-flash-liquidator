require('dotenv').config()
require("@nomiclabs/hardhat-waffle");

const ALCHEMY_API_KEY = process.env.ALCHEMY_API_KEY
const MNEMONIC_PATH = "m/44'/60'/0'/0";
const MAINNET_MNEMONIC = process.env.MAINNET_MNEMONIC
const DEFAULT_BLOCK_GAS_LIMIT = 10000000;
const DEFAULT_GAS_PRICE = 52000000000;
const DEFAULT_GAS_MUL = 5;

const getCommonNetworkConfig = (networkName, networkId) => {
    return {
        url: 'https://eth-mainnet.alchemyapi.io/v2/' + ALCHEMY_API_KEY,
        hardfork: 'istanbul',
        blockGasLimit: DEFAULT_BLOCK_GAS_LIMIT,
        gasMultiplier: DEFAULT_GAS_MUL,
        gasPrice: DEFAULT_GAS_PRICE,
        chainId: networkId,
        accounts: {
            mnemonic: MAINNET_MNEMONIC,
            path: MNEMONIC_PATH,
            initialIndex: 0,
            count: 20,
        },
    };
};

module.exports = {
    solidity: "0.6.6",
    networks: {
        main: getCommonNetworkConfig('main', 1),
    },
    mocha: {
        timeout: 120000
    }
};