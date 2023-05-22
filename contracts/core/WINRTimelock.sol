// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/governance/TimelockController.sol";
import "../interfaces/core/IWINRTimelock.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract WINRTimelock is IWINRTimelock, TimelockController {
	constructor(
		uint256 _minDelay,
		address[] memory _proposers,
		address[] memory _executors,
		address _admin
	) TimelockController(_minDelay, _proposers, _executors, _admin) {}

	/**
	 * @notice salvage function for ERC20 tokens that end up on this contract
	 * @dev this function can only be called via the timelock contract itself
	 * @param _tokenAddress address of the token to be transferred
	 * @param _tokenAmount amount of the token to be transferred
	 * @param _destination destination address tokens will be sent to
	 */
	function transferOutTokens(
		address _tokenAddress,
		uint256 _tokenAmount,
		address _destination
	) external {
		require(
			msg.sender == address(this), 
			"TimelockController: caller must be timelock"
		);
		SafeERC20.safeTransfer(
			IERC20(_tokenAddress), 
			_destination, 
			_tokenAmount
		);
		emit TransferOutTokens(_tokenAddress, _tokenAmount, _destination);
	}
}
