// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../core/AccessControlBase.sol";
import "solmate/src/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/core/IVault.sol";
import "../interfaces/core/IVaultUtils.sol";
import "../interfaces/core/IWLPManager.sol";
import "../interfaces/referrals/IReferralStorage.sol";

contract ReferralStorage is ReentrancyGuard, Pausable, AccessControlBase, IReferralStorage {
	/*==================== Constants *====================*/
	uint256 private constant MAX_INTERVAL = 7 days;
	// BASIS_POINTS_DIVISOR is a constant representing 100%, used to calculate rates as basis points
	uint256 public constant BASIS_POINTS_DIVISOR = 1e4;
	// Vested WINR rate is 5% for all tiers
	uint256 public constant VESTED_WINR_RATE = 500;
	uint256 public withdrawInterval = 1 days; // the reward withdraw interval

	IVault public vault; // vault contract address
	IVaultUtils public vaultUtils; // vault utils contract address
	IWLPManager public wlpManager; // vault contract address
	IERC20 public wlp;

	// array with addresses of all tokens fees are collected in
	address[] public allWhitelistedTokens;
	mapping(address => bool) public referrerOnBlacklist;
	mapping(address => uint256) public override referrerTiers; // link between user <> tier
	mapping(uint256 => Tier) public tiers;
	mapping(bytes32 => address) public override codeOwners;
	mapping(address => bytes32) public override playerReferralCodes;
	mapping(address => uint256) public lastWithdrawTime; // to override default value in tier
	mapping(address => mapping(address => uint256)) public withdrawn; // to override default value in tier
	mapping(address => mapping(address => uint256)) public rewards; // to override default value in tier

	constructor(
		address _vaultRegistry,
		address _vaultUtils,
		address _vault,
		address _wlpManager,
		address _timelock
	) AccessControlBase(_vaultRegistry, _timelock) Pausable() {
		vault = IVault(_vault);
		wlpManager = IWLPManager(_wlpManager);
		wlp = IERC20(wlpManager.wlp());
		vaultUtils = IVaultUtils(_vaultUtils);
	}

	/**
	 *
	 * @dev setTier allows the governance to set the WLP and vWINR rates for a given tier
	 * @param _tierId the identifier for the tier being updated
	 * @param _WLPRate the new WLP rate, expressed as a percentage in basis points (1% = 100 basis points)
	 */
	function setTier(uint256 _tierId, uint256 _WLPRate) external override onlyGovernance {
		// require that the WLP rate is not greater than 100%
		require(_WLPRate <= BASIS_POINTS_DIVISOR, "ReferralStorage: invalid WLP Rate");

		// get the current tier object from storage
		Tier memory tier = tiers[_tierId];

		// update the WLP and vWINR rates in the tier object
		tier.WLPRate = _WLPRate;
		tier.vWINRRate = VESTED_WINR_RATE;

		// write the updated tier object back to storage
		tiers[_tierId] = tier;

		// emit an event to notify listeners of the tier update
		emit SetTier(_tierId, _WLPRate, VESTED_WINR_RATE);
	}

	/**
	 * @param _user address of the user
	 * @param _tierId ID of the tier
	 * @dev setReferrerTier allows the governance to set the tier for a given user
	 */
	function setReferrerTier(address _user, uint256 _tierId) external override onlyManager {
		// set the user's tier in storage
		referrerTiers[_user] = _tierId;

		// emit an event to notify listeners of the user tier update
		emit SetReferrerTier(_user, _tierId);
	}

	/**
	 *
	 * @param _account address of the user
	 * @param _code referral code
	 * @dev setPlayerReferralCode allows the manager role to set the referral code for a given user
	 */
	function setPlayerReferralCode(
		address _account,
		bytes32 _code
	) external override onlyManager {
		_setPlayerReferralCode(_account, _code);
	}

	/**
	 *
	 * @param _code referral code
	 * @dev setPlayerReferralCodeByUser allows the user to set the referral code
	 */
	function setPlayerReferralCodeByUser(bytes32 _code) external {
		_setPlayerReferralCode(msg.sender, _code);
	}

	/**
	 * @dev Sets the referral code for a player's address.
	 * @param _account The address of the player.
	 * @param _code The referral code to set for the player.
	 * @notice This function can only be called internally by the contract.
	 */
	function _setPlayerReferralCode(address _account, bytes32 _code) private {
		// Ensure that the player is not setting their own code.
		require(codeOwners[_code] != _account, "ReferralStorage: can not set own code");
		// Ensure that the code exists.
		require(codeOwners[_code] != address(0), "ReferralStorage: code does not exist");
		// Set the player's referral code.
		playerReferralCodes[_account] = _code;
		// Emit an event to log the referral code setting.
		emit SetPlayerReferralCode(_account, _code);
	}

	/**
	 * @dev Registers a referral code.
	 * @param _code The referral code to register.
	 * @notice This function can be called externally.
	 */
	function registerCode(bytes32 _code) external {
		// Ensure that the code is not empty.
		require(_code != bytes32(0), "ReferralStorage: invalid _code");
		// Ensure that the code does not already exist.
		require(codeOwners[_code] == address(0), "ReferralStorage: code already exists");

		// Set the code owner to the message sender.
		codeOwners[_code] = msg.sender;
		// Emit an event to log the code registration.
		emit RegisterCode(msg.sender, _code);
	}

	/**
	 * @dev Sets the owner of a referral code.
	 * @param _code The referral code to modify.
	 * @param _newAccount The new owner of the referral code.
	 * @notice This function can be called externally.
	 */
	function setCodeOwner(bytes32 _code, address _newAccount) external {
		// Ensure that the code is not empty.
		require(_code != bytes32(0), "ReferralStorage: invalid _code");

		// Get the current account owner of the code.
		address account = codeOwners[_code];

		// Ensure that the caller is the current account owner.
		require(msg.sender == account, "ReferralStorage: forbidden");

		// Set the new account owner for the code.
		codeOwners[_code] = _newAccount;

		// Emit an event to log the code owner change.
		emit SetCodeOwner(msg.sender, _newAccount, _code);
	}

	/**
	 * @dev Allows the governance to set the owner of a referral code.
	 * @param _code The referral code to modify.
	 * @param _newAccount The new owner of the referral code.
	 * @notice This function can be called externally only by the governance address.
	 */
	function govSetCodeOwner(bytes32 _code, address _newAccount) external override onlyManager {
		// Ensure that the code is not empty.
		require(_code != bytes32(0), "ReferralStorage: invalid _code");

		// Set the new account owner for the code.
		codeOwners[_code] = _newAccount;

		// Emit an event to log the code owner change.
		emit GovSetCodeOwner(_code, _newAccount);
	}

	/**
	 * @notice configuration function for
	 * @dev the configured withdraw interval cannot exceed the MAX_INTERVAL
	 * @param _timeInterval uint time interval for withdraw
	 */
	function setWithdrawInterval(uint256 _timeInterval) external onlyGovernance {
		require(_timeInterval <= MAX_INTERVAL, "ReferralStorage: invalid interval");
		withdrawInterval = _timeInterval;
		emit SetWithdrawInterval(_timeInterval);
	}

	/**
	 * @notice Changes the address of the vault contract.
	 * @param vault_ The new address of the vault contract.
	 * @dev This function can only be called by the Timelock governance contract.
	 * @dev The new vault address must not be null.
	 * @dev Emits a `VaultUpdated` event upon successful execution.
	 */
	function setVault(address vault_) public onlyTimelockGovernance {
		// Ensure that the new vault address is not null.
		_checkNotNull(vault_);

		// Update the vault address.
		vault = IVault(vault_);

		// Emit an event to log the update.
		emit VaultUpdated(vault_);
	}

	/**
	 * @notice Changes the address of the VaultUtils contract.
	 * @param vaultUtils_ The new address of the VaultUtils contract.
	 * @dev This function can only be called by the Timelock governance contract.
	 * @dev The new VaultUtils address must not be null.
	 * @dev Emits a `VaultUtilsUpdated` event upon successful execution.
	 */
	function setVaultUtils(address vaultUtils_) public onlyTimelockGovernance {
		// Ensure that the new VaultUtils address is not null.
		_checkNotNull(vaultUtils_);

		// Update the VaultUtils address.
		vaultUtils = IVaultUtils(vaultUtils_);

		// Emit an event to log the update.
		emit VaultUtilsUpdated(vaultUtils_);
	}

	/**
	 * @notice Changes the address of the WLP Manager contract and updates the WLP token contract address.
	 * @param wlpManager_ The new address of the WLP Manager contract.
	 * @dev This function can only be called by the Timelock governance contract.
	 * @dev The new WLP Manager address must not be null.
	 * @dev Updates the WLP token contract address to the new WLP Manager's WLP token contract address.
	 * @dev Emits a `WLPManagerUpdated` event upon successful execution.
	 */
	function setWlpManager(address wlpManager_) public onlyTimelockGovernance {
		// Ensure that the new WLP Manager address is not null.
		_checkNotNull(wlpManager_);

		// Update the WLP Manager address and the WLP token contract address.
		wlpManager = IWLPManager(wlpManager_);
		wlp = IERC20(wlpManager.wlp());

		_checkNotNull(address(wlp));

		// Emit an event to log the update.
		emit WLPManagerUpdated(address(wlpManager_));
	}

	/**
	 * @notice manually adds a tokenaddress to the vault
	 * @param _tokenToAdd address to manually add to the allWhitelistedTokensFeeCollector array
	 */
	function addTokenToWhitelistList(address _tokenToAdd) external onlyManager {
		allWhitelistedTokens.push(_tokenToAdd);
		emit TokenAddedToWhitelist(_tokenToAdd);
	}

	/**
	 * @notice deletes entire whitelist array
	 * @dev this function should be used before syncWhitelistedTokens is called!
	 */
	function deleteWhitelistTokenList() external onlyManager {
		delete allWhitelistedTokens;
		emit DeleteAllWhitelistedTokens();
	}

	function addReferrerToBlacklist(address _referrer, bool _setting) external onlyManager {
		referrerOnBlacklist[_referrer] = _setting;
		emit AddReferrerToBlacklist(_referrer, _setting);
	}

	function _referrerOnBlacklist(address _referrer) internal view returns (bool onBlacklist_) {
		onBlacklist_ = referrerOnBlacklist[_referrer];
	}

	/**
	 * @notice internal function that checks if an address is not 0x0
	 */
	function _checkNotNull(address _setAddress) internal pure {
		require(_setAddress != address(0x0), "FeeCollector: Null not allowed");
	}

	/**
	 * @notice calculates what is a percentage portion of a certain input
	 * @param _amountToDistribute amount to charge the fee over
	 * @param _basisPointsPercentage basis point percentage scaled 1e4
	 * @return amount_ amount to distribute
	 */
	function calculateRebate(
		uint256 _amountToDistribute,
		uint256 _basisPointsPercentage
	) public pure returns (uint256 amount_) {
		amount_ = ((_amountToDistribute * _basisPointsPercentage) / BASIS_POINTS_DIVISOR);
	}

	/**
	 * @notice Synchronizes the whitelisted tokens between the vault and the this contract.
	 * @dev This function can only be called by the Manager.
	 * @dev Deletes all tokens in the `allWhitelistedTokens` array and adds the whitelisted tokens retrieved from the vault.
	 * @dev Emits a `SyncTokens` event upon successful execution.
	 */
	function syncWhitelistedTokens() public onlyManager {
		// Clear the `allWhitelistedTokens` array.
		delete allWhitelistedTokens;

		// Get the count of whitelisted tokens in the vault and add them to the `allWhitelistedTokens` array.
		uint256 count_ = vault.allWhitelistedTokensLength();
		for (uint256 i = 0; i < count_; ++i) {
			address token_ = vault.allWhitelistedTokens(i);
			// bool isWhitelisted_ = vault.whitelistedTokens(token_);
			// // if token is not whitelisted, don't add it to the whitelist
			// if (!isWhitelisted_) {
			// 	continue;
			// }
			allWhitelistedTokens.push(token_);
		}

		// Emit an event to log the synchronization.
		emit SyncTokens();
	}

	/**
	 * @notice Returns the referral code and referrer address for a given player.
	 * @param _account The player's address for which to retrieve the referral information.
	 * @return code_ The player's referral code.
	 * @return referrer_ The player's referrer address.
	 * @dev If the referrer is on the blacklist, the referrer address is set to 0x0.
	 */
	function getPlayerReferralInfo(
		address _account
	) public view override returns (bytes32 code_, address referrer_) {
		// Retrieve the player's referral code from the playerReferralCodes mapping.
		code_ = playerReferralCodes[_account];

		// If the player has a referral code, retrieve the referrer address from the codeOwners mapping.
		if (code_ != bytes32(0)) {
			referrer_ = codeOwners[code_];
		}

		// Check if the referrer is on the blacklist, if yes, set the referrer address to 0x0.
		if (_referrerOnBlacklist(referrer_)) {
			referrer_ = address(0);
		}

		// Return the player's referral code and referrer address.
		return (code_, referrer_);
	}

	/**
	 *
	 * @dev Returns the vested WINR rate of the player
	 * @param _account Address of the player
	 * @return uint256 Vested WINR rate of the player
	 * @notice If the player has no referrer, the rate is 0
	 * @notice This function overrides the getPlayerVestedWINRRate function in the IReferralSystem interface
	 */
	function getPlayerVestedWINRRate(address _account) public view override returns (uint256) {
		// Get the referral code of the player's referrer
		bytes32 code_ = playerReferralCodes[_account];
		// If the player has no referrer, return a vested WINR rate of 0
		if (code_ == bytes32(0)) {
			return 0;
		}

		// Return the vested WINR rate of the player's referrer's tier
		return tiers[referrerTiers[codeOwners[code_]]].vWINRRate;
	}

	/**
	 * @notice function that checks if a player has a referrer
	 * @param _player address of the player
	 * @return isReferred_ true if the player has a referrer
	 */
	function isPlayerReferred(address _player) public view returns (bool isReferred_) {
		(, address referrer_) = getPlayerReferralInfo(_player);
		isReferred_ = (referrer_ != address(0));
	}

	/**
	 * @notice function that returns the referrer of a player
	 * @param _player address of the player
	 * @return referrer_ address of the referrer
	 */
	function returnPlayerRefferalAddress(
		address _player
	) public view returns (address referrer_) {
		(, referrer_) = getPlayerReferralInfo(_player);
		return referrer_;
	}

	/**
	 * @notice function that sets the reward for a referrer
	 * @param _player address of the player
	 * @param _token address of the token
	 * @param _amount amount of the token to reward the referrer with (max)
	 */
	function setReward(address _player, address _token, uint256 _amount) external onlyManager {
		address referrer_ = returnPlayerRefferalAddress(_player);

		if (referrer_ != address(0)) {
			// the player has a referrer
			// calculate the rebate for the referrer tier
			uint256 amountRebate_ = calculateRebate(
				_amount,
				tiers[referrerTiers[referrer_]].WLPRate
			);
			// nothing to rebate, return early but emit event
			if (amountRebate_ == 0) {
				emit Reward(referrer_, _player, _token, 0);
				return;
			}

			// add the rebate to the rewards mapping of the referrer
			unchecked {
				rewards[referrer_][_token] += amountRebate_;
			}

			// add the rebate to the referral reserves of the vault (to keep it aside from the wagerFeeReserves)
			IVault(vault).setAsideReferral(_token, amountRebate_);

			emit Reward(referrer_, _player, _token, _amount);
		}
		emit NoRewardToSet(_player);
	}

	function removeReward(
		address _player,
		address _token,
		uint256 _amount
	) external onlyManager {
		address referrer_ = returnPlayerRefferalAddress(_player);

		if (referrer_ != address(0)) {
			// the player has a referrer
			// calculate the rebate for the referrer tier
			uint256 amountRebate_ = calculateRebate(
				_amount,
				tiers[referrerTiers[referrer_]].WLPRate
			);
			// nothing to rebate, return early
			if (amountRebate_ == 0) {
				return;
			}

			if (rewards[referrer_][_token] >= amountRebate_) {
				rewards[referrer_][_token] -= amountRebate_;
				// remove the rebate to the referral reserves of the vault
				IVault(vault).removeAsideReferral(_token, amountRebate_);
			}

			emit RewardRemoved(referrer_, _player, _token, _amount);
		}
	}

	/**
	 *
	 * @dev Allows a referrer to claim their rewards in the form of WLP tokens.
	 * @dev Referrers cannot be on the blacklist.
	 * @dev Rewards can only be withdrawn once per withdrawInterval.
	 * @dev Calculates the total WLP amount and updates the withdrawn rewards.
	 * @dev Transfers the WLP tokens to the referrer.
	 */
	function claim() public whenNotPaused nonReentrant {
		address referrer_ = _msgSender();

		require(!_referrerOnBlacklist(referrer_), "Referrer is blacklisted");

		uint256 lastWithdrawTime_ = lastWithdrawTime[referrer_];
		require(
			block.timestamp >= lastWithdrawTime_ + withdrawInterval,
			"Rewards can only be withdrawn once per withdrawInterval"
		);

		// check: update last withdrawal time
		lastWithdrawTime[referrer_] = block.timestamp;

		// effects: calculate total WLP amount and update withdrawn rewards
		uint256 totalWlpAmount_;
		address[] memory wlTokens_ = allWhitelistedTokens;
		for (uint256 i = 0; i < wlTokens_.length; ++i) {
			address token_ = wlTokens_[i];
			uint256 amount_ = rewards[referrer_][token_] - withdrawn[referrer_][token_];
			withdrawn[referrer_][token_] = rewards[referrer_][token_];

			// interactions: convert token rewards to WLP
			if (amount_ > 0) {
				totalWlpAmount_ += _convertReferralTokensToWLP(token_, amount_);
			}
		}
		// transfer WLP tokens to referrer
		if (totalWlpAmount_ > 0) {
			wlp.transfer(referrer_, totalWlpAmount_);
		}
		emit Claim(referrer_, totalWlpAmount_);
	}

	/**
	 *
	 * @param _referrer address of the referrer
	 * @dev returns the amount of WLP that can be claimed by the referrer
	 * @dev this function is used by the frontend to show the amount of WLP that can be claimed
	 */
	function getPendingWLPRewards(
		address _referrer
	) public view returns (uint256 totalWlpAmount_) {
		address[] memory wlTokens_ = allWhitelistedTokens;

		// Loop through each whitelisted token
		for (uint256 i = 0; i < wlTokens_.length; ++i) {
			// Get the address of the current token
			address token_ = wlTokens_[i];

			// Calculate the amount of the current token that can be claimed by the referrer
			uint256 amount_ = rewards[_referrer][token_] - withdrawn[_referrer][token_];

			// If the referrer can claim some of the current token, calculate the WLP amount
			if (amount_ != 0) {
				// Get the minimum price of the current token from the vault
				uint256 priceIn_ = vault.getMinPrice(token_);

				// Calculate the USDW amount of the current token
				uint256 usdwAmount_ = (amount_ * priceIn_) / 1e30;

				// Convert the USDW amount to the same decimal scale as the current token
				usdwAmount_ =
					(usdwAmount_ * 1e18) /
					(10 ** vault.tokenDecimals(token_));

				uint256 aumInUsdw_ = wlpManager.getAumInUsdw(true);

				// Calculate the WLP amount of the current token without deducting WLP minting fees
				uint256 amountWithFee_ = aumInUsdw_ == 0
					? usdwAmount_
					: ((usdwAmount_ * IERC20(wlp).totalSupply()) / aumInUsdw_);

				// Get the fee basis points for buying USDW with the current token
				uint256 feeBasisPoints_ = vaultUtils.getBuyUsdwFeeBasisPoints(
					token_,
					usdwAmount_
				);

				// Calculate the amount of WLP that can be claimed for the current token
				totalWlpAmount_ +=
					(amountWithFee_ *
						(BASIS_POINTS_DIVISOR - feeBasisPoints_)) /
					BASIS_POINTS_DIVISOR;
			}
		}
		return totalWlpAmount_;
	}

	/**
	 * @notice internal function that deposits tokens and returns amount of wlp
	 * @param _token token address of amount which wants to deposit
	 * @param _amount amount of the token collected (FeeCollector contract)
	 * @return wlpAmount_ amount of the token minted to this by depositing
	 */
	function _convertReferralTokensToWLP(
		address _token,
		uint256 _amount
	) internal returns (uint256 wlpAmount_) {
		uint256 currentWLPBalance_ = wlp.balanceOf(address(this));

		// approve WLPManager to spend the tokens
		IERC20(_token).approve(address(wlpManager), _amount);

		// WLPManager returns amount of WLP minted
		wlpAmount_ = wlpManager.addLiquidity(_token, _amount, 0, 0);

		// note: if we want to check if the mint was successful and the WLP actually sits in this contract, we should do it like this:
		require(
			wlp.balanceOf(address(this)) == currentWLPBalance_ + wlpAmount_,
			"ReferralStorage: WLP mint failed"
		);
	}

	function getReferrerTier(address _referrer) public view returns (Tier memory tier_) {
		// if the referrer is not registered as a referrer, it should return an error
		if (playerReferralCodes[_referrer] == bytes32(0)) {
			revert("ReferralStorage: Referrer not registered");
		}
		tier_ = tiers[referrerTiers[_referrer]];
	}

	/**
	 * @notice governance function to rescue or correct any tokens that end up in this contract by accident
	 * @dev this is a timelocked funciton
	 * @param _tokenAddress address of the token to be transferred out
	 * @param _amount amount of the token to be transferred out
	 * @param _recipient address of the receiver of the token
	 */
	function removeTokenByGoverance(
		address _tokenAddress,
		uint256 _amount,
		address _recipient
	) external onlyTimelockGovernance {
		IERC20(_tokenAddress).transfer(_recipient, _amount);
		emit TokenTransferredByTimelock(_tokenAddress, _recipient, _amount);
	}
}
