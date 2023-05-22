// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/core/IVault.sol";
import "../interfaces/core/IVaultUtils.sol";

contract VaultUtils is IVaultUtils {
	IVault public immutable vault;

	constructor(
		address _vault
	) {
		vault = IVault(_vault);
	}

	/*==================== View functions *====================*/

	/**
	 * @notice returns the amount of basispooints the vault will charge for a WLP deposit (so minting of WLP by depositing a whitelisted asset in the vault)
	 * @param _token address of the token to check
	 * @param _usdwAmount usdw amount/value of the mutation
	 * @return the fee basis point the vault will charge for the mutation
	 */
	function getBuyUsdwFeeBasisPoints(
		address _token,
		uint256 _usdwAmount
	) external view override returns (uint256) {
		uint256 dynamicFee_ = getFeeBasisPoints(
			_token,
			_usdwAmount,
			vault.mintBurnFeeBasisPoints(),
			vault.taxBasisPoints(),
			true
		);
		uint256 minimumFee_ = vault.minimumBurnMintFee();
		// if the dynamic fee is lower than the minimum fee
		if (dynamicFee_ < minimumFee_) {
			// the vault will charge the minimum configured mint/burn fee
			return minimumFee_;
		} else {
			return dynamicFee_;
		}
	}

	/**
	 * @notice returns the amount of basispooints the vault will charge for a WLP withdraw (so burning of WLP for a certain whitelisted asset in the vault)
	 * @param _token address of the token to check
	 * @param _usdwAmount usdw amount/value of the mutation
	 * @return the fee basis point the vault will charge for the mutation
	 */
	function getSellUsdwFeeBasisPoints(
		address _token,
		uint256 _usdwAmount
	) external view override returns (uint256) {
		uint256 dynamicFee_ = getFeeBasisPoints(
			_token,
			_usdwAmount,
			vault.mintBurnFeeBasisPoints(),
			vault.taxBasisPoints(),
			false
		);
		uint256 minimumFee_ = vault.minimumBurnMintFee();
		// if the dynamic fee is lower than the minimum fee
		if (dynamicFee_ < minimumFee_) {
			// the vault will charge the minimum configured mint/burn fee
			return minimumFee_;
		} else {
			return dynamicFee_;
		}
	}

	/**
	 * @notice this function determines how much swap fee needs to be paid for a certain swap
	 * @dev the size/extent of the swap fee depends on if the swap balances the WLP (cheaper) or unbalances the pool (expensive)
	 * @param _tokenIn address of the token being sold by the swapper
	 * @param _tokenOut address of the token being bought by the swapper
	 * @param _usdwAmount the amount of of USDC/WLP the swap is 'worth'
	 */
	function getSwapFeeBasisPoints(
		address _tokenIn,
		address _tokenOut,
		uint256 _usdwAmount
	) external view override returns (uint256 effectiveSwapFee_) {
		// check if the swap is a swap between 2 stablecoins
		bool isStableSwap_ = vault.stableTokens(_tokenIn) && vault.stableTokens(_tokenOut);
		uint256 baseBps_ = isStableSwap_
			? vault.stableSwapFeeBasisPoints()
			: vault.swapFeeBasisPoints();
		uint256 taxBps_ = isStableSwap_
			? vault.stableTaxBasisPoints()
			: vault.taxBasisPoints();
		/**
		 * How large a swap fee is depends on if the swap improves the WLP asset balance or not.
		 * If the incoming asset is relatively scarce, this means a lower swap rate
		 * If the outcoing asset is abundant, this means a lower swap rate
		 * Both the in and outcoming assets need to improve the balance for the swap fee to be low.
		 * If both the incoming as the outgoing asset are scarce, this will mean that the swap fee will be high.
		 */
		// get the swap fee for the incoming asset/change
		uint256 feesBasisPoints0_ = getFeeBasisPoints(
			_tokenIn,
			_usdwAmount,
			baseBps_,
			taxBps_,
			true
		);
		// get the swap fee for the outgoing change/asset
		uint256 feesBasisPoints1_ = getFeeBasisPoints(
			_tokenOut,
			_usdwAmount,
			baseBps_,
			taxBps_,
			false
		);
		// use the highest of the two fees as effective rate
		effectiveSwapFee_ = feesBasisPoints0_ > feesBasisPoints1_
			? feesBasisPoints0_
			: feesBasisPoints1_;
	}

	// cases to consider
	// 1. initialAmount is far from targetAmount, action increases balance slightly => high rebate
	// 2. initialAmount is far from targetAmount, action increases balance largely => high rebate
	// 3. initialAmount is close to targetAmount, action increases balance slightly => low rebate
	// 4. initialAmount is far from targetAmount, action reduces balance slightly => high tax
	// 5. initialAmount is far from targetAmount, action reduces balance largely => high tax
	// 6. initialAmount is close to targetAmount, action reduces balance largely => low tax
	// 7. initialAmount is above targetAmount, nextAmount is below targetAmount and vice versa
	// 8. a large swap should have similar fees as the same trade split into multiple smaller swaps
	/**
	 * @param _token the asset that is entering or leaving the WLP
	 * @param _usdwDelta the amount of WLP this incoming/outgoing asset is 'worth'
	 * @param _feeBasisPoints the amount of swap fee (based on the type of swap)
	 * @param _taxBasisPoints the amount of tax (based on the type of swap)
	 * @param _increment if the asset is coming in 'incrementing the balance'
	 * @return the swapFee in basis points (including the tax)
	 */
	function getFeeBasisPoints(
		address _token,
		uint256 _usdwDelta,
		uint256 _feeBasisPoints,
		uint256 _taxBasisPoints,
		bool _increment
	) public view override returns (uint256) {
		if (!vault.hasDynamicFees()) {
			return _feeBasisPoints;
		}
		// fetch how much debt of the _token there is before the change in the WLP
		uint256 initialAmount_ = vault.usdwAmounts(_token);
		uint256 nextAmount_;
		// if the _token is leaving the pool (so it is NOT incrementing the pool debt/balance)
		if (!_increment) {
			// if the token is leaving the usdw debt will be reduced
			unchecked {
				nextAmount_ = _usdwDelta > initialAmount_
					? 0
					: (initialAmount_ - _usdwDelta);
			}
			// IMO nextAmount cannot be 0 realistically, it is merely there to prevent underflow
		} else {
			// calculate how much the debt will be
			nextAmount_ = (initialAmount_ + _usdwDelta);
		}
		// fetch how much usdw debt the token should be in optimally balanced state
		uint256 targetAmount_ = vault.getTargetUsdwAmount(_token);
		// if the token weight is 0, then the fee is the standard fee
		if (targetAmount_ == 0) {
			return _feeBasisPoints;
		}
		/**
		 * calculate how much the pool balance was before the swap/depoist/mutation is processed
		 */
		uint256 initialDiff_;
		unchecked {
			initialDiff_ = initialAmount_ > targetAmount_
				? (initialAmount_ - targetAmount_)
				: (targetAmount_ - initialAmount_);
		}
		/**
		 * calculate the balance of the pool after the swap/deposit/mutation is processed
		 */
		uint256 nextDiff_;
		unchecked {
			nextDiff_ = nextAmount_ > targetAmount_
				? (nextAmount_ - targetAmount_)
				: (targetAmount_ - nextAmount_);
		}
		/**
		 * with the initial and next balance, we can determine if the swap/deposit/mutation is improving the balance of the pool
		 */
		// action improves relative asset balance
		if (nextDiff_ < initialDiff_) {
			// the _taxBasisPoints determines the extent of the discount of the fee, the higher the tax, the lower the fee in case of improvement of the pool
			// this effect also works in reverse, if the tax is low, the fee will be high in case of improvement of the pool
			uint256 rebateBps_ = (_taxBasisPoints * initialDiff_) / targetAmount_;
			// if the action improves the balance so that the rebate is so high, no swap fee is charged and no tax is charged
			// if the rebate is higher than the fee, the function returns 0
			return rebateBps_ > _feeBasisPoints ? 0 : (_feeBasisPoints - rebateBps_);
		}
		/**
		 * If we are here, it means that this leg of the swap isn't improving the balance of the pool.
		 * Now we need to establish to what extent this leg unbalances the pool in order to determine the final fee.
		 */
		uint256 averageDiff_ = (initialDiff_ + nextDiff_) / 2;
		if (averageDiff_ > targetAmount_) {
			averageDiff_ = targetAmount_;
		}
		uint256 taxBps_ = (_taxBasisPoints * averageDiff_) / targetAmount_;
		return (_feeBasisPoints + taxBps_);
	}
}
