// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IOracleRouter {
	function getPrice(
		address _token,
		bool _maximise,
		bool _includeAmmPrice,
		bool _useSwapPricing
	) external view returns (uint256);

	function getPriceMax(address _token) external view returns (uint256);

	function getPriceMin(address _token) external view returns (uint256);

	function getPrimaryPrice(address _token, bool _maximise) external view returns (uint256);

	function isAdjustmentAdditive(address _token) external view returns (bool);

	function adjustmentBasisPoints(address _token) external view returns (uint256);
}
