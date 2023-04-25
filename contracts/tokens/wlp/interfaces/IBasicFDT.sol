// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.6.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IBaseFDT.sol";

interface IBasicFDT is IBaseFDT, IERC20 {
	event PointsPerShareUpdated_WLP(uint256);

	event PointsCorrectionUpdated_WLP(address indexed, int256);

	event PointsPerShareUpdated_VWINR(uint256);

	event PointsCorrectionUpdated_VWINR(address indexed, int256);

	function withdrawnFundsOf_WLP(address) external view returns (uint256);

	function accumulativeFundsOf_WLP(address) external view returns (uint256);

	function withdrawnFundsOf_VWINR(address) external view returns (uint256);

	function accumulativeFundsOf_VWINR(address) external view returns (uint256);

	function updateFundsReceived_WLP() external;

	function updateFundsReceived_VWINR() external;
}
