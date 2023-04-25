// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/oracles/IOracleRouter.sol";
import "../interfaces/gmx/IVaultPriceFeedGMX.sol";

contract OracleRouterSimple is IOracleRouter {
	IVaultPriceFeedGMX public immutable gmxFeed;

	constructor(address _gmxPricefeed) {
		gmxFeed = IVaultPriceFeedGMX(_gmxPricefeed);
	}

	function getPrice(
		address _token,
		bool _maximise,
		bool _includeAmmPrice,
		bool _useSwapPricing
	) external view returns (uint256) {
		return gmxFeed.getPrice(_token, _maximise, _includeAmmPrice, _useSwapPricing);
	}

	function getPriceMax(address _token) external view returns (uint256) {
		return gmxFeed.getPrice(_token, true, false, false);
	}

	function getPriceMin(address _token) external view returns (uint256) {
		return gmxFeed.getPrice(_token, false, false, false);
	}

	function getPrimaryPrice(address _token, bool _type) external view returns (uint256) {
		return gmxFeed.getPrimaryPrice(_token, _type);
	}

	function isAdjustmentAdditive(address _token) external view returns (bool) {
		return gmxFeed.isAdjustmentAdditive(_token);
	}

	function adjustmentBasisPoints(address _token) external view returns (uint256) {
		return gmxFeed.adjustmentBasisPoints(_token);
	}
}
