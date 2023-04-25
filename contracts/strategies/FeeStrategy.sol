// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../interfaces/core/IVault.sol";
import "../core/AccessControlBase.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract FeeStrategy is AccessControlBase {
	/*==================================================== Events =============================================================*/

	event FeeMultiplierChanged(uint256 multiplier);

	event ConfigUpdated(uint256 maxMultiplier, uint256 minMultiplier);

	/*==================================================== State Variables ====================================================*/

	enum ReserveChangeType {
		PROFIT,
		LOSS
	}

	struct Config {
		uint256 maxMultiplier;
		uint256 minMultiplier;
	}

	struct PeriodReserve {
		uint256 totalAmount;
		uint256 profit;
		uint256 loss;
		ReserveChangeType changeType;
		uint256 currentMultiplier;
	}

	Config public config = Config(10_000_000_000_000_000, 2_000_000_000_000_000);

	/// @notice Last calculated multipliers index id
	uint256 public lastCalculatedIndex = 0;
	/// @notice Start time of periods
	uint256 public periodStartTime = block.timestamp - 1 days;
	/// @notice The reserve changes of given period duration
	mapping(uint256 => PeriodReserve) public periodReserves;
	/// @notice Last calculated multiplier
	uint256 public currentMultiplier;
	/// @notice Vault address
	IVault public vault;

	/*==================================================== Constant Variables ==================================================*/

	/// @notice used to calculate precise decimals
	uint256 private constant PRECISION = 1e18;

	/*==================================================== FUNCTIONS ===========================================================*/

	constructor(
		IVault _vault,
		address _vaultRegistry,
		address _timelock
	) AccessControlBase(_vaultRegistry, _timelock) {
		require(address(_vault) != address(0), "Vault address zero");
		vault = _vault;
		currentMultiplier = config.minMultiplier;
	}

	/**
	 *
	 * @param config_ max, min multipliers
	 * @notice funtion to set new max min multipliers config
	 */
	function updateConfig(Config memory config_) public onlyGovernance {
		require(config_.maxMultiplier != 0, "Max zero");
		require(config_.minMultiplier != 0, "Min zero");
		require(config_.minMultiplier < config_.maxMultiplier, "Min greater than max");

		config.maxMultiplier = config_.maxMultiplier;
		config.minMultiplier = config_.minMultiplier;

		emit ConfigUpdated(config_.maxMultiplier, config_.minMultiplier);
	}

	/**
	 *
	 * @param _vault address of vault
	 * @notice function to set vault address
	 */
	function setVault(IVault _vault) public onlyGovernance {
		require(address(_vault) != address(0), "vault zero address");
		vault = _vault;
	}

	/**
	 *
	 * @dev Public function to calculate the dollar value of a given token amount.
	 * @param _token The address of the whitelisted token on the vault.
	 * @param _amount The amount of the given token.
	 * @return _dollarValue The dollar value of the given token amount.
	 * @notice This function takes the address of a whitelisted token on the vault and an amount of that token,
	 *  and calculates the dollar value of that amount by multiplying the amount by the current dollar value of the token
	 *  on the vault and dividing by 10^decimals of the token. The result is then divided by 1e12 to convert to USD.
	 */
	function computeDollarValue(
		address _token,
		uint256 _amount
	) public view returns (uint256 _dollarValue) {
		uint256 _decimals = IERC20Metadata(_token).decimals(); // Get the decimals of the token using the IERC20Metadata interface
		_dollarValue = ((_amount * vault.getMinPrice(_token)) / 10 ** _decimals); // Calculate the dollar value by multiplying the amount by the current dollar value of the token on the vault and dividing by 10^decimals
		_dollarValue = _dollarValue / 1e12; // Convert the result to USD by dividing by 1e12
	}

	/**
	 *
	 * @param _token address of the wl token
	 * @return _totalLoss total loss on vault
	 * @return _totalProfit total profit on vault
	 * @notice function to read profit and loss from vault
	 */
	function _getProfitLoss(
		address _token
	) internal view returns (uint256 _totalLoss, uint256 _totalProfit) {
		(_totalLoss, _totalProfit) = vault.returnTotalOutAndIn(_token);
	}

	/**
	 *
	 * @dev Internal function to calculate the total profit and loss for the vault.
	 * @return _totalLoss The total loss in USD.
	 * @return _totalProfit The total profit in USD.
	 * @notice This function iterates over all whitelisted tokens in the vault and calculates the profit and loss
	 * in USD for each token using the _getProfitLoss() function. The dollar value of the profit and loss is
	 * calculated using the computeDollarValue() function, and the total profit and loss values are returned.
	 */
	function _computeProfitLoss()
		internal
		view
		returns (uint256 _totalLoss, uint256 _totalProfit)
	{
		// Get the length of the allWhitelistedTokens array
		uint256 _allWhitelistedTokensLength = vault.allWhitelistedTokensLength();

		// Iterate over all whitelisted tokens in the vault
		for (uint256 i = 0; i < _allWhitelistedTokensLength; i++) {
			address _token = vault.allWhitelistedTokens(i); // Get the address of the current token
			// if token is not whitelisted, don't count it to the AUM
			// if (!vault.whitelistedTokens(_token)) {
			// 	continue;
			// }
			(uint256 _loss, uint256 _profit) = _getProfitLoss(_token); // Calculate the profit and loss for the current token
			uint256 _lossInDollar = computeDollarValue(_token, _loss); // Convert the loss value to USD using the computeDollarValue() function
			uint256 _profitInDollar = computeDollarValue(_token, _profit); // Convert the profit value to USD using the computeDollarValue() function
			_totalLoss += _lossInDollar; // Add the loss value in USD to the total loss
			_totalProfit += _profitInDollar; // Add the profit value in USD to the total profit
		}
	}

	/**
	 *
	 * @param _index day index
	 * @param _wagerFee wager fee percentage in 1e18
	 * @notice function to set wager fee to vault for a given day
	 */
	function _setWagerFee(uint256 _index, uint256 _wagerFee) internal {
		periodReserves[_index].currentMultiplier = _wagerFee;
		vault.setWagerFee(_wagerFee);
		emit FeeMultiplierChanged(currentMultiplier);
	}

	/*================================================== Mining =================================================*/
	/**
	 * @dev Public function to get the current period index.
	 * @return periodIndex index of the day
	 */
	function getPeriodIndex() public view returns (uint256 periodIndex) {
		periodIndex = (block.timestamp - periodStartTime) / 1 days;
	}

	/**
	 *
	 * @dev Internal function to set period reserve with profit loss calculation.
	 * @param index The index of the day being processed.
	 * @notice This function updates the reserve for a given day based on the total profit and loss values
	 *  calculated by the _computeProfitLoss() function. It determines whether the reserve should be updated
	 *  due to a profit or loss and stores the result in the periodReserves array.
	 */
	function setReserve(uint256 index) internal {
		// Calculate the total loss and total profit values using the _computeProfitLoss() function
		(uint256 _totalLoss, uint256 _totalProfit) = _computeProfitLoss();

		// Declare variables for use in determining reserve change type and amount
		ReserveChangeType changeType_;
		uint256 amount_;

		// Determine whether the total profit is greater than or equal to the total loss
		if (_totalProfit >= _totalLoss) {
			amount_ = _totalProfit - _totalLoss; // Calculate the reserve amount as the difference between total profit and total loss
		} else {
			amount_ = _totalLoss - _totalProfit; // Calculate the reserve amount as the difference between total loss and total profit
		}

		// Determine whether the reserve change type should be set to PROFIT or LOSS
		bool isProfit = _totalProfit > _totalLoss;

		if (isProfit) {
			changeType_ = ReserveChangeType.PROFIT; // Set the reserve change type to PROFIT
		} else if (_totalLoss > _totalProfit) {
			changeType_ = ReserveChangeType.LOSS; // Set the reserve change type to LOSS
		}
		// If this is not the first day, check the previous day's reserve to see if it should be updated
		if (index > 1) {
			PeriodReserve memory prevReserve_ = periodReserves[index - 1]; // Get the previous day's reserve
			_totalProfit - prevReserve_.profit; // Subtract the previous day's profit from the total profit

			// Determine whether the reserve change type should be set to PROFIT or LOSS based on the difference between
			// the total profit and total loss for the current day and the previous day
			if (_totalProfit - prevReserve_.profit > _totalLoss - prevReserve_.loss) {
				changeType_ = ReserveChangeType.PROFIT;
			} else {
				changeType_ = ReserveChangeType.LOSS;
			}
		}

		// Store the updated reserve for the current day in the periodReserves array
		periodReserves[index] = PeriodReserve(
			amount_,
			_totalProfit,
			_totalLoss,
			changeType_,
			0
		);
	}

	/**
	 *
	 * @dev Public function to get the difference in reserve amounts between two periods.
	 * @param prevIndex The index of the previous period.
	 * @param currentIndex The index of the current period.
	 * @return prevPeriod_ The reserve information for the previous period.
	 * @return diffReserve_ The difference in reserve amounts between the two periods.
	 */
	function getDifference(
		uint256 prevIndex,
		uint256 currentIndex
	)
		public
		view
		returns (PeriodReserve memory prevPeriod_, PeriodReserve memory diffReserve_)
	{
		// Get the reserve information for the previous and current periods
		prevPeriod_ = periodReserves[prevIndex];
		PeriodReserve memory currentPeriod_ = periodReserves[currentIndex];

		// Calculate the difference in reserve amounts between the two periods
		if (prevPeriod_.totalAmount >= currentPeriod_.totalAmount) {
			diffReserve_.totalAmount =
				prevPeriod_.totalAmount -
				currentPeriod_.totalAmount;
		} else {
			diffReserve_.totalAmount =
				currentPeriod_.totalAmount -
				prevPeriod_.totalAmount;
		}

		// Set the change type of the difference reserve to the change type of the current period
		diffReserve_.changeType = currentPeriod_.changeType;
	}

	/**
	 *
	 * @dev Internal function to calculate the current multiplier.
	 * @notice This function calculates the current multiplier based on the reserve amount for the current period.
	 * @return The current multiplier as a uint256 value.
	 */
	function _getMultiplier() internal returns (uint256) {
		// Get the current period index
		uint256 index = getPeriodIndex();

		// If the current period index is the same as the last calculated index, return the current multiplier
		if (lastCalculatedIndex == index) {
			return currentMultiplier;
		}

		// Set the reserve for the current period index
		setReserve(index);

		// If the period index is less than 1, set the current multiplier to the minimum multiplier value
		if (index < 1) {
			currentMultiplier = config.minMultiplier;
		} else {
			// Calculate the difference in reserves between the current and previous periods
			(
				PeriodReserve memory prevPeriodReserve_,
				PeriodReserve memory diffReserve_
			) = getDifference(index - 1, index);
			uint256 diff = diffReserve_.totalAmount;
			uint256 periodChangeRate;

			// If the previous period reserve and the difference in reserves are not equal to zero, calculate the period change rate
			if (prevPeriodReserve_.totalAmount != 0 && diff != 0) {
				periodChangeRate =
					(diff * PRECISION) /
					prevPeriodReserve_.totalAmount;
			}

			// If the difference in reserves represents a loss, decrease the current multiplier accordingly
			if (diffReserve_.changeType == ReserveChangeType.LOSS) {
				uint256 decrease = (2 * (currentMultiplier * periodChangeRate)) /
					PRECISION;
				currentMultiplier = currentMultiplier > decrease
					? currentMultiplier - decrease
					: config.minMultiplier;
			}
			// Otherwise, increase the current multiplier according to the period change rate
			else if (periodChangeRate != 0) {
				currentMultiplier =
					(currentMultiplier * (1e18 + periodChangeRate)) /
					PRECISION;
			}

			// If the current multiplier exceeds the maximum multiplier value, set it to the maximum value
			currentMultiplier = currentMultiplier > config.maxMultiplier
				? config.maxMultiplier
				: currentMultiplier;

			// If the current multiplier is less than the minimum multiplier value, set it to the minimum value
			currentMultiplier = currentMultiplier < config.minMultiplier
				? config.minMultiplier
				: currentMultiplier;
		}

		// Update the last calculated index to the current period index
		lastCalculatedIndex = index;

		// Set the wager fee for the current period index and current multiplier
		_setWagerFee(index, currentMultiplier);

		// Return the current multiplier
		return currentMultiplier;
	}

	/**
	 *
	 * @param _token address of the input (wl) token
	 * @param _amount amount of the token
	 * @notice function to calculation with current multiplier
	 */
	function calculate(address _token, uint256 _amount) external returns (uint256 amount_) {
		uint256 _value = computeDollarValue(_token, _amount);
		amount_ = (_value * _getMultiplier()) / PRECISION;
	}
}
