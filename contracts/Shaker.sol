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

import "./MerkleTreeWithHistory.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";

contract IVerifier {
    function verifyProof(bytes memory _proof, uint256[6] memory _input) public returns(bool);
}

contract Shaker is MerkleTreeWithHistory, ReentrancyGuard {
    using SafeMath for uint256;
    uint256 public totalAmount = 0; // Total amount of deposit
    uint256 public totalBalance = 0; // Total balance of deposit after Withdrawal
    IVerifier public verifier;

    // operator can update snark verification key
    // after the final trusted setup ceremony operator rights are supposed to be transferred to zero address
    address public operator;
    address public councilAddress;

    uint256 public denomination;
    mapping(bytes32 => bool) private nullifierHashes;
    mapping(bytes32 => bool) private commitments;
  
    mapping(bytes32 => uint256) private amounts;
    mapping(bytes32 => uint8) private orderStatuses;
    mapping(bytes32 => address payable) private recipients;
    mapping(bytes32 => uint256) private effectiveTimes;
    mapping(address => address) private relayers;
    
    // If the msg.sender(relayer) has not registered Withdrawal address, the fee will send to this address
    address public commonWithdrawAddress; 
    // If withdrawal is not throught relayer, use this common fee. Be care of decimal of token
    uint256 public commonFee = 0; 
    // If withdrawal is not throught relayer, use this rate. Total fee is: commoneFee + amount * commonFeeRate. 
    // If the desired rate is 4%, commonFeeRate should set to 400
    uint256 public commonFeeRate = 0; 
        
    struct LockReason {
        string  description;
        uint8   status; // 1- locked, 2- unlocked, 0- never happend
        uint256 datetime;
        address recipient;
        address relayer;
        address locker;
        uint256 refund;
    }
    mapping(bytes32 => LockReason) public lockReason;
    bytes32[] public lockCommitments;

    modifier onlyOperator {
        require(msg.sender == operator, "Only operator can call this function.");
        _;
    }

    modifier onlyRelayer {
        require(relayers[msg.sender] != address(0x0), "Only relayer can call this function.");
        _;
    }
    
    modifier onlyCouncil {
        require(msg.sender == councilAddress, "Only council account can call this function.");
        _;
    }
    
    event Deposit(bytes32 indexed commitment, uint32 leafIndex, uint256 timestamp, uint8 orderStatus, address recipient, uint256 effectiveTime);
    event Withdrawal(address to, bytes32 nullifierHash, address indexed relayer, uint256 fee, uint256 amount);

    /**
    @dev The constructor
    @param _verifier the address of SNARK verifier for this contract
    @param _denomination transfer amount for each deposit
    @param _merkleTreeHeight the height of deposits' Merkle Tree
    @param _operator operator address (see operator comment above)
    */
    constructor(
        IVerifier _verifier,
        uint256 _denomination,
        uint32 _merkleTreeHeight,
        address _operator,
        address _commonWithdrawAddress
    ) MerkleTreeWithHistory(_merkleTreeHeight) public {
        require(_denomination > 0, "denomination should be greater than 0");
        verifier = _verifier;
        operator = _operator;
        denomination = _denomination;
        commonWithdrawAddress = _commonWithdrawAddress;
    }

    /**
    @dev Deposit a set of amount and commitments
    @param _amounts, array of ERC20 amount
    @param _commitments, array of commitments
    @param _orderStatus, status of deposit, 0: cheque for bearer, 1: cheque for order
    @param _recipient, recipient address if cheque for order
    @param _effectiveTime, effective time of the Withdrawal
    */
    function depositERC20Batch(uint256[] calldata _amounts, bytes32[] calldata _commitments, uint8 _orderStatus, address payable _recipient, uint256 _effectiveTime) external payable nonReentrant {
        require(_orderStatus == 0 || _orderStatus == 1, "There are only 2 cheque status: 0 or 1");
        require(_recipient != address(0x0));
    
        for(uint256 i = 0; i < _amounts.length; i++) {
            _deposit(_amounts[i], _commitments[i], _orderStatus, _recipient, _effectiveTime);
        }
    }
  
    /**
    @dev Deposit funds into the contract. The caller must send (for ETH) or approve (for ERC20) value equal to or `denomination` of this instance.
    @param _amount the ERC20 amount
    @param _commitment the 2nd note commitment
    @param _orderStatus, status of deposit, 0: cheque for bearer, 1: cheque for order
    @param _recipient, recipient address if cheque for order, if orderStatus is 0, the _recipient is sender. Otherwise the _recipient is to order
    @param _effectiveTime, effective time of the Withdrawal
    */
    function _deposit(uint256 _amount, bytes32 _commitment, uint8 _orderStatus, address payable _recipient, uint256 _effectiveTime) internal {
        require(!commitments[_commitment], "The commitment has been submitted");

        uint32 insertedIndex = _insert(_commitment);
        _processDeposit(_amount);
        
        commitments[_commitment] = true;
        amounts[_commitment] = _amount;
        orderStatuses[_commitment] = _orderStatus;
        recipients[_commitment] = _orderStatus == 1 ? _recipient : msg.sender;
        effectiveTimes[_commitment] = _effectiveTime < block.timestamp ? block.timestamp : _effectiveTime;
        totalAmount = totalAmount.add(_amount);
        totalBalance = totalBalance.add(_amount);

        emit Deposit(_commitment, insertedIndex, block.timestamp, _orderStatus, _recipient, _effectiveTime);
    }


    /** @dev this function is defined in a child contract 
    @param _amount the ERC20 amount
    */
    function _processDeposit(uint256 _amount) internal;

    /**
    @dev Withdraw a deposit from the contract. `proof` is a zkSNARK proof data, and input is an array of circuit public inputs
    `input` array consists of:
      - merkle root of all deposits in the contract
      - hash of unique deposit nullifier to prevent double spends
      - the recipient of funds
      - optional fee that goes to the transaction sender (usually a relay)
    @param _fee, relayer decide the fee amount
    */
    function withdraw(
        bytes calldata _proof, 
        bytes32 _root, 
        bytes32 _nullifierHash, 
        address payable _recipient, 
        address payable _relayer, 
        uint256 _fee, 
        uint256 _refund, 
        bytes32 _commitment
    ) external payable nonReentrant {
        require(lockReason[_commitment].status != 1, 'This deposit was locked');
        require(!nullifierHashes[_nullifierHash], "The note has been already spent");
        require(isKnownRoot(_root), "Cannot find your merkle root"); // Make sure to use a recent one
        require((orderStatuses[_commitment] == 1 && _recipient == recipients[_commitment]) || orderStatuses[_commitment] == 0, "Recipient is not the original recipient" );
        require(amounts[_commitment] > 0, "No balance amount of this proof");
        uint256 refundAmount = _refund < amounts[_commitment] ? _refund : amounts[_commitment]; //Take all if _refund == 0
        require(refundAmount > 0, "Refund amount can not be zero");
        require(block.timestamp >= effectiveTimes[_commitment], "The deposit is locked until the effectiveTime");
        require(refundAmount >= _fee, "Refund amount should be more than fee");

        require(verifier.verifyProof(_proof, [
            uint256(_root), 
            uint256(_nullifierHash),
            uint256(_recipient), 
            uint256(_relayer), 
            _fee, 
            _refund
        ]), "Invalid withdraw proof");
    
        address payable recipient = orderStatuses[_commitment] == 1 ? recipients[_commitment] : _recipient;
        address withdrawAddress = relayers[msg.sender] == address(0x0) ? commonWithdrawAddress : relayers[msg.sender];
        uint256 _fee1 = getFee(refundAmount);
        require(_fee1 <= refundAmount, "The fee can not be more than refund amount");
        _fee = relayers[msg.sender] == address(0x0) ? _fee1 : _fee; // If not through relay, use commonFee
        _processWithdraw(recipient, withdrawAddress , _fee, refundAmount);
    
        amounts[_commitment] = amounts[_commitment].sub(refundAmount);
        totalAmount = totalAmount.sub(refundAmount);
        nullifierHashes[_nullifierHash] = amounts[_commitment] == 0 ? true : false;
        emit Withdrawal(_recipient, _nullifierHash, _relayer, _fee, refundAmount);
    }

    /** @dev this function is defined in a child contract */
    function _processWithdraw(address payable _recipient, address _relayer, uint256 _fee, uint256 _refund) internal;

    /** @dev this function is for cheque endorsement
     *  @param _proof, Proof of zkSNARK
     *  @param _root, root of merkle tree
     *  @param _newCommitment, new commitment from frontend
     *  @param _oldCommitment, old commitment which will be endorsed
     *  @param _nullifierHash, old nullifierHashe
     *  @param _orderStatus, old cheque order type, 0- to Bearer cheque, 1- to order cheque
     *  @param _amount, endorsed amount, the endorsement amount can be part of balance of old cheque
     *  @param _recipient, new recipient address, if orderStatus is 0, the _recipient is sender. Otherwise the _recipient is to order
     *  @param _relayer, relayer address
     *  @param _effectiveTime, new effectiveTime of note
    */
    function endorse(
        bytes   calldata _proof, 

        bytes32 _root, 
        bytes32 _nullifierHash, 
        address payable _recipient, // new recipient address
        address payable _relayer,   // Useless, but to keep proof same as withdraw
        uint8 _orderStatus, // should be fee, but params memory limited, use for orderStatus here
        uint256 _amount, 

        bytes32 _oldCommitment, 
        bytes32 _newCommitment, 
        // uint8   _orderStatus, 
        // address payable _newRecipient,
        uint256 _effectiveTime
    ) external payable nonReentrant {
        require(lockReason[_oldCommitment].status != 1, 'This deposit was locked');
        require(commitments[_oldCommitment], "Old commitment can not find");
        require(!commitments[_newCommitment], "The new commitment has been submitted");
        require(!nullifierHashes[_nullifierHash], "The note has been already spent");
        require(isKnownRoot(_root), "Cannot find your merkle root");
        require(amounts[_oldCommitment] > 0, "No balance amount of this proof");
        uint256 refundAmount = _amount < amounts[_oldCommitment] ? _amount : amounts[_oldCommitment]; //Take all if _refund == 0
        require(refundAmount > 0, "Refund amount can not be zero");
        require((orderStatuses[_oldCommitment] == 1 && msg.sender == recipients[_oldCommitment]) || orderStatuses[_oldCommitment] == 0, "Sender is not the original recipient" );

        require(verifier.verifyProof(_proof, [
            uint256(_root), 
            uint256(_nullifierHash), 
            uint256(_recipient),
            uint256(_relayer), 
            uint256(_orderStatus),
            _amount
        ]), "Invalid endorsement proof");
        
        // Initialize new leaf
        uint32 insertedIndex = _insert(_newCommitment);
        if(_effectiveTime > 0 && block.timestamp >= effectiveTimes[_oldCommitment]) effectiveTimes[_newCommitment] = _effectiveTime; // Effective
        else effectiveTimes[_newCommitment] = effectiveTimes[_oldCommitment]; // Not effective
        
        commitments[_newCommitment] = true;
        amounts[_newCommitment] = _amount;
        orderStatuses[_newCommitment] = _orderStatus;
        recipients[_newCommitment] = _orderStatus == 1 ? _recipient : msg.sender;
        
        // Set old leaf
        amounts[_oldCommitment] = amounts[_oldCommitment].sub(refundAmount);
        nullifierHashes[_nullifierHash] = amounts[_oldCommitment] == 0 ? true : false;
        
        emit Deposit(_newCommitment, insertedIndex, block.timestamp, _orderStatus, _recipient, _effectiveTime);
        emit Withdrawal(address(0x0), _nullifierHash, _relayer, 0, refundAmount);
    }
    
    /** @dev whether a note is already spent */
    function isSpent(bytes32 _nullifierHash) public view returns(bool) {
        return nullifierHashes[_nullifierHash];
    }

    /** @dev whether an array of notes is already spent */
    function isSpentArray(bytes32[] calldata _nullifierHashes) external view returns(bool[] memory spent) {
        spent = new bool[](_nullifierHashes.length);
        for(uint i = 0; i < _nullifierHashes.length; i++) {
            if (isSpent(_nullifierHashes[i])) {
                spent[i] = true;
            }
        }
    }

    /**
    @dev allow operator to update SNARK verification keys. This is needed to update keys after the final trusted setup ceremony is held.
    After that operator rights are supposed to be transferred to zero address
    */
    function updateVerifier(address _newVerifier) external onlyOperator {
        verifier = IVerifier(_newVerifier);
    }

    /** @dev operator can change his address */
    function updateOperator(address _newOperator) external onlyOperator {
        operator = _newOperator;
    }

    /** @dev update authority relayer */
    function updateRelayer(address _relayer, address _withdrawAddress) external onlyOperator {
        relayers[_relayer] = _withdrawAddress;
    }
    
    /** @dev get relayer Withdrawal address */
    function getRelayerWithdrawAddress() view external onlyRelayer returns(address) {
        return relayers[msg.sender];
    }
    
    /** @dev update commonWithdrawAddress */
    function updateCommonWithdrawAddress(address _commonWithdrawAddress) external onlyOperator {
        commonWithdrawAddress = _commonWithdrawAddress;
    }
    
    /** @dev set council address */
    function setCouncial(address _councilAddress) external onlyOperator {
        councilAddress = _councilAddress;
    }
    
    /** @dev lock commitment, this operation can be only called by note holder */
    function lockDeposit(
        bytes calldata _proof, 
        bytes32 _root, 
        bytes32 _nullifierHash, 
        address payable _recipient, 
        address payable _relayer, 
        uint256 _fee, 
        uint256 _refund,
        bytes32 _commitment,
        string calldata _description
    ) external payable nonReentrant returns(uint256) {
        require(verifier.verifyProof(_proof, [
            uint256(_root), 
            uint256(_nullifierHash),
            uint256(_recipient), 
            uint256(_relayer), 
            _fee, 
            _refund
        ]), "Invalid withdraw proof");
        
        lockReason[_commitment] = LockReason(
            _description, 
            1, 
            block.timestamp,
            _recipient,
            _relayer,
            msg.sender,
            _refund
        );
        lockCommitments.push(_commitment);
        return(lockCommitments.length - 1);
    }
    
    /** @dev unlock commitment by council */
    function unlockDeposit(uint256 id) external onlyCouncil {
        if(lockReason[lockCommitments[id]].status == 1) lockReason[lockCommitments[id]].status = 2;
    }
    
    /** @dev set common fee and fee rate */
    function updateCommonFee(uint256 _fee, uint256 _rate) external onlyOperator {
        commonFee = _fee;
        commonFeeRate = _rate;
    }
    
    /** @dev caculate the fee according to amount */
    function getFee(uint256 _amount) internal view returns(uint256) {
        return _amount * commonFeeRate / 10000 + commonFee;
    }
    
}
