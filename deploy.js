import pkg from "hardhat";
import dotenv from "dotenv";

dotenv.config();

const { ethers } = pkg;

async function main() {
  console.log("Deploying RockPaperScissors...");

  const RockPaperScissors = await ethers.getContractFactory("RockPaperScissors");

  const contract = await RockPaperScissors.deploy(
    ethers.parseEther(process.env.BET_AMOUNT),
    process.env.HOUSE_EDGE,
    process.env.SUBSCRIPTION_ID,
    process.env.VRF_COORDINATOR,
    process.env.KEY_HASH,
  );

  await contract.waitForDeployment();

  console.log(`Contract deployed at: ${await contract.getAddress()}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
