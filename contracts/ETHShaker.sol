/**
 *  $$$$$$\  $$\                 $$\                           
 * $$  __$$\ $$ |                $$ |                          
 * $$ /  \__|$$$$$$$\   $$$$$$\  $$ |  $$\  $$$$$$\   $$$$$$\  
 * \$$$$$$\  $$  __$$\  \____$$\ $$ | $$  |$$  __$$\ $$  __$$\ 
 *  \____$$\ $$ |  $$ | $$$$$$$ |$$$$$$  / $$$$$$$$ |$$ |  \__|
 * $$\   $$ |$$ |  $$ |$$  __$$ |$$  _$$<  $$   ____|$$ |      
 * \$$$$$$  |$$ |  $$ |\$$$$$$$ |$$ | \$$\ \$$$$$$$\ $$ |      
 *  \______/ \__|  \__| \_______|\__|  \__| \_______|\__|
 * $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
 * ____________________________________________________________
*/

pragma solidity 0.5.17;
// pragma experimental ABIEncoderV2;

import "./Shaker.sol";

contract ETHShaker is Shaker {
  constructor(
    IVerifier _verifier,
    uint256 _denomination,
    uint32 _merkleTreeHeight,
    address _operator,
    address _commonWithdrawAddress
  ) Shaker(_verifier, _denomination, _merkleTreeHeight, _operator, _commonWithdrawAddress) public {
  }

  function _processDeposit(uint256 _amount) internal {
    require(msg.value == denomination, "Please send `mixDenomination` ETH along with transaction");
  }

  function _processWithdraw(address payable _recipient, address _relayer, uint256 _fee, uint256 _refund) internal {
    // sanity checks
    require(msg.value == 0, "Message value is supposed to be zero for ETH instance");
    require(_refund == 0, "Refund value is supposed to be zero for ETH instance");

    (bool success, ) = _recipient.call.value(denomination - _fee)("");
    require(success, "payment to _recipient did not go thru");
    if (_fee > 0) {
      (success, ) = _relayer.call.value(_fee)("");
      require(success, "payment to _relayer did not go thru");
    }
  }
}
