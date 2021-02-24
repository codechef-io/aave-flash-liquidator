const {expect} = require("chai");

const {BN, expectEvent, expectRevert} = require('@openzeppelin/test-helpers');

let liquidator;
let owner;
let addr1;
let addr2;
let addrs;

beforeEach(async function () {
    // Get the ContractFactory and Signers here.
    AaveLiquidator = await ethers.getContractFactory("AaveLiquidator");
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

    liquidator = await AaveLiquidator.deploy();
});

describe("Todo", () => {

});