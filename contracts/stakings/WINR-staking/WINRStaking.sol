// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./WINRVesting.sol";

contract WINRStaking is WINRVesting {
	/*==================================================== State Variables ========================================================*/
	mapping(address => StakeDividend) public dividendWINRStakes;
	mapping(address => StakeDividend) public dividendVestedWINRStakes;

	/*==================================================== Constructor ===========================================================*/
	constructor(
		address _vaultRegistry,
		address _timelock
	) WINRVesting(_vaultRegistry, _timelock) {}

	/*===================================================== FUNCTIONS ============================================================*/
	/*=================================================== View Functions =========================================================*/

	/**
	 *
	 * @dev Retrieves the staked amount of dividend WINR tokens for a specified account and stake type.
	 * @param _account The address of the account to retrieve the staked amount for.
	 * @param _isVested A boolean flag indicating whether to retrieve the vested WINR or WINR dividend stake.
	 * @return _amount The staked amount of dividend WINR/vWINR tokens for the specified account and stake type.
	 * @dev The function retrieves the staked amount of dividend WINR/vWINR tokens for the specified account and stake type from the dividendWINRStakes or dividenVestedWINRdStakes mapping,
	 *      depending on the value of the isVested parameter.
	 */
	function dividendStakedAmount(
		address _account,
		bool _isVested
	) external view returns (uint256) {
		return
			_isVested
				? dividendVestedWINRStakes[_account].amount
				: dividendWINRStakes[_account].amount;
	}

	/**
	 *
	 * @dev Retrieves the dividend stake for a specified account and stake type.
	 * @param _account The address of the account to retrieve the dividend stake for.
	 * @param _isVested A boolean flag indicating whether to retrieve the vested or non-vested dividend stake.
	 * @return stake A Stake struct representing the dividend stake for the specified account and stake type.
	 * @dev The function retrieves the dividend stake for the specified account and stake type from the dividendWINRStakes or dividenVestedWINRdStakes mapping, depending on the value of the isVested parameter.
	 */
	function getDividendStake(
		address _account,
		bool _isVested
	) external view returns (StakeDividend memory) {
		return
			_isVested
				? dividendVestedWINRStakes[_account]
				: dividendWINRStakes[_account];
	}

	/**
	 *
	 * @param _account The address of the account to retrieve the pending rewards data.
	 */
	function pendingDividendRewards(address _account) external view returns (uint256 pending_) {
		// Calculate the pending reward based on the dividend vested WINR stake of the given account
		pending_ += _pendingByDividendStake(dividendVestedWINRStakes[_account]);
		// Calculate the pending reward based on the dividend WINR stake of the given account
		pending_ += _pendingByDividendStake(dividendWINRStakes[_account]);
	}

	/*================================================= External Functions =======================================================*/
	/**
	 *
	 * @dev Fallback function that handles incoming Ether transfers to the contract.
	 * @dev The function emits a Donation event with the sender's address and the amount of Ether transferred.
	 * @dev The function can receive Ether and can be called by anyone, but does not modify the state of the contract.
	 */
	fallback() external payable {
		emit Donation(msg.sender, msg.value);
	}

	/**
	 *
	 * @dev Receive function that handles incoming Ether transfers to the contract.
	 * @dev The function emits a Donation event with the sender's address and the amount of Ether transferred.
	 * @dev The function can receive Ether and can be called by anyone, but does not modify the state of the contract.
	 */
	receive() external payable {
		emit Donation(msg.sender, msg.value);
	}

	/**
	 *
	 * @dev Distributes a share of profits to all stakers based on their stake weight.
	 * @param _amount The amount of profits to distribute among stakers.
	 * @notice The function can only be called by an address with the PROTOCOL_ROLE.
	 * @notice The total weight of all staked tokens must be greater than zero for profits to be distributed.
	 * @dev If the total weight of all staked tokens is greater than zero,
	 *      the function adds the specified amount of profits to the total profit pool
	 *      and updates the accumulated profit per weight value accordingly.
	 * @dev The function emits a Share event to notify external systems about the distribution of profits.
	 */
	function share(uint256 _amount) external override isAmountNonZero(_amount) onlyProtocol {
		if (totalWeight > 0) {
			totalProfit += _amount;
			totalEarned += _amount;
			accumProfitPerWeight += (_amount * PRECISION) / totalWeight;

			emit Share(_amount, totalWeight, totalStakedVestedWINR, totalStakedWINR);
		}
	}

	/**
	 *
	 *  @dev Function to claim dividends for the caller.
	 *  @notice The function can only be called when the contract is not paused and is non-reentrant.
	 *  @notice The function calls the internal function '_claimDividend' passing the caller's address and 'isVested' boolean as parameters.
	 */
	function claimDividend() external whenNotPaused nonReentrant {
		_claimDividendBatch(msg.sender);
	}

	/**
	 * @notice Pauses the contract. Only the governance address can call this function.
	 * @dev While the contract is paused, some functions may be disabled to prevent unexpected behavior.
	 */
	function pause() public onlyTeam {
		_pause();
	}

	/**
	 * @notice Unpauses the contract. Only the governance address can call this function.
	 * @dev Once the contract is unpaused, all functions should be enabled again.
	 */
	function unpause() public onlyTeam {
		_unpause();
	}

	/**
	 * @notice Allows the governance to withdraw a certain amount of donations and transfer them to a specified address
	 * @param to The address to transfer the donations to
	 * @param amount The amount of donations to withdraw
	 */
	function withdrawDonations(address payable to, uint256 amount) external onlyGovernance {
		require(address(this).balance >= amount, "Insufficient balance");
		(bool sent, ) = to.call{value: amount}("");
		require(sent, "Withdraw failed");
	}

	/**
	 * @dev Updates the vesting period configuration.
	 * @param duration Total vesting duration in seconds.
	 * @param minDuration Minimum vesting duration in seconds.
	 * @param claimDuration Duration in seconds during which rewards can be claimed.
	 * @param minPercent Minimum percentage of the total stake that must be vested.
	 */
	function updatePeriod(
		uint256 duration,
		uint256 minDuration,
		uint256 claimDuration,
		uint256 minPercent
	) external onlyGovernance {
		require(
			duration >= minDuration,
			"Duration must be greater than or equal to minimum duration"
		);
		require(
			claimDuration <= duration,
			"Claim duration must be less than or equal to duration"
		);

		period.duration = duration;
		period.minDuration = minDuration;
		period.claimDuration = claimDuration;
		period.minPercent = minPercent;
	}

	/**
	 *
	 * @dev Internal function to deposit WINR/vWINR as dividends.
	 * @param _amount The amount of WINR/vWINR to be deposited.
	 * @param _isVested Boolean flag indicating if tokens are vWINR.
	 * @dev This function performs the following steps:
	 *     Get the address of the stake owner.
	 *     Determine the stake details based on the boolean flag isVested.
	 *     Take the tokens from the stake owner and update the stake amount.
	 *     If the stake amount is greater than 0, claim dividends for the stake owner.
	 *     Calculate the stake weight based on the updated stake amount and isVested flag.
	 *     Update the stake with the new stake amount, start time, weight and profit debt.
	 *     Emit a Deposit event with the details of the deposited tokens.
	 */
	function depositDividend(
		uint256 _amount,
		bool _isVested
	) external isAmountNonZero(_amount) nonReentrant whenNotPaused {
		// Get the address of the stake owner.
		address sender_ = msg.sender;
		// Determine the stake details based on the boolean flag isVested.
		StakeDividend storage stake_;

		if (_isVested) {
			tokenManager.takeVestedWINR(sender_, _amount);
			stake_ = dividendVestedWINRStakes[sender_];
			totalStakedVestedWINR += _amount;
		} else {
			tokenManager.takeWINR(sender_, _amount);
			stake_ = dividendWINRStakes[sender_];
			totalStakedWINR += _amount;
		}

		// If the stake amount is greater than 0, claim dividends for the stake owner.
		if (stake_.amount > 0) {
			_claimDividend(sender_, _isVested);
		}

		// Calculate the stake weight
		uint256 weight_ = _calculateWeight(stake_.amount + _amount, _isVested, false);
		// increase the total staked weight
		totalWeight += (weight_ - stake_.weight);
		// Update the stake with the new stake amount, start time, weight and profit debt.
		stake_.amount += _amount;
		stake_.depositTime = uint128(block.timestamp);
		stake_.weight = weight_;
		stake_.profitDebt = _calcDebt(weight_);

		// Emit a DepositDividend event with the details of the deposited tokens.
		emit DepositDividend(sender_, stake_.amount, stake_.profitDebt, _isVested);
	}

	/**
	 *
	 * @dev Internal function to unstake tokens.
	 * @param _amount The amount of tokens to be unstaked.
	 * @param _isVested Boolean flag indicating if stake is Vested WINR.
	 * @notice This function also claims rewards.
	 * @dev This function performs the following steps:
	 *    Check that the staker has sufficient stake amount.
	 *    Claim dividends for the staker.
	 *    Compute the weight of the unstaked tokens and update the total staked amount and weight.
	 *    Compute the debt for the stake after unstaking tokens.
	 *    Burn the necessary amount of tokens and send the remaining unstaked tokens to the staker.
	 *    Emit an Unstake event with the details of the unstaked tokens.
	 */
	function unstake(uint256 _amount, bool _isVested) external nonReentrant whenNotPaused {
		address sender_ = msg.sender;
		StakeDividend storage stake_ = _isVested
			? dividendVestedWINRStakes[sender_]
			: dividendWINRStakes[sender_];
		require(stake_.amount >= _amount, "Insufficient stake amount");
		ITokenManager tokenManager_ = tokenManager;

		// Compute the amount of tokens to be burned and sent to the staker.
		uint256 burnAmount_ = _computeBurnAmount(_amount);
		uint256 sendAmount_ = _amount - burnAmount_;
		// Compute the weight of the unstaked tokens and update the total staked amount and weight.
		uint256 unstakedWeight_;

		// Claim dividends for the staker.
		_claimDividend(sender_, _isVested);

		// Burn the necessary amount of tokens and send the remaining unstaked tokens to the staker.
		if (_isVested) {
			tokenManager_.burnVestedWINR(burnAmount_);
			tokenManager_.sendVestedWINR(sender_, sendAmount_);
			unstakedWeight_ = _amount * weightMultipliers.vWinr;
			totalStakedVestedWINR -= _amount;
		} else {
			tokenManager_.burnWINR(burnAmount_);
			tokenManager_.sendWINR(sender_, sendAmount_);
			unstakedWeight_ = _amount * weightMultipliers.winr;
			totalStakedWINR -= _amount;
		}

		totalWeight -= unstakedWeight_;

		// Update the stake details after unstaking tokens.
		stake_.amount -= _amount;
		stake_.weight -= unstakedWeight_;
		stake_.profitDebt = _calcDebt(stake_.weight);

		// Emit an Unstake event with the details of the unstaked tokens.
		emit Unstake(sender_, block.timestamp, sendAmount_, burnAmount_, _isVested);
	}

	/*================================================= Internal Functions =======================================================*/
	/**
	 *
	 * @dev Internal function to claim dividends for a stake.
	 * @param _account The address of the stake owner.
	 * @param _isVested Boolean flag indicating if stake is Vested WINR.
	 * @return reward_ The amount of dividends claimed.
	 * @dev This function performs the following steps:
	 *     Determine the stake details based on the boolean flag isVested.
	 *     Calculate the pending rewards for the stake.
	 *     Send the rewards to the stake owner.
	 *     Update the profit debt for the stake.
	 *     Update the total profit and total claimed for the stake owner.
	 *     Emit a Claim event with the details of the claimed rewards.
	 */
	function _claimDividend(
		address _account,
		bool _isVested
	) internal returns (uint256 reward_) {
		// Determine the stake details based on the boolean flag isVested.
		StakeDividend storage stake_ = _isVested
			? dividendVestedWINRStakes[_account]
			: dividendWINRStakes[_account];

		// Calculate the pending rewards for the stake.
		reward_ = _pendingByDividendStake(stake_);

		if (reward_ == 0) {
			return 0;
		}

		// Send the rewards to the stake owner.
		tokenManager.sendWLP(_account, reward_);

		// Update the profit debt for the stake.
		stake_.profitDebt = _calcDebt(stake_.weight);

		// Update the total profit and total claimed for the stake owner.
		// totalProfit -= _reward;
		totalClaimed[_account] += reward_;

		// Emit a Claim event with the details of the claimed rewards.
		emit ClaimDividend(_account, reward_, _isVested);
	}

	/**
	 *
	 * @dev Internal function to claim dividends for all stake.
	 * @param _account The address of the stake owner.
	 * @return reward_ The amount of dividends claimed.
	 */
	function _claimDividendBatch(address _account) internal returns (uint256 reward_) {
		// Determine the stake details based on the boolean flag isVested.
		StakeDividend storage stakeVWINR_ = dividendVestedWINRStakes[_account];
		StakeDividend storage stakeWINR_ = dividendWINRStakes[_account];

		// Calculate the pending rewards for the stake.
		reward_ = _pendingByDividendStake(stakeVWINR_);
		reward_ += _pendingByDividendStake(stakeWINR_);

		if (reward_ == 0) {
			return 0;
		}

		// Send the rewards to the stake owner.
		tokenManager.sendWLP(_account, reward_);

		// Update the profit debt for the stake.
		stakeVWINR_.profitDebt = _calcDebt(stakeVWINR_.weight);
		stakeWINR_.profitDebt = _calcDebt(stakeWINR_.weight);

		// Update the total profit and total claimed for the stake owner.
		totalClaimed[_account] += reward_;

		// Emit a Claim event with the details of the claimed rewards.
		emit ClaimDividendBatch(_account, reward_);
	}

	/**
	 * @notice Computes the pending WLP amount of the stake.
	 * @param _stake The stake for which to compute the pending amount.
	 * @return holderProfit_ The pending WLP amount.
	 */
	function _pendingByDividendStake(
		StakeDividend memory _stake
	) internal view returns (uint256 holderProfit_) {
		// Compute the holder's profit as the product of their stake's weight and the accumulated profit per weight.
		holderProfit_ = ((_stake.weight * accumProfitPerWeight) / PRECISION);
		// If the holder's profit is less than their profit debt, return zero.
		if (holderProfit_ < _stake.profitDebt) {
			return 0;
		} else {
			// Otherwise, subtract their profit debt from their total profit and return the result.
			holderProfit_ -= _stake.profitDebt;
		}
	}
}
