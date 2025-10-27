import pkg from "hardhat"

const { ethers } = pkg

const CONTRACT_ADDRESS = "0x00Ea3f7594f3C5929BE57A67155e189aA933Eb96"

async function main() {
    const [deployer] = await ethers.getSigners()
    console.log("Using account:", deployer.address)

    const RockPaperScissors = await ethers.getContractFactory("RockPaperScissors");
    const contract = RockPaperScissors.attach(CONTRACT_ADDRESS)
    console.log(`Connected to contract at ${CONTRACT_ADDRESS}`);

    // await fund(contract, deployer)

    await play(contract, deployer)

    const stats = await contract.getPlayerStats(deployer.address);
    console.log("Player stats:", stats);
}

async function fund(contract, deployer) {
    const depositTx = await contract.connect(deployer).depositFunds({
        value: ethers.parseEther("0.1")
    })

    await depositTx.wait()
    console.log("Funds deposited")
}

async function play(contract, deployer) {
    const betAmount = ethers.parseEther("0.01")
    const playerChoice = 1;
    const playTx = await contract.connect(deployer).playAgainstHouse(playerChoice, {
        value: betAmount
    })
    const receipt = await playTx.wait();
    console.log("Game started!")
    console.log("Tx hash:", receipt.hash)
}

main().catch(console.error);