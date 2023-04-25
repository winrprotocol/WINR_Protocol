// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IBaseToken {
	event SetInfo(string name, string symbol);

	event YieldTrackerSet(address[] yieldTrackers);

	event GovernanceTokenWithdraw(address token, address recipient, uint256 amountWithdrawn);

	event SetPrivateTransferMode(bool inPrivateTransferMode);

	event SetHandler(address handlerAddress, bool isActive);

	event NonStakingAccountAdded(address accountAdded);

	event NonStakingRemoved(address accountRemoved);

	event ClaimRecovered(address account, address receiver);

	event Claimed(address claimer, address receiver);

	event WithdrawStuckToken(address tokenAddress, address receiver, uint256 amount);

	function totalStaked() external view returns (uint256);

	function stakedBalance(address _account) external view returns (uint256);

	function setInPrivateTransferMode(bool _inPrivateTransferMode) external;

	function withdrawToken(address _token, address _account, uint256 _amount) external;
}
