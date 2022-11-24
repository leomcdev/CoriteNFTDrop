const { expect } = require("chai");
const help = require("./upgradeable_helper_functions.js");
const { ethers, upgrades } = require("hardhat");

CNR = "0x0cadb0d9e410072325d2acc00aab99eb795a8c86";

describe("Whitelist", function () {
  let owner, provider, investor, testToken;

  beforeEach(async function () {
    [owner, provider, investor] = await ethers.getSigners();
    // CNR = await help.setCNR();
    testToken = await help.setTestToken();

    const NFTDrop = await ethers.getContractFactory("NFTDrop");
    const nftdrop = await upgrades.deployProxy(
      NFTDrop,
      [owner.address, "tokenName", "tokenSymbol", CNR],
      {
        initializer: "initialize",
      }
    );
    await nftdrop.deployed();

    let ADMIN = await nftdrop.ADMIN();
    await nftdrop.grantRole(ADMIN, owner.address);
  });
  it("Should work", async function () {
    const NFTDrop = await ethers.getContractFactory("NFTDrop");
    const nftdrop = await upgrades.deployProxy(
      NFTDrop,
      [owner.address, "tokenName", "tokenSymbol", CNR],
      {
        initializer: "initialize",
      }
    );
    await nftdrop.deployed();

    let ADMIN = await nftdrop.ADMIN();
    await nftdrop.grantRole(ADMIN, owner.address);
    await nftdrop.grantRole(ADMIN, provider.address);

    await nftdrop.createNftDrop(1, 300, testToken.address);
    await nftdrop.mintNftDrop(1, 100);

    console.log("total assets in circulation", await nftdrop.getTotalMinted(1));
    await nftdrop.setWhitelisted([investor.address], true);
    console.log(investor.address);
    let units = [1000000000, 1000000001, 1000000002];

    console.log("current asset cap", await nftdrop.getNftDropCap(1));

    await nftdrop.updateNftDrop(1, 1000);
    console.log("asset cap after update", await nftdrop.getNftDropCap(1));

    await nftdrop.mintNftDrop(1, 150);

    console.log(
      "total assets in circulation after creating more",
      await nftdrop.getTotalMinted(1)
    );

    let obj = ethers.utils.defaultAbiCoder.encode(
      ["address", "address", "uint[]"],
      [investor.address, nftdrop.address, units]
    );
    const { prefix, v, r, s } = await createSignature(obj);

    await nftdrop.updateServer(provider.address);

    await nftdrop.connect(investor).buyShare(units, prefix, v, r, s);

    expect(await nftdrop.ownerOf(1000000002)).to.be.equal(investor.address);
    // console.log(await nftdrop.balanceOf(investor.address));

    console.log(
      "hash admin",
      ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ADMIN")),
      nftdrop.address
    );
  });

  async function createSignature(obj) {
    obj = ethers.utils.arrayify(obj);
    const prefix = ethers.utils.toUtf8Bytes(
      "\x19Ethereum Signed Message:\n" + obj.length
    );
    const serverSig = await provider.signMessage(obj);
    const sig = ethers.utils.splitSignature(serverSig);
    return { ...sig, prefix };
  }
});
