pragma solidity ^0.4.23;

import "sc-library/contracts/wallet/ERC20Wallet.sol";
import "sc-library/contracts/wallet/Wallet.sol";
import "./LostKey.sol";


contract LostKeyERC20Wallet is LostKey, ERC20Wallet, Wallet {
  event Withdraw(address _sender, uint amount, address _beneficiary);

  function execute(address _to, uint _value, bytes _data) external returns (bytes32) {
    sendFunds(_to, _value, _data);
    return keccak256(abi.encodePacked(msg.data, block.number));
  }

  function sendFunds(address _receiver, uint _amount, bytes _data) public onlyTarget onlyAlive {
    sendFundsInternal(_receiver, _amount, _data);
  }

  function sendFunds(address _receiver, uint _amount) public onlyTarget onlyAlive {
    sendFundsInternal(_receiver, _amount, "");
  }

  function tokenTransfer(address _token, address _to, uint _value) public onlyTarget returns (bool success) {
    updateLastActivity();
    return super.tokenTransfer(_token, _to, _value);
  }

  function tokenTransferFrom(
    address _token,
    address _from,
    address _to,
    uint _value
  )
    public
    onlyTarget
    returns (bool success)
  {
    updateLastActivity();
    return super.tokenTransferFrom(
      _token,
      _from,
      _to,
      _value
    );
  }

  function tokenApprove(address _token, address _spender, uint256 _value) public onlyTarget returns (bool success) {
    updateLastActivity();
    return super.tokenApprove(_token, _spender, _value);
  }

  function sendFundsInternal(address _receiver, uint _amount, bytes _data) internal {
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
