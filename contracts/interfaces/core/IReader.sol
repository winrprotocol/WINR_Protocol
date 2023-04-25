// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

import "./IVault.sol";
import "../gmx/IVaultPriceFeedGMX.sol";

interface IReader {
	function getFees(
		address _vault,
		address[] memory _tokens
	) external view returns (uint256[] memory);

	function getWagerFees(
		address _vault,
		address[] memory _tokens
	) external view returns (uint256[] memory);

	function getSwapFeeBasisPoints(
		IVault _vault,
		address _tokenIn,
		address _tokenOut,
		uint256 _amountIn
	) external view returns (uint256, uint256, uint256);

	function getAmountOut(
		IVault _vault,
		address _tokenIn,
		address _tokenOut,
		uint256 _amountIn
	) external view returns (uint256, uint256);

	function getMaxAmountIn(
		IVault _vault,
		address _tokenIn,
		address _tokenOut
	) external view returns (uint256);

	function getPrices(
		IVaultPriceFeedGMX _priceFeed,
		address[] memory _tokens
	) external view returns (uint256[] memory);

	function getVaultTokenInfo(
		address _vault,
		address _weth,
		uint256 _usdwAmount,
		address[] memory _tokens
	) external view returns (uint256[] memory);

	function getFullVaultTokenInfo(
		address _vault,
		address _weth,
		uint256 _usdwAmount,
		address[] memory _tokens
	) external view returns (uint256[] memory);

	function getFeesForGameSetupFeesUSD(
		address _tokenWager,
		address _tokenWinnings,
		uint256 _amountWager
	) external view returns (uint256 wagerFeeUsd_, uint256 swapFeeUsd_, uint256 swapFeeBp_);

	function getNetWinningsAmount(
		address _tokenWager,
		address _tokenWinnings,
		uint256 _amountWager,
		uint256 _multiple
	) external view returns (uint256 amountWon_, uint256 wagerFeeToken_, uint256 swapFeeToken_);

	function getSwapFeePercentageMatrix(
		uint256 _usdValueOfSwapAsset
	) external view returns (uint256[] memory);

	function adjustForDecimals(
		uint256 _amount,
		address _tokenDiv,
		address _tokenMul
	) external view returns (uint256 scaledAmount_);
}
