const { ethers, upgrades } = require("hardhat");

async function main() {
  const IronVestPreCheck = await ethers.getContractFactory("IronVestPreCheck");
  console.log("Deploying IronVest...");

  const ironVestPreCheck = await upgrades.deployProxy(IronVestPreCheck);
  await ironVestPreCheck.deployed();

  console.log(`IronVest deployed to ${ironVestPreCheck.address}`);

  if (network.name == "hardhat") return;
  // await ironVestPreCheck.deployTransaction.wait(21);
  console.log("Verifing...");
  await hre.run("verify:verify", {
    address: IronVestPreCheck.address,
    constructorArguments: [],
  });
  console.log("Contract verified successfully !");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
