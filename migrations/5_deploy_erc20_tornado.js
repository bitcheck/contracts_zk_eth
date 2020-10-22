/* global artifacts */
require('dotenv').config({ path: '../.env' })
const ERC20Shaker = artifacts.require('ERC20Shaker')
const ERC20ShakerV2 = artifacts.require('ERC20ShakerV2')
const Verifier = artifacts.require('Verifier')
const hasherContract = artifacts.require('Hasher')
const ERC20Mock = artifacts.require('ERC20Mock')


module.exports = function(deployer, network, accounts) {
  return deployer.then(async () => {
    const { MERKLE_TREE_HEIGHT, ERC20_TOKEN, TOKEN_AMOUNT, FEE_ADDRESS, VERSION } = process.env
    console.log("默克尔树高度", MERKLE_TREE_HEIGHT, "ERC20数量", TOKEN_AMOUNT / 1e18)
    const verifier = await Verifier.deployed()
    const hasherInstance = await hasherContract.deployed()
    await ERC20Shaker.link(hasherContract, hasherInstance.address)
    let token = ERC20_TOKEN
    if(token === '') {
      const tokenInstance = await deployer.deploy(ERC20Mock)
      token = tokenInstance.address
    }
    let shaker;
    if(VERSION == 'V1') shaker = await deployer.deploy(
      ERC20Shaker,
      verifier.address,
      TOKEN_AMOUNT,
      MERKLE_TREE_HEIGHT,
      accounts[0],
      FEE_ADDRESS,
      token,
    ) 
    else shaker = await deployer.deploy(
      ERC20ShakerV2,
      verifier.address,
      TOKEN_AMOUNT,
      accounts[0],
      FEE_ADDRESS,
      token,
    )
    console.log('ERC20Shaker\'s address ', shaker.address)
  })
}
