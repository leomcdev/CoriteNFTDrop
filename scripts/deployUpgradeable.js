require("dotenv").config();
const path = require("path");

const { ethers, upgrades } = require("hardhat");

async function main() {
  const [owner] = await ethers.getSigners();
  await ethers.getSigners();

  const Asset = await ethers.getContractFactory("Asset");
  const asset = await Asset.deploy();
  await asset.deployed();
  console.log("asset Contract deployed to:", asset.address);

  const RWAT = await ethers.getContractFactory("RWAT");
  const rwat = await upgrades.deployProxy(
    RWAT,
    [owner.address, asset.address],
    { initializer: "initialize" }
  );
  await rwat.deployed();
  console.log("proxy Contract deployed to:", rwat.address);

  console.log("owner address", owner.address);
  await rwat.grantRole(
    ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ADMIN")),
    owner.address
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

// npx hardhat run scripts/deployUpgradeable.js --network BSCTestnet
// npx hardhat verify --network BSCTestnet
