pragma solidity ^0.4.23;

import "./LostKey.sol";

contract LostKeyNotify is LostKey {
  /**
   * Occurs when user notify that he is available.
   */
  event Notified();

  function imAvailable() public onlyTarget notTriggered onlyAlive {
    updateLastActivity();
    emit Notified();
  }
}
