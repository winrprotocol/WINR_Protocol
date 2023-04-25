// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/IAccessControl.sol";

pragma solidity >=0.6.0 <0.9.0;

interface IWINRTimelock is IAccessControl {
	function transferOutTokens(
		address _tokenAddress,
		uint256 _tokenAmount,
		address _destination
	) external;

	event TransferOutTokens(address tokenAddres, uint256 amount, address destination);
}
