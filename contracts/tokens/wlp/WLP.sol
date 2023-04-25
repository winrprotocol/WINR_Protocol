// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./MintableBaseToken.sol";

contract WLP is MintableBaseToken {
	constructor(
		address _vaultRegistry,
		address _timelock,
		address _vwinrAddress
	) MintableBaseToken("WINR LP", "WLP", _vwinrAddress, _vaultRegistry, _timelock) {}

	function id() external pure returns (string memory _name) {
		return "WLP";
	}
}
