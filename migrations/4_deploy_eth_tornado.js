/* global artifacts */
require('dotenv').config({ path: '../.env' })
const ETHShaker = artifacts.require('ETHShaker')
const ETHShakerV2 = artifacts.require('ETHShakerV2')
const Verifier = artifacts.require('Verifier')
const hasherContract = artifacts.require('Hasher')


module.exports = function(deployer, network, accounts) {
  return deployer.then(async () => {
    const { MERKLE_TREE_HEIGHT, ETH_AMOUNT, FEE_ADDRESS, VERSION } = process.env
    console.log('版本', VERSION)
    console.log('默克尔树高度', MERKLE_TREE_HEIGHT, '以太坊数量', ETH_AMOUNT / 1e18)
    const verifier = await Verifier.deployed()
    console.log('Verifier address', verifier.address)
    const hasherInstance = await hasherContract.deployed()
    console.log('HasherInstance', hasherInstance.address)
    await ETHShaker.link(hasherContract, hasherInstance.address)
    let shaker
    if(VERSION == 'V1') shaker = await deployer.deploy(ETHShaker, verifier.address, ETH_AMOUNT, MERKLE_TREE_HEIGHT, accounts[0], FEE_ADDRESS)
    else if(VERSION == 'V2') shaker = await deployer.deploy(ETHShakerV2, verifier.address, ETH_AMOUNT, accounts[0], FEE_ADDRESS)
    console.log('ETHShaker\'s address ', shaker.address)
  })
}
