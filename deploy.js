const ethers = require("ethers")
const fs = require("fs")

async function main() {
    const provider = new ethers.JsonRpcProvider(process.env.RPC_URL)

    const account = new ethers.Wallet(process.env.PRIVATE_KEY, provider)

    const abi = fs.readFileSync("./contracts/RockPaperScissors_sol_RockPaperScissors.abi", "utf-8")
    const binary = fs.readFileSync("./contracts/RockPaperScissors_sol_RockPaperScissors.bin", "utf-8")

    const contractFactory = new ethers.ContractFactory(abi, binary, account)
    console.log("Deploying...")
    const contract = await contractFactory.deploy()

    console.log(contract)
    const deploymentReceipt = await contract.deploymentTransaction().wait(1)
    console.log(deploymentReceipt)
    console.log(`Contract address: ${contract.getAddress()}`)
}

main().then(() => process.exit(0)).catch((error) => {
    console.error(error)
    process.exit(1)
})
