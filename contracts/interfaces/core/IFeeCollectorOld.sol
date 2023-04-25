// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IFeeCollectorOld {
	/*==================== Public Functions *====================*/

	function calculateDistribution(
		uint256 _amountToDistribute,
		uint64 _ratio
	) external pure returns (uint256 amount_);

	function distributeFeesAllGovernance() external;

	function distributeFeesAll() external;

	function syncLastDistribution() external;

	function syncWhitelistedTokens() external;

	function addToWhitelist(address _toWhitelistAddress, bool _setting) external;

	function setReferralDistributor(address _distributorAddress) external;

	function setCoreDevelopment(address _coreDevelopment) external;

	function setWinrStakingContract(address _winrStakingContract) external;

	function setBuyBackContract(address _buybackContract) external;

	function setWlpClaimContract(address _wlpClaimContract) external;

	function setDistribution(
		uint64 _ratioWLP,
		uint64 _ratioStaking,
		uint64 _buybackRatio,
		uint64 _ratioCore,
		uint64 _ratioReferral
	) external;

	function addTokenToWhitelistList(address _tokenToAdd) external;

	function deleteWhitelistTokenList() external;

	/*==================== Events *====================*/

	event DistributionSync();
	event WhitelistEdit(address whitelistAddress, bool setting);
	event EmergencyWithdraw(address caller, address token, uint256 amount, address destination);
	event ManualGovernanceDistro();
	event FeesDistributed();
	event WagerFeesManuallyFarmed(address tokenAddress, uint256 amountFarmed);
	event ManualDistributionManager(
		address targetToken,
		uint256 amountToken,
		address destinationAddress
	);
	event SetRewardInterval(uint256 timeInterval);
	event SetCoreDestination(address newDestination);
	event SetBuybackDestination(address newDestination);
	event SetClaimDestination(address newDestination);
	event SetReferralDestination(address referralDestination);
	event SetStakingDestination(address newDestination);
	event SwapFeesManuallyFarmed(address tokenAddress, uint256 totalAmountCollected);
	event CollectedWagerFees(address tokenAddress, uint256 amountCollected);
	event CollectedSwapFees(address tokenAddress, uint256 amountCollected);
	event NothingToDistribute(address token);
	event DistributionComplete(
		address token,
		uint256 toWLP,
		uint256 toStakers,
		uint256 toBuyBack,
		uint256 toCore,
		uint256 toReferral
	);
	event DistributionSet(
		uint64 ratioWLP,
		uint64 ratioStaking,
		uint64 buybackRatio,
		uint64 ratioCore,
		uint64 referralRatio
	);
	event SyncTokens();
	event DeleteAllWhitelistedTokens();
	event TokenAddedToWhitelist(address addedTokenAddress);
	event TokenTransferredByTimelock(address token, address recipient, uint256 amount);
}
