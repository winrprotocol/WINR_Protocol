// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev This contract designed to easing token transfers broadcasting information between contracts
interface IVaultManager {
	/// @notice escrow tokens into the manager
	/// @param _token one of the whitelisted tokens which is collected in settings
	/// @param _sender holder of tokens
	/// @param _amount the amount of token
	function escrow(address _token, address _sender, uint256 _amount) external;

	/// @notice release some amount of escrowed tokens
	/// @param _token one of the whitelisted tokens which is collected in settings
	/// @param _recipient holder of tokens
	/// @param _amount the amount of token
	function payback(address _token, address _recipient, uint256 _amount) external;

	/// @notice lets vault get wager amount from escrowed tokens
	/// @param _token one of the whitelisted tokens which is collected in settings
	/// @param _amount the amount of token
	function getEscrowedTokens(address _token, uint256 _amount) external;

	/// @notice lets vault get wager amount from escrowed tokens
	function payout(
		address[2] memory _tokens,
		address _recipient,
		uint256 _escrowAmount,
		uint256 _totalAmount
	) external;

	/// @notice lets vault get wager amount from escrowed tokens
	function payin(address _token, uint256 _escrowAmount) external;

	/// @notice transfers any whitelisted token into here
	/// @param _token one of the whitelisted tokens which is collected in settings
	/// @param _sender holder of tokens
	/// @param _amount the amount of token
	function transferIn(address _token, address _sender, uint256 _amount) external;

	/// @notice transfers any whitelisted token to recipient
	/// @param _token one of the whitelisted tokens which is collected in settings
	/// @param _recipient of tokens
	/// @param _amount the amount of token
	function transferOut(address _token, address _recipient, uint256 _amount) external;

	/// @notice transfers WLP tokens from this contract to Fee Collector and triggers Fee Collector
	/// @param _fee the amount of WLP sends to Fee Controller
	function transferWLPFee(uint256 _fee) external;

	function getMaxWager() external view returns (uint256);
}
