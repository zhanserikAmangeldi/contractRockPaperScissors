import pkg from "hardhat"

const { ethers } = pkg

const CONTRACT_ADDRESS = "0xFF2B816Fb5BB7a821D97A2B26a5f8a18aE21C8D5"
// 0x00Ea3f7594f3C5929BE57A67155e189aA933Eb96 only Oracle
// 0xFF2B816Fb5BB7a821D97A2B26a5f8a18aE21C8D5 Oracle + Multiplayer
// 

async function main() {
    const [deployer, player2] = await ethers.getSigners();
    console.log("Using accounts:");
    console.log("  Player1:", deployer.address);
    console.log("  Player2:", player2.address);

    const RockPaperScissors = await ethers.getContractFactory("RockPaperScissors");
    const contract = RockPaperScissors.attach(CONTRACT_ADDRESS)
    console.log(`Connected to contract at ${CONTRACT_ADDRESS}`);

    // await fund(contract, deployer)

    // await play(contract, deployer)

    await playMultiplayer(contract, deployer, player2);


    const stats1 = await contract.getPlayerStats(deployer.address);
    const stats2 = await contract.getPlayerStats(player2.address);
    console.log("Player1 stats:", stats1);
    console.log("Player2 stats:", stats2);
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

async function playMultiplayer(contract, player1, player2) {
    const betAmount = ethers.parseEther("0.01")
    
    const createTx = await contract.connect(player1).createMultiplayerGame({
        value: betAmount
    })
    const createReceipt = await createTx.wait()

    const event = createReceipt.logs
        .map((log) => {
            try {
                return contract.interface.parseLog(log)
            } catch {
                return null
            }
        })
        .find((e) => e && e.name === "MultiplayerGameCreated")
    
    const gameId = event ? event.args.gameId : null
    console.log(`Game created (ID: ${gameId})`)

    const joinTx = await contract.connect(player2).joinMultiplayerGame(gameId, {
        value: betAmount,
    });
    await joinTx.wait();
    console.log("Player2 joined the game")


    const choices = [1, 2, 3]; 
    const choice1 = choices[Math.floor(Math.random() * choices.length)];
    const choice2 = choices[Math.floor(Math.random() * choices.length)];

    const choiceName = (c) => c === 1 ? "Rock" : c === 2 ? "Paper" : "Scissors";

    console.log(`Player1 chooses ${choiceName(choice1)}`);
    console.log(`Player2 chooses ${choiceName(choice2)}`);


    const move1 = await contract.connect(player1).makeMove(gameId, choice1)
    await move1.wait()

    const move2 = await contract.connect(player2).makeMove(gameId, choice2)
    const receipt2 = await move2.wait()

    console.log("Moves submitted!")

    const resultEvent = receipt2.logs
        .map((log) => {
            try {
                return contract.interface.parseLog(log)
            } catch {
                return null;
            }
        })
        .find((e) => e && e.name === "MultiplayerGameResult")

    if (resultEvent) {
        const { gameId: id, winner, payout } = resultEvent.args
        console.log(`Game ${id} Winner: ${winner}`)
        console.log(`Payout: ${ethers.formatEther(payout)} ETH`)
    } else {
        console.log("No result event found (might be a draw)")
    }

}

main().catch(console.error);