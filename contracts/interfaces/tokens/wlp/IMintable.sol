// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IMintable {
	event MinterSet(address minterAddress, bool isActive);

	function isMinter(address _account) external returns (bool);

	function setMinter(address _minter, bool _isActive) external;

	function mint(address _account, uint256 _amount) external;

	function burn(address _account, uint256 _amount) external;
}
