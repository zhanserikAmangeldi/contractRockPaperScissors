import pkg from "hardhat"
const { ethers } = pkg

const CONTRACT_ADDRESS = "0x2d6918a3fFEc3E09c633c11b50b62b8D2Acd23Ba"
const USDT_ADDRESS = "0x64544969ed7EBf5f083679233325356EbE738930"

async function main() {
    const [deployer, player2] = await ethers.getSigners();
    
    console.log("Using accounts:");
    console.log(" Player1:", deployer.address);
    console.log(" Player2:", player2.address);

    const RockPaperScissors = await ethers.getContractFactory("RockPaperScissors");
    const contract = RockPaperScissors.attach(CONTRACT_ADDRESS);
    console.log(`Connected to contract at ${CONTRACT_ADDRESS}\n`);

    const tokenABI = [
        "function approve(address spender, uint256 amount) external returns (bool)",
        "function balanceOf(address account) external view returns (uint256)",
        "function decimals() external view returns (uint8)",
        "function symbol() external view returns (string)"
    ];
    
    const usdt = new ethers.Contract(USDT_ADDRESS, tokenABI, deployer);
    const usdtSymbol = await usdt.symbol();
    const usdtDecimals = await usdt.decimals();
    
    console.log(`Token: ${usdtSymbol}`);
    console.log(`Token Address: ${USDT_ADDRESS}`);
    console.log(`Decimals: ${usdtDecimals}\n`);
    
        
    // 1. Setup USDT in contract (run this first)
    // await setupToken(contract, deployer, usdt);
    
    // 2. Fund contract with USDT
    // await fundContractWithTokens(contract, deployer, usdt);
    
    // 3. Test single player with USDT
    await playSinglePlayerToken(contract, deployer, usdt, USDT_ADDRESS);
    
    // 4. Test multiplayer with USDT
    // await playMultiplayerToken(contract, deployer, player2, usdt, USDT_ADDRESS);
    
    await viewStats(contract, deployer, player2, USDT_ADDRESS);
    await viewTokenInfo(contract, USDT_ADDRESS);
}

async function setupToken(contract, owner, token) {

    const tokenAddress = await token.getAddress();
    const tokenSymbol = await token.symbol();
    const tokenDecimals = await token.decimals();
    
    const tokenBetAmount = ethers.parseUnits("0.01", tokenDecimals);
    
    console.log(`Token: ${tokenSymbol}`);
    console.log(`Address: ${tokenAddress}`);
    console.log(`Decimals: ${tokenDecimals}`);
    console.log(`Bet Amount: ${ethers.formatUnits(tokenBetAmount, tokenDecimals)} ${tokenSymbol}`);
    
    const addTx = await contract.connect(owner).addToken(
        tokenAddress,
        tokenBetAmount
    );
    await addTx.wait();
    console.log(`Token added to contract successfully!`);
    
    const isSupported = await contract.isTokenSupported(tokenAddress);
    console.log(`Token is supported: ${isSupported}`);
    
    const betAmount = await contract.getTokenBetAmount(tokenAddress);
    console.log(`Contract bet amount: ${ethers.formatUnits(betAmount, tokenDecimals)} ${tokenSymbol}`);
}

async function fundContractWithTokens(contract, owner, token) {

    const tokenAddress = await token.getAddress();
    const tokenDecimals = await token.decimals();
    const tokenSymbol = await token.symbol();
    
    const tokenAmount = ethers.parseUnits("5", tokenDecimals);
    console.log(`Depositing: ${ethers.formatUnits(tokenAmount, tokenDecimals)} ${tokenSymbol}`);
    
    const approveTx = await token.connect(owner).approve(
        await contract.getAddress(),
        tokenAmount
    );
    await approveTx.wait();
    
    const depositTx = await contract.connect(owner).depositTokens(
        tokenAddress,
        tokenAmount
    );
    await depositTx.wait();
    console.log(`Deposited ${ethers.formatUnits(tokenAmount, tokenDecimals)} ${tokenSymbol}`);
    
    const contractBalance = await contract.getContractTokenBalance(tokenAddress);
    console.log(`Contract ${tokenSymbol} balance: ${ethers.formatUnits(contractBalance, tokenDecimals)}`);
}

async function playSinglePlayerToken(contract, player, token, tokenAddress) {
    
    const tokenDecimals = await token.decimals();
    const tokenSymbol = await token.symbol();
    const betAmount = await contract.getTokenBetAmount(tokenAddress);
    
    console.log(`Playing with ${ethers.formatUnits(betAmount, tokenDecimals)} ${tokenSymbol}`);
    
    const playerBalance = await token.balanceOf(player.address);
    console.log(`Your ${tokenSymbol} balance: ${ethers.formatUnits(playerBalance, tokenDecimals)}`);
    
    if (playerBalance < betAmount) {
        console.log(`Insufficient balance. Need ${ethers.formatUnits(betAmount, tokenDecimals)} ${tokenSymbol}`);
        return;
    }
    
    const approveTx = await token.connect(player).approve(
        await contract.getAddress(),
        betAmount
    );
    await approveTx.wait();
    console.log(`Approved tokens`);
    
    const playerChoice = 1;
    const choiceName = playerChoice === 1 ? "Rock" : playerChoice === 2 ? "Paper" : "Scissors";
    console.log(`Your choice: ${choiceName}`);
    
    const playTx = await contract.connect(player).playAgainstHouseWithToken(
        playerChoice,
        tokenAddress
    );
    const receipt = await playTx.wait();
    
    console.log(`Game started!`);
    console.log(`Tx hash: ${receipt.hash}`);
    
    const event = receipt.logs
        .map((log) => {
            try {
                return contract.interface.parseLog(log);
            } catch {
                return null;
            }
        })
        .find((e) => e && e.name === "SingleGameStarted");
    
    if (event) {
        console.log(`Request ID: ${event.args.requestId}`);
        console.log(`Is Token Game: ${event.args.isTokenGame}`);
        console.log(`Token: ${event.args.token}`);
    }
}

async function playMultiplayerToken(contract, player1, player2, token, tokenAddress) {
    
    const tokenDecimals = await token.decimals();
    const tokenSymbol = await token.symbol();
    const betAmount = await contract.getTokenBetAmount(tokenAddress);
    
    console.log(`Playing with ${ethers.formatUnits(betAmount, tokenDecimals)} ${tokenSymbol}`);
    
    console.log("\nPlayer1 creating game...");
    const approve1Tx = await token.connect(player1).approve(
        await contract.getAddress(),
        betAmount
    );
    await approve1Tx.wait();
    console.log(`Player1 approved tokens`);
    
    const createTx = await contract.connect(player1).createMultiplayerGameWithToken(tokenAddress);
    const createReceipt = await createTx.wait();
    
    const createEvent = createReceipt.logs
        .map((log) => {
            try {
                return contract.interface.parseLog(log);
            } catch {
                return null;
            }
        })
        .find((e) => e && e.name === "MultiplayerGameCreated");
    
    const gameId = createEvent ? createEvent.args.gameId : null;
    console.log(`Game created (ID: ${gameId})`);
    
    console.log("\nPlayer2 joining game...");
    const approve2Tx = await token.connect(player2).approve(
        await contract.getAddress(),
        betAmount
    );
    await approve2Tx.wait();
    console.log(`Player2 approved tokens`);
    
    const joinTx = await contract.connect(player2).joinMultiplayerGameWithToken(gameId);
    await joinTx.wait();
    console.log(`Player2 joined the game`);
    
    const choices = [1, 2, 3];
    const choice1 = choices[Math.floor(Math.random() * choices.length)];
    const choice2 = choices[Math.floor(Math.random() * choices.length)];
    const choiceName = (c) => c === 1 ? "Rock" : c === 2 ? "Paper" : "Scissors";
    
    console.log(`Player1 chooses: ${choiceName(choice1)}`);
    console.log(`Player2 chooses: ${choiceName(choice2)}`);
    
    const move1 = await contract.connect(player1).makeMove(gameId, choice1);
    await move1.wait();
    
    const move2 = await contract.connect(player2).makeMove(gameId, choice2);
    const receipt2 = await move2.wait();
    
    const resultEvent = receipt2.logs
        .map((log) => {
            try {
                return contract.interface.parseLog(log);
            } catch {
                return null;
            }
        })
        .find((e) => e && e.name === "MultiplayerGameResult");
    
    if (resultEvent) {
        const { winner, payout } = resultEvent.args;
        console.log(`GAME RESULT:`);
        console.log(`   Winner: ${winner}`);
        console.log(`   Payout: ${ethers.formatUnits(payout, tokenDecimals)} ${tokenSymbol}`);
    } else {
        console.log(`GAME RESULT: Draw (both players refunded)`);
    }
}

async function viewStats(contract, player1, player2, tokenAddress) {

    const token = new ethers.Contract(tokenAddress, [
        "function decimals() external view returns (uint8)",
        "function symbol() external view returns (string)"
    ], player1);
    const decimals = await token.decimals();
    const symbol = await token.symbol();
    
    const stats1 = await contract.getPlayerStats(player1.address);
    console.log(`Player1 (${player1.address}):`);
    console.log(`  Wins: ${stats1[0]}`);
    console.log(`  Losses: ${stats1[1]}`);
    console.log(`  Total ETH Profits: ${ethers.formatEther(stats1[2])} ETH`);
    
    const tokenProfits1 = await contract.getPlayerTokenProfits(player1.address, tokenAddress);
    console.log(`  Total ${symbol} Profits: ${ethers.formatUnits(tokenProfits1, decimals)} ${symbol}`);
    
    const stats2 = await contract.getPlayerStats(player2.address);
    console.log(`Player2 (${player2.address}):`);
    console.log(`  Wins: ${stats2[0]}`);
    console.log(`  Losses: ${stats2[1]}`);
    console.log(`  Total ETH Profits: ${ethers.formatEther(stats2[2])} ETH`);
    
    const tokenProfits2 = await contract.getPlayerTokenProfits(player2.address, tokenAddress);
    console.log(`  Total ${symbol} Profits: ${ethers.formatUnits(tokenProfits2, decimals)} ${symbol}`);
}

async function viewTokenInfo(contract, tokenAddress) {

    const isSupported = await contract.isTokenSupported(tokenAddress);
    console.log(`Token Address: ${tokenAddress}`);
    console.log(`Is Supported: ${isSupported}`);
    
    if (isSupported) {
        const betAmount = await contract.getTokenBetAmount(tokenAddress);
        const token = new ethers.Contract(tokenAddress, [
            "function decimals() external view returns (uint8)",
            "function symbol() external view returns (string)"
        ], await ethers.provider.getSigner());
        const decimals = await token.decimals();
        const symbol = await token.symbol();
        
        console.log(`Token Symbol: ${symbol}`);
        console.log(`Bet Amount: ${ethers.formatUnits(betAmount, decimals)} ${symbol}`);
        
        const contractBalance = await contract.getContractTokenBalance(tokenAddress);
        console.log(`Contract Balance: ${ethers.formatUnits(contractBalance, decimals)} ${symbol}`);
    }
    
    const allTokens = await contract.getSupportedTokens();
    console.log(`\nTotal Supported Tokens: ${allTokens.length}`);
    if (allTokens.length > 0) {
        console.log(`Supported Token Addresses:`);
        allTokens.forEach((addr, i) => {
            console.log(`  ${i + 1}. ${addr}`);
        });
    }
}

main().catch(console.error);
