const { ethers, upgrades } = require("hardhat");

async function main() {
  const IronVestExtended = await ethers.getContractFactory("IronVestExtended");
  console.log("Deploying IronVest...");

  const ironVestExtended = await upgrades.deployProxy(IronVestExtended,["Iron Vest", "0xf97E03bc3498170D8195512A33E44602ed1A4D34", "0x8aAE6F836DdE559B873CcA5B6Dea937887776E9d", "0xf4Cf39303FB1E61A2a08D0E0C9c91823693B6Cb4"], {
    initializer: "initialize",
  });
  await ironVestExtended.deployed();

  console.log(`IronVest deployed to ${ironVestExtended.address}`);

  if (network.name == "hardhat") return;
  await ironVestExtended.deployTransaction.wait(21);
  console.log("Verifing...");
  await hre.run("verify:verify", {
    address: ironVestExtended.address,
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
