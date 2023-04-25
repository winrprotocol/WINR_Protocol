// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IYieldTracker {
	function claim(address _account, address _receiver) external returns (uint256);

	function updateRewards(address _account) external;

	function getTokensPerInterval() external view returns (uint256);

	function claimable(address _account) external view returns (uint256);
}
