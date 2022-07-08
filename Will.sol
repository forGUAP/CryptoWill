// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./SafeMath.sol";
import "./Ownable.sol";


contract Will is Ownable {
  using SafeMath for uint;

  bool distributed; //Whether the contract has distributed
  uint waitingTime; //How long to wait before initiating distribution
  uint lastInteraction; //Last time contract was interacted with
  address[] heirs; //Address for each heir
  mapping(address => uint) public distribution; //List of ratio of contract balance to sent to each heir
  mapping(address => uint) heirIndex; //Mapping of heir to index in heirs list

  event HeirUpdated( address indexed heir, uint distribution); //Notify of update to heirs / distribution
  event HeirDistributed( address indexed heir, uint total); //Notify of update to heirs / distribution

  constructor (uint _waitTime ) {
    waitingTime = _waitTime;
    lastInteraction = block.timestamp;
  }

  function isHeir (address _addr) public view returns (bool) {
    return distribution[_addr] >= 0;
  }

  function getAllHeirs () public view returns (address[] memory) {
    return heirs;
  }

  function distributionSum () internal view returns (uint _sum) {
    for (uint i = 0; i < heirs.length; i++) {
      _sum = _sum.add(distribution[ heirs[i] ]);
    }
  }

  function getHeirIndex (address _heir) internal view returns (uint) {
    return heirIndex[_heir];
  }

  function _calcDistributionDue (address _heir, uint _totalBalance, uint _distributionSum)
    internal view returns (uint) {
    return (_totalBalance.mul(distribution[_heir] )).div(_distributionSum);
  }

  function isDistributionDue ()  public view returns (bool) {
    return block.timestamp.sub(lastInteraction) >= waitingTime;
  }

  function timeLeft () public view returns (uint) {
    return !isDistributionDue() ?
     waitingTime - block.timestamp.sub(lastInteraction) : 0;
  }

  function updateTime(uint _time) public onlyOwner {
    postpone();
    waitingTime = _time;
  }

  function getBalance() public view returns (uint) {
    return address(this).balance;
  }
  
  function withdraw(uint _sum) public onlyOwner {
    require(_sum <= address(this).balance, 'Too much for withdraw');
    payable(address(msg.sender)).transfer(_sum);
  }

  function transfer(address _address, uint _sum) public onlyOwner {
    require(_sum <= address(this).balance, 'Too much for transfer');
    payable(_address).transfer(_sum);
  }

  function updateHeir (address _heir, uint _distribution) public onlyOwner returns (bool) {
    require(_heir != address(0), '_heir cannot be Zero Address');
    require(_heir != owner, 'Cannot update Contract Owner distribution');
    require(_distribution > 0, 'Distribution must be greter than 0');
    require(!isDistributionDue(), 'Can not update distributions when distribution is Due');
    uint idx = getHeirIndex(_heir);
    if (idx == 0 && (heirs.length == 0 || (heirs[idx] != _heir))) {
      // Adding heir
      heirIndex[_heir] = heirs.length;
      heirs.push(_heir);
    }
    //Update distribution
    distribution[_heir] = _distribution;
    //Reset lastInteraction
    postpone();
    emit HeirUpdated(_heir, _distribution);
    return true;
  }

  function removeHeir (address _heir) public onlyOwner returns (bool) {
    require(_heir != address(0), 'Provide a heir address to remove');
    require(!isDistributionDue(), 'Can not update distributions when distribution is Due');
    uint idx = getHeirIndex(_heir);
    assert(heirs[idx] == _heir);
    //Remove heir
    delete(distribution[_heir]);
    delete(heirIndex[_heir]);
    heirs[idx] = heirs[ heirs.length.sub(1)];
    heirIndex[ heirs[idx] ] = idx;
    heirs.pop();
    //reset lastInteraction
    postpone();
    
    emit HeirUpdated(_heir, 0);
    return true;
  }

  //Reset the Wait Time, by pushing Distribution forward by another waitTime cycle
  function postpone () public payable onlyOwner returns (bool) {
    require(distributed == false, 'Timer can not be reset after initial distribution');
    lastInteraction = block.timestamp;
    return true;
  }

  //Distribute the inheritance
  function triggerDistribution () public {
    require(isDistributionDue(), 'Will is not yet due for distribution');
    require(address(this).balance>0, 'Nothing to distribution');
    uint amountDue;
    uint _balance = address(this).balance;
    uint _distributionSum = distributionSum();
    distributed = true;
    if (heirs.length > 0) {
      for (uint i = 0; i < heirs.length; i++) {
        amountDue = _calcDistributionDue(heirs[i], _balance, _distributionSum);
        address payable heir = payable(address(uint160(heirs[i])));
        heir.transfer(amountDue);
        emit HeirDistributed(heirs[i], amountDue);
      }
    }
    payable(owner).transfer(address(this).balance);
  }

  /**
  * Scenarios:
  * - Non-owner sends funds to contract: funds are received no function is triggerred
  * - Owner sends funds to contract: funds are received and postpone is triggerred if not yet distributed
  * - Non-owner sends no value to contract: contract triggerDistribution if isDistributionDue
  * - Owner sends no value to contract: postpone is triggerred if not yet distributed
  */
  receive() external payable {
    if (msg.sender == owner && distributed == false) {
      postpone();
    } else if (msg.value == 0 && isDistributionDue()) {
      triggerDistribution();
    }
  }
}
