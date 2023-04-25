// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "solmate/src/utils/ReentrancyGuard.sol";
import "../interfaces/core/IVault.sol";
import "../interfaces/core/IFeeCollector.sol";
import "../interfaces/core/IWLPManager.sol";
import "../interfaces/tokens/wlp/IUSDW.sol";
import "../interfaces/tokens/wlp/IMintable.sol";
import "./AccessControlBase.sol";

contract WLPManager is ReentrancyGuard, AccessControlBase, IWLPManager {
	/*==================== Constants *====================*/
	uint128 private constant PRICE_PRECISION = 1e30;
	uint32 private constant USDW_DECIMALS = 18;
	uint64 private constant WLP_PRECISION = 1e18;
	uint64 private constant MAX_COOLDOWN_DURATION = 48 hours;

	/*==================== State Variabes Operations *====================*/
	IVault public immutable override vault;
	address public immutable override usdw;
	address public immutable override wlp;
	address public feeCollector;
	uint256 public override cooldownDuration;
	uint256 public aumAddition;
	uint256 public aumDeduction;
	uint256 public reserveDeduction;

	// Percentages configuration
	uint256 public override maxPercentageOfWagerFee = 2000;
	uint256 public reserveDeductionOnCB = 5000; // 50% of AUM when CB is triggered

	bool public handlersEnabled = false;
	bool public collectFeesOnLiquidityEvent = false;
	bool public inPrivateMode = false;

	// Vault circuit breaker config
	bool public pausePayoutsOnCB = false;
	bool public pauseSwapOnCB = false;
	bool private circuitBreakerActive = false;

	mapping(address => uint256) public override lastAddedAt;
	mapping(address => bool) public isHandler;

	constructor(
		address _vault,
		address _usdw,
		address _wlp,
		uint256 _cooldownDuration,
		address _vaultRegistry,
		address _timelock
	) AccessControlBase(_vaultRegistry, _timelock) {
		vault = IVault(_vault);
		usdw = _usdw;
		wlp = _wlp;
		cooldownDuration = _cooldownDuration;
	}

	/*==================== Configuration functions *====================*/

	/**
	 * @notice when private mode is enabled, minting and redemption of WLP is not possible (it is disabled) - only exception is that if handlersEnabled is true, whitelisted handlers are able to mint and redeem WLP on behalf of others.
	 * @param _inPrivateMode bool to set private mdoe
	 */
	function setInPrivateMode(bool _inPrivateMode) external onlyGovernance {
		inPrivateMode = _inPrivateMode;
		emit PrivateModeSet(_inPrivateMode);
	}

	function setHandlerEnabled(bool _setting) external onlyTimelockGovernance {
		handlersEnabled = _setting;
		emit HandlerEnabling(_setting);
	}

	/**
	 * @dev since this function could 'steal' assets of LPs that do not agree with the action, it has a timelock on it
	 * @param _handler address of the handler that will be allowed to handle the WLPs wlp on their behalf
	 * @param _isActive bool setting (true adds a handlerAddress, false removes a handlerAddress)
	 */
	function setHandler(address _handler, bool _isActive) external onlyTimelockGovernance {
		isHandler[_handler] = _isActive;
		emit HandlerSet(_handler, _isActive);
	}

	/**
	 * @notice configuration function to set the max percentage of the wagerfees collected the referral can represent
	 * @dev this mechanism is in place as a backstop for a potential exploit of the referral mechanism
	 * @param _maxPercentageOfWagerFee configure value for the max percentage of the wagerfee
	 */
	function setMaxPercentageOfWagerFee(
		uint256 _maxPercentageOfWagerFee
	) external onlyGovernance {
		maxPercentageOfWagerFee = _maxPercentageOfWagerFee;
		emit MaxPercentageOfWagerFeeSet(_maxPercentageOfWagerFee);
	}

	/**
	 * @notice the cooldown durations sets a certain amount of seconds cooldown after a lp withdraw until a neext withdraw is able to be conducted
	 * @param _cooldownDuration amount of seconds for the cooldown
	 */
	function setCooldownDuration(uint256 _cooldownDuration) external override onlyGovernance {
		require(
			_cooldownDuration <= MAX_COOLDOWN_DURATION,
			"WLPManager: invalid _cooldownDuration"
		);
		cooldownDuration = _cooldownDuration;
		emit CoolDownDurationSet(_cooldownDuration);
	}

	/**
	 * @notice configuration confuction to set a AUM adjustment, this is useful for if due to some reason the calculation is wrong and needs to be corrected
	 * @param _aumAddition amount the calulated aum should be increased
	 * @param _aumDeduction amount the calculated aum should be decreased
	 */
	function setAumAdjustment(
		uint256 _aumAddition,
		uint256 _aumDeduction
	) external onlyGovernance {
		aumAddition = _aumAddition;
		aumDeduction = _aumDeduction;
		emit AumAdjustmentSet(_aumAddition, _aumDeduction);
	}

	/*==================== Operational functions WINR/JB *====================*/

	/**
	 * @notice the function that can mint WLP/ add liquidity to the vault
	 * @dev this function mints WLP to the msg sender, also this will mint USDW to this contract
	 * @param _token the address of the token being deposited as LP
	 * @param _amount the amount of the token being deposited
	 * @param _minUsdw the minimum USDW the callers wants his deposit to be valued at
	 * @param _minWlp the minimum amount of WLP the callers wants to receive
	 * @return wlpAmount_ returns the amount of WLP that was minted to the _account
	 */
	function addLiquidity(
		address _token,
		uint256 _amount,
		uint256 _minUsdw,
		uint256 _minWlp
	) external override nonReentrant returns (uint256 wlpAmount_) {
		if (inPrivateMode) {
			revert("WLPManager: action not enabled");
		}
		wlpAmount_ = _addLiquidity(
			_msgSender(),
			_msgSender(),
			_token,
			_amount,
			_minUsdw,
			_minWlp
		);
	}

	/**
	 * @notice the function that can mint WLP/ add liquidity to the vault (for a handler)
	 * @param _fundingAccount the address that will source the tokens to de deposited
	 * @param _account the address that will receive the WLP
	 * @param _token the address of the token being deposited as LP
	 * @param _amount the amount of the token being deposited
	 * @param _minUsdw the minimum USDW the callers wants his deposit to be valued at
	 * @param _minWlp the minimum amount of WLP the callers wants to receive
	 * @return wlpAmount_ returns the amount of WLP that was minted to the _account
	 */
	function addLiquidityForAccount(
		address _fundingAccount,
		address _account,
		address _token,
		uint256 _amount,
		uint256 _minUsdw,
		uint256 _minWlp
	) external override nonReentrant returns (uint256 wlpAmount_) {
		_validateHandler();
		wlpAmount_ = _addLiquidity(
			_fundingAccount,
			_account,
			_token,
			_amount,
			_minUsdw,
			_minWlp
		);
	}

	/**
	 * @param _tokenOut address of the token the redeemer wants to receive
	 * @param _wlpAmount  amount of wlp tokens to be redeemed for _tokenOut
	 * @param _minOut minimum amount of _tokenOut the redemeer wants to receive
	 * @param _receiver  address that will reive the _tokenOut assets
	 * @return tokenOutAmount_ uint256 amount of the tokenOut the caller receives (for their burned WLP)
	 */
	function removeLiquidity(
		address _tokenOut,
		uint256 _wlpAmount,
		uint256 _minOut,
		address _receiver
	) external override nonReentrant returns (uint256 tokenOutAmount_) {
		if (inPrivateMode) {
			revert("WLPManager: action not enabled");
		}
		tokenOutAmount_ = _removeLiquidity(
			_msgSender(),
			_tokenOut,
			_wlpAmount,
			_minOut,
			_receiver
		);
	}

	/**
	 * @notice handler remove liquidity function - redeems WLP for selected asset
	 * @param _account  the address that will source the WLP  tokens
	 * @param _tokenOut address of the token the redeemer wants to receive
	 * @param _wlpAmount  amount of wlp tokens to be redeemed for _tokenOut
	 * @param _minOut minimum amount of _tokenOut the redemeer wants to receive
	 * @param _receiver  address that will reive the _tokenOut assets
	 * @return tokenOutAmount_ uint256 amount of the tokenOut the caller receives
	 */
	function removeLiquidityForAccount(
		address _account,
		address _tokenOut,
		uint256 _wlpAmount,
		uint256 _minOut,
		address _receiver
	) external override nonReentrant returns (uint256 tokenOutAmount_) {
		_validateHandler();
		tokenOutAmount_ = _removeLiquidity(
			_account,
			_tokenOut,
			_wlpAmount,
			_minOut,
			_receiver
		);
	}

	/**
	 * @notice the circuit breaker configuration
	 * @param _pausePayoutsOnCB bool to set if the cb should pause payouts the vault in case of a circuit breaker level trigger
	 * @param _pauseSwapOnCB bool to set if the cb should pause the entire protocol in case of a circuit breaker trigger
	 * @param _reserveDeductionOnCB percentage amount deduction config for the cb to reduce max wager amount after a cb trigger
	 */
	function setCiruitBreakerPolicy(
		bool _pausePayoutsOnCB,
		bool _pauseSwapOnCB,
		uint256 _reserveDeductionOnCB
	) external onlyManager {
		pausePayoutsOnCB = _pausePayoutsOnCB;
		pauseSwapOnCB = _pauseSwapOnCB;
		reserveDeductionOnCB = _reserveDeductionOnCB;
		emit CircuitBreakerPolicy(pausePayoutsOnCB, pauseSwapOnCB, reserveDeductionOnCB);
	}

	/**
	 * @notice function called by the vault when the circuit breaker is triggered (poolAmount under configured minimum)
	 * @param _token the address of the token that triggered the Circuit Breaker in the vault
	 */
	function circuitBreakerTrigger(address _token) external {
		if (circuitBreakerActive) {
			// circuit breaker is already active, so we return to vault
			return;
		}
		require(
			_msgSender() == address(vault),
			"WLPManager: only vault can trigger circuit break"
		);
		circuitBreakerActive = true;
		// execute the circuit breaker policy for payouts
		vault.setPayoutHalted(pausePayoutsOnCB);
		// execute the circuit breaker policy for external swaps
		vault.setIsSwapEnabled(pauseSwapOnCB);
		// if AUM deduction is set, we will lower the AUM by the configured percentage
		// a lower AUM will also mean a lower max
		if (reserveDeductionOnCB != 0) {
			// get the current AUM (without any deductions)
			uint256 aum_ = getAum(true);
			// caculate the deduction percentage, so if AUM is 2M and the deduction is 50%, we will deduct 1M
			reserveDeduction = (aum_ * reserveDeductionOnCB) / 10000;
			// with the deduction of the circuit breaker we will not lower the WLP, but we will lower the getReserves() function in the vault
			// this getReseres() function is used to calculate the max wager amount. Thus the trigger of the circuit breaker can drastically lower the max wager!
			// of course the policy of deducting the maxWager only makes sense if the payouts are not paused. If payouts are paused by the circuit breaker no wager can be made anyway.
		}
		emit CircuitBreakerTriggered(
			_token,
			pausePayoutsOnCB,
			pauseSwapOnCB,
			reserveDeductionOnCB
		);
	}

	/**
	 * @notice functuion that undoes/resets the circuitbreaker
	 */
	function resetCircuitBreaker() external onlyManager {
		circuitBreakerActive = false;
		vault.setPayoutHalted(false);
		vault.setIsSwapEnabled(true);
		reserveDeduction = 0;
		emit CircuitBreakerReset(pausePayoutsOnCB, pauseSwapOnCB, reserveDeductionOnCB);
	}

	/*==================== View functions WINR/JB *====================*/

	/**
	 * @notice returns the value of 1 wlp token in USD (scaled 1e30)
	 * @param _maximise when true, the assets maxPrice will be used (upper bound), when false lower bound will be used
	 * @return tokenPrice_ returns price of a single WLP token
	 */
	function getPriceWlp(bool _maximise) external view returns (uint256 tokenPrice_) {
		uint256 supply_ = IERC20(wlp).totalSupply();
		if (supply_ == 0) {
			return 0;
		}
		tokenPrice_ = ((getAum(_maximise) * WLP_PRECISION) / supply_);
	}

	/**
	 * @notice returns the WLP price of 1 WLP token denominated in USDW (so in 1e18, $1 = 1e18)
	 * @param _maximise when true, the assets maxPrice will be used (upper bound), when false lower bound will be used
	 */
	function getPriceWLPInUsdw(bool _maximise) external view returns (uint256 tokenPrice_) {
		uint256 supply_ = IERC20(wlp).totalSupply();
		if (supply_ == 0) {
			return 0;
		}
		tokenPrice_ = ((getAumInUsdw(_maximise) * WLP_PRECISION) / supply_);
	}

	/**
	 * @notice function that returns the total vault AUM in USDW
	 * @param _maximise bool signifying if the maxPrices of the tokens need to be used
	 * @return aumUSDW_ the amount of aum denomnated in USDW tokens
	 * @dev the USDW tokens are 1e18 scaled, not 1e30 as the USD value is represented
	 */
	function getAumInUsdw(bool _maximise) public view override returns (uint256 aumUSDW_) {
		aumUSDW_ = (getAum(_maximise) * (10 ** USDW_DECIMALS)) / PRICE_PRECISION;
	}

	/**
	 * @notice returns the total value of all the assets in the WLP/Vault
	 * @dev the USD value is scaled in 1e30, not 1e18, so $1 = 1e30
	 * @return aumAmountsUSD_ array with minimised and maximised AU<
	 */
	function getAums() external view returns (uint256[] memory aumAmountsUSD_) {
		aumAmountsUSD_ = new uint256[](2);
		aumAmountsUSD_[0] = getAum(true /** use upper bound oracle price for assets */);
		aumAmountsUSD_[1] = getAum(false /** use lower bound oracle price for assets */);
	}

	/**
	 * @notice returns the total amount of AUM of the vault
	 * @dev take note that 1 USD is 1e30, this function returns the AUM in this format
	 * @param _maximise bool indicating if the max price need to be used for the aum calculation
	 * @return aumUSD_ the total aum (in USD) of all the whtielisted assets in the vault
	 */
	function getAum(bool _maximise) public view returns (uint256 aumUSD_) {
		IVault _vault = vault;
		uint256 length_ = _vault.allWhitelistedTokensLength();
		uint256 aum_ = aumAddition;
		for (uint256 i = 0; i < length_; ++i) {
			address token_ = _vault.allWhitelistedTokens(i);
			// if token is not whitelisted, don't count it to the AUM
			uint256 price_ = _maximise
				? _vault.getMaxPrice(token_)
				: _vault.getMinPrice(token_);
			aum_ += ((_vault.poolAmounts(token_) * price_) /
				(10 ** _vault.tokenDecimals(token_)));
		}
		uint256 aumD_ = aumDeduction;
		aumUSD_ = aumD_ > aum_ ? 0 : (aum_ - aumD_);
	}

	/*==================== Internal functions WINR/JB *====================*/

	/**
	 * @notice function used by feecollector to mint WLP tokens
	 * @dev this function is only active when
	 * @param _token address of the token the WLP will be minted for
	 * @param _amount amount of tokens to be added to the vault pool
	 * @param _minUsdw minimum amount of USDW tokens to be received
	 * @param _minWlp minimum amount of WLP tokens to be received
	 */
	function addLiquidityFeeCollector(
		address _token,
		uint256 _amount,
		uint256 _minUsdw,
		uint256 _minWlp
	) external returns (uint256 wlpAmount_) {
		require(
			_msgSender() == feeCollector,
			"WLP: only fee collector can call this function"
		);
		wlpAmount_ = _addLiquidity(
			_msgSender(),
			_msgSender(),
			_token,
			_amount,
			_minUsdw,
			_minWlp
		);
	}

	/**
	 * @param _feeCollector address of the fee collector
	 */
	function setFeeCollector(address _feeCollector) external onlyGovernance {
		feeCollector = _feeCollector;
	}

	/**
	 * @notice config function to enable or disable the collection of wlp fees on liquidity events (mint and burning)
	 * @dev this mechnism is in place to the sandwiching of the distribution of wlp fees
	 * @param _collectFeesOnLiquidityEvent bool set to true to enable the collection of fees on liquidity events
	 */
	function setCollectFeesOnLiquidityEvent(
		bool _collectFeesOnLiquidityEvent
	) external onlyGovernance {
		collectFeesOnLiquidityEvent = _collectFeesOnLiquidityEvent;
	}

	/**
	 * @notice internal funciton that collects fees before a liquidity event
	 */
	function _collectFees() internal {
		// note: in the process of collecting fees and converting it into wlp the protocol 'by design' re-enters the WLPManager contract
		IFeeCollector(feeCollector).collectFeesBeforeLPEvent();
	}

	/**
	 * @notice internal function that calls the deposit function in the vault
	 * @dev calling this function requires an approval by the _funding account
	 * @param _fundingAccount address of the account sourcing the
	 * @param _account address that will receive the newly minted WLP tokens
	 * @param _tokenDeposit address of the token being deposited into the vault
	 * @param _amountDeposit amiunt of _tokenDeposit the caller is adding as liquiditty
	 * @param _minUsdw minimum amount of USDW the caller wants their deposited tokens to be worth
	 * @param _minWlp minimum amount of WLP the caller wants to receive
	 * @return mintAmountWLP_ amount of WLP tokens minted
	 */
	function _addLiquidity(
		address _fundingAccount,
		address _account,
		address _tokenDeposit,
		uint256 _amountDeposit,
		uint256 _minUsdw,
		uint256 _minWlp
	) private returns (uint256 mintAmountWLP_) {
		require(_amountDeposit != 0, "WLPManager: invalid _amount");
		if (collectFeesOnLiquidityEvent) {
			// prevent reentrancy looping if the wlp collection on mint/deposit is enabled
			collectFeesOnLiquidityEvent = false;
			// collect fees from vault and distribute to WLP holders (to prevent frontrunning of WLP feecollection)
			_collectFees();
			// set the configuration back to true, so that it
			collectFeesOnLiquidityEvent = true;
		}
		// cache address to save on SLOADs
		address wlp_ = wlp;
		// calculate aum before buyUSDW
		uint256 aumInUsdw_ = getAumInUsdw(true /**  get AUM using upper bound prices */);
		uint256 wlpSupply_ = IERC20(wlp_).totalSupply();

		// mechanism in place to prevent manipulation of wlp price by the first wlp minter
		bool firstMint_;
		if (wlpSupply_ == 0) {
			firstMint_ = true;
			// first mint must issue more than 10 WLP to ensure WLP pricing precision
			require((_minWlp >= 1e18), "WLPManager: too low WLP amount for first mint");
		}

		// transfer the tokens to the vault, from the user/source (_fundingAccount). note this requires an approval from the source address
		SafeERC20.safeTransferFrom(
			IERC20(_tokenDeposit),
			_fundingAccount,
			address(vault),
			_amountDeposit
		);
		// call the deposit function in the vault (external call)
		uint256 usdwAmount_ = vault.deposit(
			_tokenDeposit, // the token that is being deposited into the vault for WLP
			address(this) // the address that will receive the USDW tokens (minted by the vault)
		);
		// the vault has minted USDW to this contract (WLP Manager), the amount of USDW minted is equivalent to the value of the deposited tokens (in USD, scaled 1e18) now this WLP Manager contract has received usdw, 1e18 usdw is 1 USD 'debt'. If the caller has provided tokens worth $10k, then about 1e5 * 1e18 USDW will be minted. This ratio of value deposited vs amount of USDW minted will remain the same.

		// check if the amount of usdwAmount_ fits the expectation of the caller
		require(usdwAmount_ >= _minUsdw, "WLPManager: insufficient USDW output");
		/**
		 * Initially depositing 1 USD will result in 1 WLP, however as the value of the WLP grows (so historically the WLP LPs are in profit), a 1 USD deposit will result in less WLP, this because new LPs do not have the right to 'cash in' on the WLP profits that where earned bedore the LP entered the vault. The calculation below determines how much WLP will be minted for the amount of USDW deposited.
		 */
		mintAmountWLP_ = aumInUsdw_ == 0
			? usdwAmount_
			: ((usdwAmount_ * wlpSupply_) / aumInUsdw_);
		require(mintAmountWLP_ >= _minWlp, "WLPManager: insufficient WLP output");

		// only on the first mint 1 WLP will be sent to the timelock
		if (firstMint_) {
			mintAmountWLP_ -= 1e18;
			// mint 1 WLP to the timelock address to prevent any attack possible
			IMintable(wlp_).mint(timelockAddressImmutable, 1e18);
		}

		// wlp is minted to the _account address
		IMintable(wlp_).mint(_account, mintAmountWLP_);
		lastAddedAt[_account] = block.timestamp;
		emit AddLiquidity(
			_account,
			_tokenDeposit,
			_amountDeposit,
			aumInUsdw_,
			wlpSupply_,
			usdwAmount_,
			mintAmountWLP_
		);
		return mintAmountWLP_;
	}

	/**
	 * @notice internal function that withdraws assets from the vault
	 * @dev burns WLP, burns usdw, transfers tokenOut from the vault to the caller
	 * @param _account the addresss that wants to redeem its WLP from
	 * @param _tokenOut address of the token that the redeemer wants to receive for their wlp
	 * @param _wlpAmount the amount of WLP that is being redeemed
	 * @param _minOut the minimum amount of tokenOut the redeemer/remover wants to receive
	 * @param _receiver address the redeemer wants to receive the tokenOut on
	 * @return amountOutToken_ amount of the token redeemed from the vault
	 */
	function _removeLiquidity(
		address _account,
		address _tokenOut,
		uint256 _wlpAmount,
		uint256 _minOut,
		address _receiver
	) private returns (uint256 amountOutToken_) {
		require(_wlpAmount != 0, "WLPManager: invalid _wlpAmount");
		// check if there is a cooldown period
		require(
			(lastAddedAt[_account] + cooldownDuration) <= block.timestamp,
			"WLPManager: cooldown duration not yet passed"
		);
		// calculate how much the lower bound priced value is of all the assets in the WLP
		uint256 aumInUsdw_ = getAumInUsdw(false);
		// cache wlp address to save on SLOAD
		address wlp_ = wlp;
		// fetch how much WLP tokens are minted/outstanding
		uint256 wlpSupply_ = IERC20(wlp_).totalSupply();
		// when liquidity is removed, usdw needs to be burned, since the usdw token is an accounting token for debt (it is the value of the token when it was deposited, or transferred to the vault via a swap)
		uint256 usdwAmountToBurn_ = (_wlpAmount * aumInUsdw_) / wlpSupply_;
		// calculate how much USDW debt there is in total
		// cache address to save on SLOAD
		address usdw_ = usdw;
		uint256 usdwBalance_ = IERC20(usdw_).balanceOf(address(this));
		// check if there are enough USDW tokens to burn
		if (usdwAmountToBurn_ > usdwBalance_) {
			// auditor note: this situation, where usdw token need to be minted without actual tokens being deposited, can only occur when there are almost no WLPs left and the vault in general. Another requirement for this to occur is that the prices of assets in the vault are (far) lower at the time of withdrawal relative ti the time they where originally added to the vault.
			IUSDW(usdw_).mint(address(this), usdwAmountToBurn_ - usdwBalance_);
		}
		// burn the WLP token in the wallet of the LP remover, will fail if the _account doesn't have the WLP tokens in their wallet
		IMintable(wlp_).burn(_account, _wlpAmount);
		// usdw is transferred to the vault (where it will be burned)
		IERC20(usdw_).transfer(address(vault), usdwAmountToBurn_);
		// call the vault for the second step of the withdraw flow
		amountOutToken_ = vault.withdraw(_tokenOut, _receiver);
		// check if the amount of tokenOut the vault has returend fits the requirements of the caller
		require(amountOutToken_ >= _minOut, "WLPManager: insufficient output");
		emit RemoveLiquidity(
			_account,
			_tokenOut,
			_wlpAmount,
			aumInUsdw_,
			wlpSupply_,
			usdwAmountToBurn_,
			amountOutToken_
		);
		return amountOutToken_;
	}

	function _validateHandler() private view {
		require(handlersEnabled, "WLPManager: handlers not enabled");
		require(isHandler[_msgSender()], "WLPManager: forbidden");
	}
}
