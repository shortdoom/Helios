import { ethers } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { BigNumber, Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import {
  Helios__factory,
  XYKswapper__factory,
  Token__factory,
} from "../typechain-types";

chai.use(solidity);
const { expect } = chai;

// Defaults to e18 using amount * 10^18
function getBigNumber(amount: number, decimals = 18) {
  return BigNumber.from(amount).mul(BigNumber.from(10).pow(decimals));
}

describe("Helios", function () {
  let helios: Contract; // Helios contract instance
  let xyk: Contract; // XYK swapper contract instance
  let token0: Contract; // token0 contract instance
  let token1: Contract; // token1 contract instance

  let alice: SignerWithAddress; // signerA
  let bob: SignerWithAddress; // signerB
  let carol: SignerWithAddress; // signerC
  let dave: SignerWithAddress;
  let robert: SignerWithAddress;
  let signers: SignerWithAddress[];

  async function mintTokens(signer: SignerWithAddress) {
    const tokenInstance0 = token0.connect(signer);
    const tokenInstance1 = token1.connect(signer);
    await tokenInstance0.mint(signer.address, getBigNumber(1000));
    await tokenInstance1.mint(signer.address, getBigNumber(1000));
    await tokenInstance0.approve(helios.address, getBigNumber(1000));
    await tokenInstance1.approve(helios.address, getBigNumber(1000));
  }

  beforeEach(async () => {
    [alice, bob, carol, dave, robert] = await ethers.getSigners();
    signers = [alice, bob, carol, dave, robert];

    const Helios = new Helios__factory(alice);
    helios = await Helios.deploy();
    await helios.deployed();

    const XYK = new XYKswapper__factory(alice);
    xyk = await XYK.deploy();
    await xyk.deployed();

    const TokenFactory = new Token__factory(alice);

    token0 = await TokenFactory.deploy("Wrapped Ether", "WETH");

    await token0.deployed();

    token1 = await TokenFactory.deploy("Dai Stablecoin", "DAI");
    await token1.deployed();

    for (let signer of signers) {
      await mintTokens(signer);
    }
  });

  it("Should allow LP creation", async function () {
    await helios.createPair(
      alice.address,
      token0.address,
      token1.address,
      getBigNumber(100),
      getBigNumber(100),
      xyk.address,
      0,
      "0x"
    );
  });

  it("Should allow token0 swap using XYK", async function () {
    await helios.createPair(
      alice.address,
      token0.address,
      token1.address,
      getBigNumber(100),
      getBigNumber(100),
      xyk.address,
      0,
      "0x"
    );

    await helios.swap(alice.address, 1, token0.address, getBigNumber(10));
  });

  it("Should allow token1 swap using XYK", async function () {
    await helios.createPair(
      alice.address,
      token0.address,
      token1.address,
      getBigNumber(100),
      getBigNumber(100),
      xyk.address,
      0,
      "0x"
    );

    await helios.swap(alice.address, 1, token1.address, getBigNumber(10));
  });

  it("Should allow LP mint using XYK", async function () {
    await helios.createPair(
      alice.address,
      token0.address,
      token1.address,
      getBigNumber(100),
      getBigNumber(100),
      xyk.address,
      0,
      "0x"
    );

    // helios.swap(
    //   alice.address,
    //   1,
    //   token0.address,
    //   getBigNumber(10)
    // )

    await helios.addLiquidity(
      alice.address,
      1,
      getBigNumber(100),
      getBigNumber(100),
      "0x"
    );
  });

  it("Should allow LP burn using XYK", async function () {
    await helios.createPair(
      alice.address,
      token0.address,
      token1.address,
      getBigNumber(100),
      getBigNumber(100),
      xyk.address,
      0,
      "0x"
    );

    await helios.swap(alice.address, 1, token0.address, getBigNumber(10));

    await helios.removeLiquidity(alice.address, 1, getBigNumber(10));
  });
});
