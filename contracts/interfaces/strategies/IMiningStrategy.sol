// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IMiningStrategy {
	function calculate(
		uint256 _amount,
		uint256 _mintedByGames
	) external returns (uint256 amount_);

	function increaseVolume(address _input, uint256 _amount) external;

	function decreaseVolume(address _input, uint256 _amount) external;

	function currentMultiplier() external view returns (int256);
}
