// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "solmate/src/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../../core/AccessControlBase.sol";
import "../../interfaces/core/ITokenManager.sol";
import "../../interfaces/tokens/IWINR.sol";
import "../../interfaces/stakings/IWINRStaking.sol";

contract WINRVesting is IWINRStaking, Pausable, ReentrancyGuard, AccessControlBase {
	/*====================================================== Modifiers ===========================================================*/
	/**
	 * @notice Throws if the amount is not greater than zero
	 */
	modifier isAmountNonZero(uint256 amount) {
		require(amount > 0, "amount must be greater than zero");
		_;
	}

	/*====================================================== State Variables =====================================================*/

	// 18 decimal precision
	uint256 internal constant PRECISION = 1e18;
	//The total profit earned by all staked tokens in the contract
	uint256 public totalProfit;
	//The total weight of all stakes in the contract
	uint256 public totalWeight;
	//The total amount of WINR tokens staked in the contract
	uint256 public totalStakedWINR;
	//The total amount of vWINR tokens staked in the contract
	uint256 public totalStakedVestedWINR;
	//The accumulated profit per weight of all stakes in the contract. It is used in the calculation of rewards earned by each stakeholder
	uint256 public accumProfitPerWeight;
	//The percentage of staked tokens that will be burned when a stake is withdrawn
	uint256 public unstakeBurnPercentage;
	//The total profit history earned by all staked tokens in the contract
	uint256 public totalEarned;
	//Interface of Token Manager contract
	ITokenManager public tokenManager;
	//This mapping stores an array of StakeVesting structures for each address that has staked tokens in the contract
	mapping(address => StakeVesting[]) public stakes;
	//This mapping stores an array of indexes into the stakes array for each address that has active vesting stakes in the contract
	mapping(address => uint256[]) public activeVestingIndexes;
	//This mapping stores the total amount of tokens claimed by each address that has staked tokens in the contract
	mapping(address => uint256) public totalClaimed;
	//Initializes default vesting period
	Period public period = Period(180 days, 15 days, 165, 5e17);
	//IInitializes default reward multipliers
	WeightMultipliers public weightMultipliers = WeightMultipliers(1, 2, 1);

	/*==================================================== Constructor ===========================================================*/
	constructor(
		address _vaultRegistry,
		address _timelock
	) AccessControlBase(_vaultRegistry, _timelock) {
		unstakeBurnPercentage = 5e15; // 0.5% default
	}

	/*===================================================== FUNCTIONS ============================================================*/
	/*=================================================== View Functions =========================================================*/
	/**
	 *
	 * @dev Calculates the pending reward for a given staker.
	 * @param account The address of the staker for whom to calculate the pending reward.
	 * @return pending The amount of pending WLP tokens that the staker is eligible to receive.
	 * @dev The function iterates over all active stakes for the given staker and calculates the pending rewards for each stake using the _pendingWLPOfStake() internal function.
	 * @dev The function is view-only and does not modify the state of the contract.
	 */
	function pendingVestingRewards(address account) external view returns (uint256 pending) {
		uint256[] memory activeIndexes = getActiveIndexes(account);

		for (uint256 i = 0; i < activeIndexes.length; i++) {
			StakeVesting memory stake = stakes[account][activeIndexes[i]];
			pending += _pendingWLPOfStake(stake);
		}
	}

	/**
	 *
	 * @dev Calculates the pending reward for a given staker with given index.
	 * @param account The address of the staker for whom to calculate the pending reward.
	 * @return pending The amount of pending WLP tokens that the staker is eligible to receive.
	 * @dev The function calculates the pending rewards for the stake using the _pendingWLPOfStake() internal function.
	 * @dev The function is view-only and does not modify the state of the contract.
	 */
	function pendingVestingByIndex(
		address account,
		uint256 index
	) external view returns (uint256 pending) {
		// Get the stake from the stakes mapping
		StakeVesting memory stake = stakes[account][index];
		// Calculate the pending reward for the stake
		pending = _pendingWLPOfStake(stake);
	}

	/**
	 *
	 * @param _account Address of staker
	 * @param _index index to calculate the withdrawable amount
	 * @return _withdrawable  withdrawable amount of WINR/vWINR
	 */
	function withdrawableTokens(
		address _account,
		uint256 _index
	) external view returns (uint256 _withdrawable) {
		// Get the stake from the stakes mapping
		StakeVesting memory _stake = stakes[_account][_index];
		// Calculate the withdrawable amount for the stake
		_withdrawable = _withdrawableByVesting(_stake);

		// Check if the vesting period has passed
		if (_stake.startTime + _stake.vestingDuration > block.timestamp) {
			_withdrawable = 0;
		}
	}

	/**
	 * @notice This function returns an array of indexes representing the active vesting stakes indexes for a given staker.
	 * @param staker The address of the staker
	 */
	function getActiveIndexes(address staker) public view returns (uint[] memory indexes) {
		indexes = activeVestingIndexes[staker];
	}

	/**
	 *
	 * @param _account Address of the staker
	 * @param _indexes Indexes of the vesting stakes to calculate the total staked amount
	 * @return _totalStaked The total amount of staked tokens across the specified vesting stakes
	 */
	function vestingStakedAmount(
		address _account,
		uint256[] calldata _indexes
	) external view returns (uint256 _totalStaked) {
		for (uint256 i = 0; i < _indexes.length; i++) {
			StakeVesting memory _stake = stakes[_account][_indexes[i]];
			_totalStaked += _stake.amount;
		}
	}

	/**
	 * @return _totalStakedVWINR The total amount of vWINR tokens staked in the contract
	 * @return _totalStakedWINR The total amount of WINR tokens staked in the contract
	 * @return _totalEarned The total profit earned
	 */
	function globalData()
		external
		view
		returns (uint256 _totalStakedVWINR, uint256 _totalStakedWINR, uint256 _totalEarned)
	{
		_totalStakedVWINR = totalStakedVestedWINR;
		_totalStakedWINR = totalStakedWINR;
		_totalEarned = totalEarned;
	}

	/**
	 *
	 * @param _account Address of staker
	 * @param _index Index of stake
	 * @return _stake Data of the stake
	 */
	function getVestingStake(
		address _account,
		uint256 _index
	) public view returns (StakeVesting memory _stake) {
		_stake = stakes[_account][_index];
	}

	/**
	 *
	 * @param _account Address of staker
	 * @return _length total stake count of the _account
	 */
	function getVestingStakeLength(address _account) external view returns (uint256 _length) {
		_length = stakes[_account].length;
	}

	function _calcDebt(uint256 _weight) internal view returns (uint256 debt) {
		debt = (_weight * accumProfitPerWeight) / PRECISION;
	}

	/**
	 *
	 * @dev Computes the weight of a specified amount of tokens based on its type and vesting status.
	 * @param amount The amount of tokens to compute the weight for.
	 * @param vested A boolean flag indicating whether the tokens are vested or not.
	 * @param vesting A boolean flag indicating whether the tokens are vesting or not, applicable only if the tokens are vested.
	 * @return The weight of the specified amount of tokens.
	 * @dev The function computes the weight of the specified amount of tokens based on its type and vesting status, using the weightMultipliers mapping.
	 * @dev The function does not modify the state of the contract and can only be called internally.
	 */
	function _calculateWeight(
		uint256 amount,
		bool vested,
		bool vesting
	) internal view returns (uint256) {
		return
			!vested ? amount * weightMultipliers.winr : vesting
				? amount * weightMultipliers.vWinrVesting
				: amount * weightMultipliers.vWinr;
	}

	/**
	 * @notice Computes the pending WLP amount of the stake.
	 * @param stake The stake for which to compute the pending amount.
	 * @return holderProfit The pending WLP amount.
	 */
	function _pendingWLPOfStake(StakeVesting memory stake) internal view returns (uint256) {
		// Compute the holder's profit as the product of their stake's weight and the accumulated profit per weight.
		uint256 holderProfit = ((stake.weight * accumProfitPerWeight) / PRECISION);
		// If the holder's profit is less than their profit debt, return zero.
		return holderProfit < stake.profitDebt ? 0 : holderProfit - stake.profitDebt;
	}

	/**
	 * @notice Calculates the amount of WINR/vWINR that should be burned upon unstaking.
	 * @param amount The amount of WINR/vWINR being unstaked.
	 * @return _burnAmount The amount of WINR/vWINR to be burned.
	 */
	function _computeBurnAmount(uint256 amount) internal view returns (uint256 _burnAmount) {
		// Calculate the burn amount as the product of the unstake burn percentage and the amount being unstaked.
		_burnAmount = (amount * unstakeBurnPercentage) / PRECISION;
	}

	/**
	 * @notice Computes the withdrawable amount of WINR for the stake.
	 * @param stake The stake for which to compute the withdrawable amount.
	 * @return withdrawable_ The withdrawable amount of WINR.
	 */
	function _withdrawableByVesting(
		StakeVesting memory stake
	) internal view returns (uint256 withdrawable_) {
		// Compute the total amount of time that the stake has been staked, in days.
		uint256 totalStakedDuration_ = (block.timestamp - stake.startTime) / 1 days;
		// Compute the minimum number of days required for staking in order to be eligible for a reward.
		uint256 _minDays = period.minDuration / 1 days;

		// If the stake duration is less than the minimum number of days, the holder cannot withdraw any tokens.
		if (totalStakedDuration_ < _minDays) {
			return 0;
		}

		// Otherwise, calculate the holder's profit as follows:
		if (block.timestamp > stake.startTime + stake.vestingDuration) {
			// If the vesting period has expired, then the holder can withdraw their full stake amount.
			totalStakedDuration_ = stake.vestingDuration / 1 days;
		}

		// Calculate the profit for the holder as the sum of the tokens earned on the first day and the additional tokens earned over time.
		withdrawable_ =
			stake.accTokenFirstDay +
			((stake.amount - stake.accTokenFirstDay) *
				(totalStakedDuration_ - _minDays)) /
			period.claimDuration;
	}

	/*================================================= External Functions =======================================================*/

	/**
	 * @dev This function cancels vesting stakes without penalty and reward.
	 * It sends the staked amount to the staker.
	 * @param index index to cancel vesting for
	 * @notice Throws an error if the stake has already been withdrawn
	 * @notice Emits a Cancel event upon successful execution
	 */
	function cancel(uint256 index) external {
		// Get the address of the caller
		address sender = msg.sender;

		// Declare local variables for stake and bool values
		StakeVesting memory stake;

		// Retrieve the stake and bool values for the given index and staker
		(stake) = getVestingStake(sender, index);

		// Check if the stake has already been withdrawn
		require(!stake.withdrawn, "stake has withdrawn");

		// Remove the index from the staker's active stakes list
		_removeActiveIndex(sender, index);

		uint256 amount_ = stake.amount;

		// Mark the stake as cancelled in the mapping
		stakes[sender][index].cancelled = true;

		// Calculate the amount of tokens to burn and the amount of tokens to send to the staker
		uint256 burnAmount_ = _computeBurnAmount(amount_);
		uint256 sendAmount_ = amount_ - burnAmount_;
		totalStakedVestedWINR -= amount_;

		// Send the staked tokens to the staker
		tokenManager.sendVestedWINR(sender, sendAmount_);

		// Burn the remaining vesting tokens
		tokenManager.burnVestedWINR(burnAmount_);

		// Emit a Cancel event to notify listeners of the cancellation
		emit Cancel(sender, block.timestamp, index, burnAmount_, sendAmount_);
	}

	/**
	 * @dev Set the weight multipliers for each type of stake. Only callable by the governance address.
	 * @param _weightMultipliers Multiplier per weight for each type of stake
	 * @notice Emits a WeightMultipliersUpdate event upon successful execution
	 */
	function setWeightMultipliers(
		WeightMultipliers memory _weightMultipliers
	) external onlyGovernance {
		require(_weightMultipliers.vWinr != 0, "vWINR dividend multiplier can not be zero");
		require(
			_weightMultipliers.vWinrVesting != 0,
			"vWINR vesting multiplier can not be zero"
		);
		require(_weightMultipliers.winr != 0, "WINR multiplier can not be zero");
		// Set the weight multipliers to the provided values
		weightMultipliers = _weightMultipliers;

		// Emit an event to notify listeners of the update
		emit WeightMultipliersUpdate(_weightMultipliers);
	}

	/**
	 * @dev Set the percentage of tokens to burn upon unstaking. Only callable by the governance address.
	 * @param _unstakeBurnPercentage The percentage of tokens to burn upon unstaking
	 * @notice Emits an UnstakeBurnPercentageUpdate event upon successful execution
	 */
	function setUnstakeBurnPercentage(uint256 _unstakeBurnPercentage) external onlyGovernance {
		// Set the unstake burn percentage to the provided value
		unstakeBurnPercentage = _unstakeBurnPercentage;

		// Emit an event to notify listeners of the update
		emit UnstakeBurnPercentageUpdate(_unstakeBurnPercentage);
	}

	/**
	 * @dev Set the address of the token manager contract. Only callable by the governance address.
	 * @param _tokenManager The address of the token manager contract
	 */
	function setTokenManager(ITokenManager _tokenManager) external onlyGovernance {
		require(
			address(_tokenManager) != address(0),
			"token manager address can not be zero"
		);
		// Set the token manager to the provided address
		tokenManager = _tokenManager;
	}

	/**
	 * @dev Deposit vWINR tokens into the contract and create a vesting stake with the specified parameters
	 * @param amount The amount of vWINR tokens to deposit
	 * @param vestingDuration The duration of the vesting period in seconds
	 */
	function depositVesting(
		uint256 amount,
		uint256 vestingDuration
	) external isAmountNonZero(amount) nonReentrant whenNotPaused {
		uint256 vestingDurationInSeconds = vestingDuration * 1 days;
		require(
			vestingDurationInSeconds >= period.minDuration &&
				vestingDuration <= period.duration,
			"duration must be in period"
		);
		// Get the address of the caller
		address sender = msg.sender;
		uint256 weight = _calculateWeight(amount, true, true);
		// Calculate the profit debt for the stake based on its weight
		uint256 profitDebt = _calcDebt(weight);
		// Get the current timestamp as the start time for the stake
		uint256 startTime = block.timestamp;
		// Calculate the accumulated token value for the first day of the claim period
		uint256 accTokenFirstDay = (amount * period.minPercent) / PRECISION;
		// Calculate the daily accumulation rate for the claim period
		uint256 accTokenPerDay = (amount - accTokenFirstDay) / period.claimDuration;

		// Transfer the vWINR tokens from the sender to the token manager contract
		tokenManager.takeVestedWINR(sender, amount);

		totalWeight += weight;
		totalStakedVestedWINR += amount;

		// Create a new stake with the specified parameters and add it to the list of stakes for the sender
		stakes[sender].push(
			StakeVesting(
				amount,
				weight,
				vestingDurationInSeconds,
				profitDebt,
				startTime,
				accTokenFirstDay,
				accTokenPerDay,
				false,
				false
			)
		);

		// Get the index of the newly added stake and add it to the list of active stakes for the sender
		uint256 _index = stakes[msg.sender].length - 1;
		_addActiveIndex(msg.sender, _index);

		// Emit a Deposit event to notify listeners of the new stake
		emit DepositVesting(
			sender,
			_index,
			startTime,
			vestingDurationInSeconds,
			amount,
			profitDebt,
			true,
			true
		);
	}

	/**
	 *
	 *  @dev Function to claim rewards for a specified array of indexes.
	 *  @param indexes The array of indexes to claim rewards for.
	 *  @notice The function can only be called when the contract is not paused and is non-reentrant.
	 *  @notice The function throws an error if the array of indexes is empty.
	 */
	function claimVesting(uint256[] calldata indexes) external whenNotPaused nonReentrant {
		require(indexes.length > 0, "empty indexes");
		_claim(indexes, true);
	}

	/**
	 * @dev Withdraws staked tokens and claims rewards
	 * @param _index Index to withdraw
	 */
	function withdrawVesting(uint256 _index) external whenNotPaused nonReentrant {
		address sender_ = _msgSender();
		// Initialize an array of size 4 to store the amounts
		StakeVesting storage stake_ = stakes[sender_][_index];

		// Check that the withdrawal period for this stake has passed
		require(
			block.timestamp >= stake_.startTime + stake_.vestingDuration,
			"You can't withdraw the stake yet"
		);
		// Check that this stake has not already been withdrawn
		require(!stake_.withdrawn, "already withdrawn");
		// Check that this stake has not been cancelled
		require(!stake_.cancelled, "stake cancelled");

		// Redeemable WINR amount by stake
		uint256 redeemable_ = _withdrawableByVesting(stake_);
		// Redeemable WLP amount by stake
		uint256 reward_ = _pendingWLPOfStake(stake_);

		// Interact with external contracts to complete the withdrawal process
		if (redeemable_ > 0) {
			// Mint reward tokens if necessary
			tokenManager.mintOrTransferByPool(sender_, redeemable_);
		}

		uint256 amountToBurn = stake_.amount - redeemable_;

		// Mint WINR tokens to decrease total supply
		if (amountToBurn > 0) {
			// this code piece is used to decrease burn amount from WINR total supply
			tokenManager.mintWINR(address(tokenManager), amountToBurn);
			tokenManager.burnWINR(amountToBurn);
		}

		// Burn vested WINR tokens
		tokenManager.burnVestedWINR(stake_.amount);

		// Interactions
		if (reward_ > 0) {
			tokenManager.sendWLP(sender_, reward_);

			stakes[sender_][_index].profitDebt += reward_;
			totalProfit -= reward_;
			totalClaimed[sender_] += reward_;

			emit ClaimVesting(sender_, reward_, _index);
		}

		// Calculate the total amounts to be withdrawn
		// Mark this stake as withdrawn and remove its index from the active list
		stake_.withdrawn = true;
		_removeActiveIndex(sender_, _index);

		// Update the total weight and total staked amount
		totalWeight -= stake_.weight;
		totalStakedVestedWINR -= stake_.amount;

		// Emit an event to log the withdrawal
		emit Withdraw(
			sender_,
			block.timestamp,
			_index,
			stake_.weight,
			stake_.weight,
			stake_.amount
		);
	}

	/**
	 * @dev Withdraws staked tokens and claims rewards
	 * @param indexes Indexes to withdraw
	 */
	function withdrawVestingBatch(
		uint256[] calldata indexes
	) external whenNotPaused nonReentrant {
		address sender = msg.sender;
		// Initialize an array of size 4 to store the amounts
		uint256[4] memory _amounts;

		// Check effects for each stake to be withdrawn
		for (uint256 i = 0; i < indexes.length; i++) {
			// Get the stake and boolean values for this index
			uint256 index = indexes[i];
			StakeVesting storage stake = stakes[sender][index];

			// Check that the withdrawal period for this stake has passed
			require(
				block.timestamp >= stake.startTime + stake.vestingDuration,
				"You can't withdraw the stake yet"
			);

			// Check that this stake has not already been withdrawn
			require(!stake.withdrawn, "already withdrawn");

			// Check that this stake has not been cancelled
			require(!stake.cancelled, "stake cancelled");

			// Calculate the total amounts to be withdrawn
			_amounts[0] += stake.weight;
			_amounts[1] += _withdrawableByVesting(stake);
			_amounts[2] += _pendingWLPOfStake(stake);
			_amounts[3] += stake.amount;

			// Mark this stake as withdrawn and remove its index from the active list
			stake.withdrawn = true;
			_removeActiveIndex(sender, index);
		}

		// Interact with external contracts to complete the withdrawal process
		if (_amounts[1] > 0) {
			// Mint rewards tokens if necessary
			tokenManager.mintOrTransferByPool(sender, _amounts[1]);
		}

		// the calculation is amountToBurn = total withdraw weight - total withdraw amount;
		uint256 amountToBurn = _amounts[3] - _amounts[1];

		// Mint WINR tokens to decrease total supply
		if (amountToBurn > 0) {
			// this code piece is used to decrease burn amount from WINR total supply
			// Mint WINR tokens to the tokenManager contract
			tokenManager.mintWINR(address(tokenManager), amountToBurn);
			tokenManager.burnWINR(amountToBurn);
		}

		// Burn total vested WINR tokens
		tokenManager.burnVestedWINR(_amounts[3]);

		// Update the total weight and total staked amount
		totalWeight -= _amounts[0];
		totalStakedVestedWINR -= _amounts[3];

		// Claim rewards for remaining stakes
		_claim(indexes, false);

		// Emit an event to log the withdrawal
		emit WithdrawBatch(
			sender,
			block.timestamp,
			indexes,
			_amounts[1],
			_amounts[1],
			_amounts[3]
		);
	}

	/*================================================= Internal Functions =======================================================*/
	/**
	 * @dev Claims the reward for the specified stakes
	 * @param indexes Array of the indexes to claim
	 * @param isClaim Checks if the caller is the claim function
	 */
	function _claim(uint256[] calldata indexes, bool isClaim) internal {
		address sender = msg.sender;
		uint256 _totalFee;

		// Check
		for (uint256 i = 0; i < indexes.length; i++) {
			uint256 index = indexes[i];

			StakeVesting memory _stake = getVestingStake(sender, index);

			// Check that the stake has not been withdrawn
			if (isClaim) {
				require(!_stake.withdrawn, "Stake has already been withdrawn");
			}

			// Check that the stake has not been cancelled
			require(!_stake.cancelled, "Stake has been cancelled");

			uint256 _fee = _pendingWLPOfStake(_stake);
			_totalFee += _fee;
		}

		// Effects
		for (uint256 i = 0; i < indexes.length; i++) {
			uint256 index = indexes[i];
			stakes[sender][index].profitDebt += _totalFee;
		}

		totalProfit -= _totalFee;
		totalClaimed[sender] += _totalFee;

		// Interactions
		if (_totalFee > 0) {
			tokenManager.sendWLP(sender, _totalFee);
		}

		// Emit event
		emit ClaimVestingBatch(sender, _totalFee, indexes);
	}

	/**
	 *
	 *  @dev Internal function to remove an active vesting index for a staker.
	 *  @param staker The address of the staker.
	 *  @param index The index of the vesting schedule to remove.
	 */
	function _removeActiveIndex(address staker, uint index) internal {
		uint[] storage indexes;

		indexes = activeVestingIndexes[staker];

		uint length = indexes.length;

		// Find the index to remove
		for (uint i = 0; i < length; i++) {
			if (indexes[i] == index) {
				// Shift all subsequent elements left by one position
				for (uint j = i; j < length - 1; j++) {
					indexes[j] = indexes[j + 1];
				}
				// Remove the last element
				indexes.pop();
				return;
			}
		}
	}

	function _addActiveIndex(address staker, uint256 index) internal {
		uint[] storage indexes;

		indexes = activeVestingIndexes[staker];
		indexes.push(index);
	}

	function share(uint256 amount) external virtual override {}
}
