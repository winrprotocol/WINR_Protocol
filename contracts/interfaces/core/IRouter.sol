// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IRouter {
	/*==================== Functions *====================*/
	function addPlugin(address _plugin) external;

	function pluginTransfer(
		address _token,
		address _account,
		address _receiver,
		uint256 _amount
	) external;

	function swap(
		address[] memory _path,
		uint256 _amountIn,
		uint256 _minOut,
		address _receiver
	) external;

	/*==================== Events  *====================*/
	event Swap(
		address account,
		address tokenIn,
		address tokenOut,
		uint256 amountIn,
		uint256 amountOut
	);
}
