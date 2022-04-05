import { ethers } from "hardhat";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import { BigNumber, Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  Helios__factory,
  XYKswapper__factory,
  Token__factory,
  HeliosERC1155__factory,
} from "../typechain-types";
import { Interface } from "ethers/lib/utils";

chai.use(solidity);
const { expect } = chai;

// Defaults to e18 using amount * 10^18
function getBigNumber(amount: number, decimals = 18) {
  return BigNumber.from(amount).mul(BigNumber.from(10).pow(decimals));
}

function formatBigNumber(arg: BigNumber) {
  return ethers.utils.formatUnits(arg);
}

describe("Helios", function () {
  let helios: Contract; // Helios contract instance
  let heliosInterface: Interface;
  let xyk: Contract; // XYK swapper contract instance
  let token0: Contract; // token0 contract instance
  let token1: Contract; // token1 contract instance
  let lpToken: Contract;

  let deployer: SignerWithAddress; // signerA
  let bob: SignerWithAddress; // signerB
  let carol: SignerWithAddress; // signerC
  let signers: SignerWithAddress[]; // signers array

  /// This should be moved to helper functions
  /// This SHOULDN'T be done. Pre-approving Helios by all signers.
  async function mintTokens(signer: SignerWithAddress, amount: number) {
    const tokenInstance0 = token0.connect(signer);
    const tokenInstance1 = token1.connect(signer);
    await tokenInstance0.mint(signer.address, getBigNumber(amount));
    await tokenInstance1.mint(signer.address, getBigNumber(amount));
    await tokenInstance0.approve(helios.address, getBigNumber(amount));
    await tokenInstance1.approve(helios.address, getBigNumber(amount));
  }

  /// Decode return values from non view/pure functions
  async function addedLiq(funcsig: string, data: any) {
    /// https://github.com/ChainSafe/web3.js/issues/3016#issuecomment-828274902
    data = heliosInterface.decodeFunctionResult(funcsig, "0x" + data.slice(10));
    if (funcsig == "addLiquidity") {
      return data[0].toString();
    } else {
      return data[1].toString();
    }
  }

  describe("Rewards testing", function () {
    before(async () => {
      [deployer, bob, carol] = await ethers.getSigners();
      signers = [deployer];

      const Helios = new Helios__factory(deployer);
      heliosInterface = new ethers.utils.Interface(Helios__factory.abi);
      helios = await Helios.deploy();
      await helios.deployed();

      const XYK = new XYKswapper__factory(deployer);
      xyk = await XYK.deploy();
      await xyk.deployed();

      const TokenFactory = new Token__factory(deployer);
      token0 = await TokenFactory.deploy("Wrapped Ether", "WETH");
      await token0.deployed();
      token1 = await TokenFactory.deploy("Dai Stablecoin", "DAI");
      await token1.deployed();

      await mintTokens(deployer, 10000);

      const tx = await helios.createPair(
        deployer.address,
        token0.address, // WETH
        token1.address, // DAI
        getBigNumber(10), // WETH
        getBigNumber(1000), // DAI
        xyk.address,
        0,
        "0x"
      );

      const liq = await addedLiq("createPair", tx.data);
      console.log("liquidity output from swapper: ", liq);
      const _bal: BigNumber = await helios.balanceOf(deployer.address, 1);
      console.log("LP balance after deploy: ", _bal.toString());
    });

    async function addLiq(id: number) {
      await helios.addLiquidity(
        deployer.address,
        id,
        getBigNumber(100),
        getBigNumber(100),
        "0x"
      );      
    }

    it("addLiquidity to id 1", async function () {
      await addLiq(1);
    });

    it("transfer lp token", async function () {
      await helios.safeTransferFrom(deployer.address, bob.address, 1, getBigNumber(10), '0x');
    });

    it("create reward vault", async function () {
      await helios.create(1, getBigNumber(1000));
    });

    it("deposit to reward vault", async function () {
      await helios.deposit(1, getBigNumber(70));
    });

    it("can't transfer locked", async function () {
      const balanceLocked = await helios.balanceLocked(deployer.address, 1);
      const balanceOf = await helios.balanceOf(deployer.address, 1);
      const maxTransfer = balanceOf.sub(balanceLocked);
      console.log("max allowed to transfer:", formatBigNumber(maxTransfer))
      await expect(helios.safeTransferFrom(deployer.address, bob.address, 1, maxTransfer.add(BigNumber.from(1)), '0x')).to.be.revertedWith("Locked");
    });

    it("withdraw from reward vault", async function () {
      await addLiq(1);
      await helios.withdraw(1, 1, getBigNumber(10), deployer.address);
    });

  });

  describe("Basic Testing", function () {
    beforeEach(async () => {
      [deployer, bob, carol] = await ethers.getSigners();
      signers = [deployer, bob, carol];

      const Helios = new Helios__factory(deployer);
      helios = await Helios.deploy();
      await helios.deployed();

      const XYK = new XYKswapper__factory(deployer);
      xyk = await XYK.deploy();
      await xyk.deployed();

      const TokenFactory = new Token__factory(deployer);
      token0 = await TokenFactory.deploy("Wrapped Ether", "WETH");
      await token0.deployed();
      token1 = await TokenFactory.deploy("Dai Stablecoin", "DAI");
      await token1.deployed();

      await mintTokens(deployer, 10000);

      await helios.createPair(
        deployer.address,
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
      await helios.swap(deployer.address, 1, token0.address, getBigNumber(10));
    });

    it("Should allow token1 swap using XYK", async function () {
      await helios.swap(deployer.address, 1, token1.address, getBigNumber(10));
    });

    it("Should allow LP mint using XYK", async function () {
      await helios.addLiquidity(
        deployer.address,
        1,
        getBigNumber(100),
        getBigNumber(100),
        "0x"
      );
    });

    it("Should allow LP burn using XYK", async function () {
      await helios.removeLiquidity(deployer.address, 1, getBigNumber(10));
    });
  });
});
