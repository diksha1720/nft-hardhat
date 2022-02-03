
let { networkConfig } = require('../helper-hardhat-config')
const fs = require('fs')
module.exports = async ({
    getNamedAccounts, deployments, getChainId
}) => {
    const { deploy, get, log } = deployments
    const { deployer } = await getNamedAccounts()
    const chainId = await getChainId()

    let linkTokenAddress, vrfCoordinatorAddress

    if (chainId == 31337) {
        let linkToken = await get('LinkToken')
        linkTokenAddress = linkToken.address
        let vrfCoordinatorMock = await get('VRFCoordinatorMock')
        vrfCoordinatorAddress = vrfCoordinatorMock.address
    } else {
        linkTokenAddress = networkConfig[chainId]['linkToken']
        vrfCoordinatorAddress = networkConfig[chainId]['vrfcoordinator']

    }
    const keyhash = networkConfig[chainId]['keyhash']
    const fee = networkConfig[chainId]['fee']
    let args = [vrfCoordinatorAddress, linkTokenAddress, keyhash, fee]
    log("---------------------------------")
    const RandomSVG = await deploy('RandomSVG', {
        from: deployer,
        args: args,
        log: true
    })
    log("You have deployed your NFT conntract")
    const networkName = networkConfig[chainId]['name']
    log(`Verify with : \n npx hardhat verify --network ${networkName} ${RandomSVG.address} ${args.toString().replace(/,/g, " ")}`)

    //fund with link
    const linkTokenContract = await ethers.getContractFactory("LinkToken")
    const accounts = await hre.ethers.getSigners()
    const signer = accounts[0]
    const linkToken = new ethers.Contract(linkTokenAddress, linkTokenContract.interface, signer)
    let fund_tx = await linkToken.transfer(RandomSVG.address, fee)
    await fund_tx.wait(1)

    //create an NFT
    const randomSVGContract = await ethers.getContractFactory("RandomSVG")
    const randomSVG = new ethers.Contract(RandomSVG.address, randomSVGContract.interface, signer)
    let create_tx = await randomSVG.create({ gasLimit: 300000, value: '100000000000000000' })
    let receipt = await create_tx.wait(1)
    let tokenId = receipt.events[3].topics[2]
    log(`You've made your NFT!! This is tokne number ${tokenId.toString()}`)
    log("Let's wait for the Chainlink node to respond...")
    if (chainId != 31337) {
        await new Promise(r => setTimeout(r, 180000))
        log(`Now let's finsih the mint...`)
        tx = await randomSVG.finishMint(tokenId, { gasLimit: 2000000 })
        await tx.wait(1)
        log(`You can view the tokenURI here ${await randomSVG.tokenURI(0)}`)
    } else {
        const VRFCoordinatorMock = await deployments.get('VRFCoordinatorMock')
        vrfCoordinator = await ethers.getContractAt('VRFCoordinatorMock', VRFCoordinatorMock.address, signer)
        let transactionResponse = await vrfCoordinator.callBackWithRandomness(receipt.logs[3].topics[1], 77777, randomSVG.address)
        await transactionResponse.wait(1)
        log(`Now let's finsih the mint...`)
        tx = await randomSVG.finishMint(tokenId, { gasLimit: 2000000 })
        await tx.wait(1)
        log(`You can view the tokenURI here ${await randomSVG.tokenURI(0)}`)
    }

}
module.exports.tags = ['all', 'rsvg']