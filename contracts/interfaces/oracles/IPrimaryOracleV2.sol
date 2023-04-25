// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IPrimaryOracleV2 {
	function getPrice(
		address _token,
		bool _maximise,
		bool _includeAmmPrice,
		bool _useSwapPricing
	) external view returns (uint256);
}
