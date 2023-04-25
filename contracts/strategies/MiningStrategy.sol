// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "../interfaces/tokens/IWINR.sol";
import "../interfaces/core/ITokenManager.sol";
import "../interfaces/core/IVault.sol";
import "../core/AccessControlBase.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MiningStrategy is AccessControlBase {
	/*==================================================== Events =============================================================*/

	event MiningMultiplierChanged(int256 multiplier);
	event AddressesUpdated(IWINR token, IVault vault);
	event ConfigUpdated(uint256[] _percentages, Config[] _configs);
	event VolumeIncreased(uint256 _amount, uint256 newVolume);
	event VolumeDecreased(uint256 _amount, uint256 newVolume);

	/*==================================================== State Variables ====================================================*/

	struct Config {
		int256 maxMultiplier;
		int256 minMultiplier;
	}
	IWINR public WINR;
	IVault public vault;
	address public pool;
	IERC20 public pairToken;
	address public tokenManager;

	/// @notice max mint amount by games
	uint256 public immutable MAX_MINT;
	/// @notice Last parity of ETH/WINR
	uint256 public parity;
	/// @notice Last calculated multipliers index id
	uint256 public lastCalculatedIndex;
	/// @notice The volumes of given period duration
	mapping(uint256 => uint256) public dailyVolumes;
	/// @notice The volumes of given period duration
	mapping(uint256 => int256) public dailyVolumeCurrentMultiplier;
	/// @notice Last calculated multiplier
	int256 public currentMultiplier;
	/// @notice Start time of periods
	uint256 public volumeRecordStartTime = block.timestamp - 1 days;

	uint256[] public percentages;
	mapping(uint256 => Config) public halvings;

	/*==================================================== Constant Variables ==================================================*/

	/// @notice used to calculate precise decimals
	uint256 private constant PRECISION = 1e18;

	/*==================================================== Configurations ===========================================================*/

	constructor(
		address _vaultRegistry,
		address _timelock,
		uint256[] memory _percentages,
		Config[] memory _configs,
		uint256 _maxMint
	) AccessControlBase(_vaultRegistry, _timelock) {
		_updateHalvings(_percentages, _configs);
		currentMultiplier = _configs[0].maxMultiplier;
		MAX_MINT = _maxMint;
	}

	/**
	 *
	 * @dev Internal function to update the halvings mapping.
	 * @param _percentages An array of percentages at which the halvings will occur.
	 * @param _configs An array of configurations to be associated with each halving percentage.
	 * @notice The function requires that the lengths of the two input arrays must be equal.
	 * @notice Each configuration must have a non-zero value for both minMultiplier and maxMultiplier.
	 * @notice The minimum multiplier value must be less than the maximum multiplier value for each configuration.
	 * @notice For each percentage in the _percentages array, the corresponding configuration in the _configs array will be associated with the halvings mapping.
	 * @notice After the halvings are updated, the percentages and configurations arrays will be updated and a ConfigUpdated event will be emitted with the new arrays as inputs.
	 */
	function _updateHalvings(uint256[] memory _percentages, Config[] memory _configs) internal {
		require(_percentages.length == _configs.length, "Lengths must be equal");
		for (uint256 i = 0; i < _percentages.length; i++) {
			require(_configs[i].maxMultiplier != 0, "Max zero");
			require(_configs[i].minMultiplier != 0, "Min zero");
			require(
				_configs[i].minMultiplier < _configs[i].maxMultiplier,
				"Min greater than max"
			);
			halvings[_percentages[i]] = _configs[i];
		}

		percentages = _percentages;
		emit ConfigUpdated(_percentages, _configs);
	}

	/**
	 *
	 * @param _percentages An array of percentages at which the halvings will occur.
	 * @param _configs  An array of configurations to be associated with each halving percentage.
	 * @dev Allows the governance role to update the halvings mapping.
	 */
	function updateHalvings(
		uint256[] memory _percentages,
		Config[] memory _configs
	) public onlyGovernance {
		_updateHalvings(_percentages, _configs);
	}

	/**
	 *
	 * @dev Allows the governance role to update the contract's addresses for the WINR token, Vault, Pool, and Pair Token.
	 * @param _WINR The new address of the WINR token contract.
	 * @param _vault The new address of the Vault contract.
	 * @param _pool The new address of the Pool contract.
	 * @param _pairToken The new address of the Pair Token contract.
	 * @notice Each input address must not be equal to the zero address.
	 * @notice The function updates the corresponding variables with the new addresses.
	 * @notice After the addresses are updated, the parity variable is updated by calling the getParity() function.
	 * @notice Finally, an AddressesUpdated event is emitted with the updated WINR and Vault addresses.
	 */
	function updateAddresses(
		IWINR _WINR,
		IVault _vault,
		address _pool,
		IERC20 _pairToken
	) public onlyGovernance {
		require(address(_WINR) != address(0), "WINR address zero");
		require(address(_vault) != address(0), "Vault zero");
		require(_pool != address(0), "Pool zero");
		require(address(_pairToken) != address(0), "Pair Token zero");
		WINR = _WINR;
		vault = _vault;
		pool = _pool;
		pairToken = _pairToken;
		parity = getParity();

		emit AddressesUpdated(_WINR, _vault);
	}

	function setTokenManager(address _tokenManager) external onlyGovernance {
		tokenManager = _tokenManager;
	}

	/*==================================================== Volume ===========================================================*/

	function getVolumeDayIndex() public view returns (uint256 day_) {
		day_ = (block.timestamp - volumeRecordStartTime) / 1 days;
	}

	/**
    @dev Public function to get the daily volume of a specific day index.
    @param _dayIndex The index of the day for which to get the volume.
    @return volume_ The  volume of the specified day index.
    @notice This function takes a day index and returns the volume of that day,
    as stored in the dailyVolumes mapping.
    */
	function getVolumeOfDay(uint256 _dayIndex) public view returns (uint256 volume_) {
		volume_ = dailyVolumes[_dayIndex]; // Get the  volume of the specified day index from the dailyVolumes mapping
	}

	/**

    @dev Public function to calculate the dollar value of a given token amount.
    @param _token The address of the whitelisted token on the vault.
    @param _amount The amount of the given token.
    @return _dollarValue The dollar value of the given token amount.
    @notice This function takes the address of a whitelisted token on the vault and an amount of that token,
    and calculates the dollar value of that amount by multiplying the amount by the current dollar value of the token
    on the vault and dividing by 10^decimals of the token. The result is then divided by 1e12 to convert to USD.
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
	 * @dev External function to increase the volume of the current day index.
	 * @dev This function is called by the Token Manager to increase the volume of the current day index.
	 * @param _input The address of the token to increase the volume.
	 * @param _amount The amount of the token to increase the volume.
	 * @notice This function is called by the Token Manager to increase the volume
	 *  of the current day index. It calculates the dollar value of the token amount using
	 *  the computeDollarValue function, adds it to the volume of the current day
	 *  index, and emits a VolumeIncreased event with the updated volume.
	 */
	function increaseVolume(address _input, uint256 _amount) external onlyManager {
		uint256 _dayIndex = getVolumeDayIndex(); // Get the current day index to update the volume
		uint256 _dollarValue = computeDollarValue(_input, _amount); // Calculate the dollar value of the token amount using the computeDollarValue function
		dailyVolumes[_dayIndex] += _dollarValue; // Increase the volume of the current day index by the calculated dollar value
		emit VolumeIncreased(_dollarValue, dailyVolumes[_dayIndex]); // Emit a VolumeIncreased event with the updated volume
	}

	/**
	 *
	 * @dev External function to decrease the volume of the current day index.
	 * @dev This function is called by the Token Manager to decrease the volume of the current day index.
	 * @param _input The address of the token to decrease the volume.
	 * @param _amount The amount of the token to decrease the volume.
	 * @notice This function is called by the Token Manager to decrease the volume
	 *  of the current day index. It calculates the dollar value of the token amount using
	 *  the computeDollarValue function, subtracts it from the  volume of the current day
	 *  index, and emits a VolumeDecreased event with the updated volume.
	 */
	function decreaseVolume(address _input, uint256 _amount) external onlyManager {
		uint256 _dayIndex = getVolumeDayIndex(); // Get the current day index to update the  volume
		uint256 _dollarValue = computeDollarValue(_input, _amount); // Calculate the dollar value of the token amount using the computeDollarValue function
		dailyVolumes[_dayIndex] -= _dollarValue; // Decrease the  volume of the current day index by the calculated dollar value
		emit VolumeDecreased(_dollarValue, dailyVolumes[_dayIndex]); // Emit a VolumeDecreased event with the updated volume
	}

	/*================================================== Mining =================================================*/

	function getParity() public view returns (uint256 _value) {
		_value = (pairToken.balanceOf(pool) * PRECISION) / WINR.balanceOf(pool);
	}

	/**
	 * @notice This function calculates the mining multiplier based on the current day's volume and the previous day's volume
	 * @dev It takes in two parameters, the number of tokens minted by games and the maximum number of tokens that can be minted
	 * @dev It returns the current mining multiplier as an int256
	 * @dev _mintedByGames and MAX_MINT are using to halving calculation
	 * @param _mintedByGames The total minted Vested WINR amount
	 */
	function _getMultiplier(uint256 _mintedByGames) internal returns (int256) {
		// Get the current day's index
		uint256 index = getVolumeDayIndex();

		// If the current day's index is the same as the last calculated index, return the current multiplier
		if (lastCalculatedIndex == index) {
			return currentMultiplier;
		}

		// Get the current configuration based on the number of tokens minted by games and the maximum number of tokens that can be minted
		Config memory config = getCurrentConfig(_mintedByGames);

		// Get the volume of the previous day and the current day
		uint256 prevDayVolume = getVolumeOfDay(index - 1);
		uint256 currentDayVolume = getVolumeOfDay(index);

		// If either the current day's volume or the previous day's volume is zero, return the current multiplier
		if (currentDayVolume == 0 || prevDayVolume == 0) {
			dailyVolumeCurrentMultiplier[index] = currentMultiplier;
			return currentMultiplier;
		}

		// Calculate the percentage change in volume between the previous day and the current day
		int256 diff = int256(
			currentDayVolume > prevDayVolume
				? currentDayVolume - prevDayVolume
				: prevDayVolume - currentDayVolume
		);
		int256 periodChangeRate = (diff * int256(PRECISION)) / int256(prevDayVolume);

		// If the current day's volume is less than the previous day's volume, increase the multiplier, otherwise decrease it
		if (currentDayVolume < prevDayVolume) {
			currentMultiplier =
				(currentMultiplier * (1e18 + 2 * periodChangeRate)) /
				int256(PRECISION);
		} else {
			int256 decrease = (currentMultiplier * periodChangeRate) /
				int256(PRECISION);
			currentMultiplier = decrease > currentMultiplier
				? config.minMultiplier
				: currentMultiplier - decrease;
		}

		// Ensure the current multiplier is within the configured maximum and minimum range
		currentMultiplier = currentMultiplier > config.maxMultiplier
			? config.maxMultiplier
			: currentMultiplier;
		currentMultiplier = currentMultiplier < config.minMultiplier
			? config.minMultiplier
			: currentMultiplier;

		// Set the new multiplier for the current day and emit an event
		dailyVolumeCurrentMultiplier[index] = currentMultiplier;
		emit MiningMultiplierChanged(currentMultiplier);

		// Update the last calculated index and return the current multiplier
		lastCalculatedIndex = index;
		return currentMultiplier;
	}

	function calculate(
		uint256 _amount,
		uint256 _mintedByGames
	) external returns (uint256 _mintAmount) {
		_mintAmount =
			(_amount *
				((uint256(_getMultiplier(_mintedByGames)) * PRECISION) / parity)) /
			PRECISION;
	}

	function getCurrentConfig(
		uint256 _mintedByGames
	) public view returns (Config memory config) {
		uint256 ratio = (PRECISION * _mintedByGames) / MAX_MINT;
		uint8 index = findIndex(ratio);
		return halvings[percentages[index]];
	}

	function findIndex(uint256 ratio) internal view returns (uint8 index) {
		uint8 min = 0;
		uint8 max = uint8(percentages.length) - 1;

		while (min < max) {
			uint8 mid = (min + max) / 2;
			if (ratio < percentages[mid]) {
				max = mid;
			} else {
				min = mid + 1;
			}
		}

		return min;
	}
}
