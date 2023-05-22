// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/oracles/IPrimaryOracleV2.sol";
import "../interfaces/oracles/ISecondaryOracleV2.sol";
import "../interfaces/oracles/IOracleRouterV2.sol";
import "../interfaces/gmx/IVaultPriceFeedGMX.sol";

contract OracleRouterV3 is IOracleRouterV2 {
	IPrimaryOracleV2 public immutable primaryPriceFeed; // this is the GMX price feed
	ISecondaryOracleV2 public immutable secondaryPriceFeed; // this is the alternative price feed
	address public immutable secondaryToken;

	constructor(
		address _primaryFeed,
		address _secondaryFeed,
		address _tokenToSecondary
	) {
		primaryPriceFeed = IPrimaryOracleV2(_primaryFeed);
		secondaryPriceFeed = ISecondaryOracleV2(_secondaryFeed);
		secondaryToken = _tokenToSecondary;
	}


	function getPriceMax(address _token) external view returns (uint256) {
		if (_token != secondaryToken) {
			// call the gmx/primary oracle
			return primaryPriceFeed.getPrice(_token, true, false, false);
		} else {
			require(
				_token == secondaryToken,
				"OracleRouterV2: only works for secondary token"
			);
			return secondaryPriceFeed.getPriceMax(_token);
		}
	}

	function getPriceMin(address _token) external view returns (uint256) {
		if (_token != secondaryToken) {
			// call the gmx/primary oracle
			return primaryPriceFeed.getPrice(_token, false, false, false);
		} else {
			require(
				_token == secondaryToken,
				"OracleRouterV2: only works for secondary token"
			);
			return secondaryPriceFeed.getPriceMin(_token);
		}
	}
}