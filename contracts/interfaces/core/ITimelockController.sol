// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/IAccessControl.sol";

pragma solidity >=0.6.0 <0.9.0;

interface ITimelockController is IAccessControl {
	function isOperation(bytes32 id) external view returns (bool registered);

	function isOperationPending(bytes32 id) external view returns (bool pending);

	function isOperationReady(bytes32 id) external view returns (bool ready);

	function isOperationDone(bytes32 id) external view returns (bool done);

	function getTimestamp(bytes32 id) external view returns (uint256 timestamp);

	function getMinDelay() external view returns (uint256 duration);

	function hashOperation(
		address target,
		uint256 value,
		bytes calldata data,
		bytes32 predecessor,
		bytes32 salt
	) external pure returns (bytes32 hash);

	function schedule(
		address target,
		uint256 value,
		bytes calldata data,
		bytes32 predecessor,
		bytes32 salt,
		uint256 delay
	) external;

	function execute(
		address target,
		uint256 value,
		bytes calldata payload,
		bytes32 predecessor,
		bytes32 salt
	) external;

	function updateDelay(uint256 newDelay) external;
}
