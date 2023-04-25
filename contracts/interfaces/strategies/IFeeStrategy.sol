// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IFeeStrategy {
	function calculate(address _token, uint256 _amount) external returns (uint256 amount_);

	function currentMultiplier() external view returns (int256);

	function computeDollarValue(
		address _token,
		uint256 _amount
	) external view returns (uint256 _dollarValue);
}
