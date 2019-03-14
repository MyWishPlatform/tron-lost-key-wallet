pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/math/Math.sol";
import "sc-library/contracts/ERC223/ERC223Receiver.sol";
import "sc-library/contracts/SoftDestruct.sol";
import "./Checkable.sol";

contract LostKey is Checkable, SoftDestruct, ERC223Receiver {
  using SafeMath for uint;

  struct RecipientPercent {
    address recipient;
    uint8 percent;
  }

  /**
   * Period of time (in seconds) without activity.
   */
  uint32 public noActivityPeriod;

  /**
   * Last active timestamp.
   */
  uint64 public lastActiveTs;

  /**
   * Addresses of token contracts
   */
  address[] private tokenAddresses;

  /**
   * Recipient addresses and corresponding % of funds.
   */
  RecipientPercent[] public percents;

  // Occurs when contract was killed.
  event Killed(bool byUser);

  event TokensSent(address indexed token, address indexed recipient, uint amount, uint percent);

  event TokenAdded(address indexed token);

  event Withdraw(address _sender, uint amount, address _beneficiary);
  // Occurs when founds were sent.
  event FundsAdded(address indexed from, uint amount);
  // Occurs when accident leads to sending funds to recipient.
  event FundsSent(address recipient, uint amount, uint percent);

  constructor() public {
    lastActiveTs = uint64(block.timestamp);
  }

  function() public payable onlyAlive notTriggered {
    emit FundsAdded(msg.sender, msg.value);
  }

  function tokenFallback(address, uint, bytes) public {
    require(false, "Token fallback function not allowed");
  }

  /**
   * @dev Limit check execution only for alive contract.
   */
  function check() public payable onlyAlive {
    super.check();
  }

  /**
   * @dev Extends super method to add event producing.
   */
  function kill() public {
    super.kill();
    emit Killed(true);
  }

  /**
   * @dev Adds token addresses.
   *
   * @param _contracts Token contracts list to add.
   */
  function addTokenAddresses(address[] _contracts) external onlyTarget notTriggered onlyAlive {
    for (uint i = 0; i < _contracts.length; i++) {
      _addTokenAddress(_contracts[i]);
    }
  }

  /**
   * @dev Adds token address.
   *
   * @param _contract Token contract to add.
   */
  function addTokenAddress(address _contract) public onlyTarget notTriggered onlyAlive {
    _addTokenAddress(_contract);
  }

  function _addTokenAddress(address _contract) internal {
    require(_contract != address(0));
    //    require(!internalIsTokenAddressAlreadyInList(_contract));
    tokenAddresses.push(_contract);
    emit TokenAdded(_contract);
  }

  function isTokenInList(address _tokenContract) public view returns (bool) {
    for (uint i = 0; i < tokenAddresses.length; i++) {
      if (_tokenContract == tokenAddresses[i]) {
        return true;
      }
    }
    return false;
  }

  /**
   * @dev Calculate amounts to transfer corresponding to the percents.
   *
   * @param _balance current contract balance.
   */
  function _calculateAmounts(uint _balance) internal view returns (uint[] amounts) {
    uint remainder = _balance;
    amounts = new uint[](percents.length);
    for (uint i = 0; i < percents.length; i++) {
      if (i + 1 == percents.length) {
        amounts[i] = remainder;
        break;
      }
      uint amount = _balance.mul(percents[i].percent).div(100);
      amounts[i] = amount;
      remainder -= amount;
    }
  }

  function _distributeFunds() internal {
    uint[] memory amounts = _calculateAmounts(address(this).balance);

    for (uint i = 0; i < amounts.length; i++) {
      uint amount = amounts[i];
      address recipient = percents[i].recipient;
      uint percent = percents[i].percent;

      if (amount == 0) {
        continue;
      }

      recipient.transfer(amount);
      emit FundsSent(recipient, amount, percent);
    }
  }

  /**
   * @dev Distribute tokens between recipients in corresponding by percents.
   */
  function _distributeTokens() internal {
    for (uint i = 0; i < tokenAddresses.length; i++) {
      ERC20 token = ERC20(tokenAddresses[i]);
      uint balance = token.balanceOf(targetUser);
      uint allowance = token.allowance(targetUser, this);
      uint[] memory amounts = _calculateAmounts(Math.min256(balance, allowance));

      for (uint j = 0; j < amounts.length; j++) {
        uint amount = amounts[j];
        address recipient = percents[j].recipient;
        uint percent = percents[j].percent;

        if (amount == 0) {
          continue;
        }

        token.transferFrom(targetUser, recipient, amount);
        emit TokensSent(token, recipient, amount, percent);
      }
    }
  }

  function internalCheck() internal returns (bool) {
    bool result = block.timestamp > lastActiveTs && (block.timestamp - lastActiveTs) >= noActivityPeriod;
    require(msg.value == 0, "Value should be zero");
    emit Checked(result);
    return result;
  }

  /**
   * @dev Do inner action if check was success.
   */
  function internalAction() internal {
    _distributeFunds();
    _distributeTokens();
  }

  function getTokenAddresses() public view returns (address[]) {
    return tokenAddresses;
  }

  function updateLastActivity() internal {
    lastActiveTs = uint64(block.timestamp);
  }

  function sendFundsInternal(uint _amount, address _receiver, bytes _data) internal {
    require(address(this).balance >= _amount);
    if (_data.length == 0) {
      // solium-disable-next-line security/no-send
      require(_receiver.send(_amount));
    } else {
      // solium-disable-next-line security/no-call-value
      require(_receiver.call.value(_amount)(_data));
    }

    emit Withdraw(msg.sender, _amount, _receiver);
    updateLastActivity();
  }
}
