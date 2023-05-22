// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IOracleRouterV1 {
	function getPriceMax(address _token) external view returns (uint256);

	function getPriceMin(address _token) external view returns (uint256);
}
