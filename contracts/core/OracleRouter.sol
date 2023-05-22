// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/oracles/IPrimaryOracleV1.sol";
import "../interfaces/oracles/IOracleRouterV1.sol";
import "../interfaces/gmx/IVaultPriceFeedGMX.sol";

contract OracleRouterV1 is IOracleRouterV1 {
	IPrimaryOracleV1 public immutable primaryPriceFeed; 

	constructor(
		address _primaryFeed
	) {
		primaryPriceFeed = IPrimaryOracleV1(_primaryFeed);
	}
	
	function getPriceMax(address _token) external view returns (uint256) {
		return primaryPriceFeed.getPrice(_token, true, false, false);
	}

	function getPriceMin(address _token) external view returns (uint256) {
		return primaryPriceFeed.getPrice(_token, false, false, false);
	}
}