// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/oracles/IOracleRouterV2.sol";
import "../interfaces/gmx/IVaultPriceFeedGMX.sol";
import "./AccessControlBase.sol";
import "../interfaces/oracles/IPrimaryOracleV2.sol";
import "../interfaces/oracles/ISecondaryOracleV2.sol";

contract OracleRouterV2 is IOracleRouterV2, AccessControlBase {
	IPrimaryOracleV2 public immutable primaryPriceFeed; // this is the GMX price feed
	ISecondaryOracleV2 public immutable secondaryPriceFeed; // this is the alternative price feed
	address public immutable secondaryToken;

	constructor(
		address _vaultRegistry,
		address _timelock,
		address _primaryFeed,
		address _secondaryFeed,
		address _tokenToSecondary
	) AccessControlBase(_vaultRegistry, _timelock) {
		primaryPriceFeed = IPrimaryOracleV2(_primaryFeed);
		secondaryPriceFeed = ISecondaryOracleV2(_secondaryFeed);
		secondaryToken = _tokenToSecondary;
	}

	function getPriceMax(address _token) external view returns (uint256) {
		if (_token != secondaryToken) {
			return primaryPriceFeed.getPrice(_token, true, false, false);
		} else {
			return secondaryPriceFeed.getPriceMax(_token);
		}
	}

	function getPriceMin(address _token) external view returns (uint256) {
		if (_token != secondaryToken) {
			return primaryPriceFeed.getPrice(_token, false, false, false);
		} else {
			return secondaryPriceFeed.getPriceMin(_token);
		}
	}
}
