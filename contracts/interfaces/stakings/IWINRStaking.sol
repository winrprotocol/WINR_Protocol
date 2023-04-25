// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IWINRStaking {
	function share(uint256 amount) external;

	struct StakeDividend {
		uint256 amount;
		uint256 profitDebt;
		uint256 weight;
		uint128 depositTime;
	}

	struct StakeVesting {
		uint256 amount; // The amount of tokens being staked
		uint256 weight; // The weight of the stake, used for calculating rewards
		uint256 vestingDuration; // The duration of the vesting period in seconds
		uint256 profitDebt; // The amount of profit earned by the stake, used for calculating rewards
		uint256 startTime; // The timestamp at which the stake was created
		uint256 accTokenFirstDay; // The accumulated  WINR tokens earned on the first day of the stake
		uint256 accTokenPerDay; // The rate at which WINR tokens are accumulated per day
		bool withdrawn; // Indicates whether the stake has been withdrawn or not
		bool cancelled; // Indicates whether the stake has been cancelled or not
	}

	struct Period {
		uint256 duration;
		uint256 minDuration;
		uint256 claimDuration;
		uint256 minPercent;
	}

	struct WeightMultipliers {
		uint256 winr;
		uint256 vWinr;
		uint256 vWinrVesting;
	}

	/*==================================================== Events =============================================================*/

	event Donation(address indexed player, uint amount);
	event Share(uint256 amount, uint256 totalDeposit);
	event DepositVesting(
		address indexed user,
		uint256 index,
		uint256 startTime,
		uint256 endTime,
		uint256 amount,
		uint256 profitDebt,
		bool isVested,
		bool isVesting
	);

	event DepositDividend(
		address indexed user,
		uint256 amount,
		uint256 profitDebt,
		bool isVested
	);
	event Withdraw(
		address indexed user,
		uint256 withdrawTime,
		uint256 index,
		uint256 amount,
		uint256 redeem,
		uint256 vestedBurn
	);
	event WithdrawBatch(
		address indexed user,
		uint256 withdrawTime,
		uint256[] indexes,
		uint256 amount,
		uint256 redeem,
		uint256 vestedBurn
	);

	event Unstake(
		address indexed user,
		uint256 unstakeTime,
		uint256 amount,
		uint256 burnedAmount,
		bool isVested
	);
	event Cancel(
		address indexed user,
		uint256 cancelTime,
		uint256 index,
		uint256 burnedAmount,
		uint256 sentAmount
	);
	event ClaimVesting(address indexed user, uint256 reward, uint256 index);
	event ClaimVestingBatch(address indexed user, uint256 reward, uint256[] indexes);
	event ClaimDividend(address indexed user, uint256 reward, bool isVested);
	event ClaimDividendBatch(address indexed user, uint256 reward);
	event WeightMultipliersUpdate(WeightMultipliers _weightMultipliers);
	event UnstakeBurnPercentageUpdate(uint256 _unstakeBurnPercentage);
}
