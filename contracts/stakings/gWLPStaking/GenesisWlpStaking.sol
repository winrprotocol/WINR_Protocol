// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "solmate/src/utils/ReentrancyGuard.sol";
import "../../core/Access.sol";
import "../../tokens/wlp/interfaces/IBasicFDT.sol";

contract GenesisWlpStaking is Access, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using SafeERC20 for IBasicFDT;
  /*==================================================== Events =============================================================*/

  event Harvest(address indexed user, uint256 harvestAmount, uint256 wlpHarvestAmount);
  event UpdatePool(uint256 lastRewardBlock, uint256 stakedTokens, uint256 accRewardPerShare);
  event Deposit(address indexed user, uint256 amount);
  event Withdraw(address indexed user, uint256 amount);
  event SetWLP(IBasicFDT wlp);
  event SetWithdrawable();
  event RewardFunded(
    uint256 _amount,
    uint256 _fromBlock,
    uint256 _toBlock,
    uint256 _rewardPerBlock
  );
  event WLPFunded(uint256 _amount, uint256 _ratio);
  event UpdateRatio(uint256 _ratio);
  event RecoverToken(IERC20 _token, uint256 _amount);

  /*==================================================== State Variables ====================================================*/
  // Staking user for a pool
  struct StakerInfo {
    bool exist; // Whether the user has already staked in this pool
    uint256 amount; // The tokens quantity the user has staked.
    uint256 rewardDebt; // The amount relative to accumulatedRewardsPerShare the user can't get as reward
    uint256 wlpRewardDebt; // reward debt of WLP
    uint256 vWINRRewardDebt; // reward debt of vWINR
  }

  // Staking pool
  struct PoolInfo {
    uint256 tokensStaked; // Total tokens staked
    uint256 lastRewardedBlock; // Last block number the user had their rewards calculated
    uint256 accumulatedRewardsPerShare; // Accumulated rewards per share times ACC_REWARD_PRECISION
    uint256 totalWlpProfit; // Total profit obtained from the claimWLP() function
    uint256 wlpPerToken; // The amount of WLP token that can be claimed per staked token
    uint256 totalvWINRProfit; // Total profit obtained from the claimvWINR() function
    uint256 vWINRPerToken; // The amount of vWINR token that can be claimed per staked token
  }

  /// @notice Vested WINR address
  IERC20 public immutable vWINR;
  /// @notice Address of the GenesisWLP token.
  IERC20 public immutable gWLP;
  /// @notice stores unconverted gwlp amount
  uint256 public unconvertedGWLP;
  /// @notice WLP address
  IBasicFDT public WLP;
  /// @notice Info of each staker that stakes gWLP tokens.
  mapping(address => StakerInfo) private stakerInfo;
  /// @notice reward precision
  uint256 private constant ACC_REWARD_PRECISION = 1e12;
  ///@notice 18 decimals precision
  uint256 private constant PRECISION = 1e18;
  /// @notice Reward Token quantity per block.
  uint256 public rewardPerBlock;
  /// @notice a new pool
  PoolInfo public pool = PoolInfo(0, 0, 0, 0, 0, 0, 0);
  /// @notice end block of distrubition
  uint256 public lastBlock;
  /// @notice WLP/ gWLP
  uint256 public ratio;
  /// @notice withdraw active check
  bool public isWithdrawable;
  /// @notice variable to check WLP set
  bool public WLPSet;
  /// @notice stores allocated vWINR rewards
  uint256 public allocatedRewards;
  ///@notice Burn address (dead address)
  address public immutable burnAddress;

  /*==================================================== Constructor ========================================================*/

  constructor(IERC20 _gWLP, IERC20 _vWINR, address _gov, address _burnAddress) Access(_gov) {
    require(address(_gWLP) != address(0), "gWLP address zero");
    require(address(_vWINR) != address(0), "vWINR address zero");
    require(_gov != address(0), "gov address zero");
    gWLP = _gWLP;
    vWINR = _vWINR;
    unconvertedGWLP = gWLP.totalSupply(); // gWlp won't mint anymore
    burnAddress = _burnAddress;
  }

  /**
   *
   * @param _WLP The Ethereum address of the WLP contract, represented as an instance of the IERC20 interface.
   * @notice This function sets the WLP and claimWlp contract addresses.
   * @notice This function can only be called once, and is restricted to the governance address.
   */
  function setWLPAddress(IBasicFDT _WLP) external onlyGovernance {
    require(!WLPSet, "Addresses has already set");
    require(address(_WLP) != address(gWLP), "WLP can not be same with the gWLP");
    require(address(_WLP) != address(vWINR), "WLP can not be same with the vWINR");
    WLP = _WLP;

    WLPSet = true;

    emit SetWLP(_WLP);
  }

  /**
   *
   * @notice This function sets the isWithdrawable variable to true.
   * @notice This function can only be called by the governance address.
   */
  function setWithdrawable() external onlyGovernance {
    isWithdrawable = true;

    emit SetWithdrawable();
  }

  /**
   * @notice This function allows users to deposit gWLP tokens to this contract, which sets the "exist" status to true to prevent secondary deposits.
   * @notice This function can only be called once per address and is non-reentrant.
   */
  function deposit() external nonReentrant {
    // Check that the deposit amount is not zero
    uint256 amount_ = gWLP.balanceOf(msg.sender);
    require(amount_ != 0, "Deposit amount can't be zero");
    // Check that the staker is not already registered
    StakerInfo storage staker = stakerInfo[msg.sender];
    require(!staker.exist, "secondary deposit is not allowed");
    // Update pool rewards
    _updatePoolRewards();
    // Update staker information
    staker.amount = amount_;
    staker.rewardDebt = (staker.amount * pool.accumulatedRewardsPerShare) / ACC_REWARD_PRECISION;
    staker.exist = true;
    // Update pool information
    pool.tokensStaked += amount_;
    // Emit Deposit event
    emit Deposit(msg.sender, amount_);
    // Interact with gWLP contract to transfer tokens from the user to burn address
    gWLP.safeTransferFrom(msg.sender, burnAddress, amount_);
  }

  /**
   * @notice This function allows users to withdraw WLP tokens from the contract if the isWithdrawable variable is set to true.
   * @notice This function is non-reentrant and calls the harvest function.
   * @notice This function decreases uncorvertedGWLP amount.
   */
  function withdraw() external nonReentrant {
    require(isWithdrawable, "Withdraw is not active yet");
    require(WLPSet, "WLP address will be set");

    // Retrieve the staker information and check the staked amount
    StakerInfo storage staker = stakerInfo[msg.sender];
    uint256 amount_ = staker.amount;
    require(amount_ != 0, "Withdraw amount can't be zero");
    // Pay out pending rewards to the staker
    _harvest();
    // Update the staker's amount to zero
    staker.amount = 0;
    // Update the pool's tokens staked by subtracting the staked amount
    pool.tokensStaked -= amount_;
    // Update the amount of unconverted gWLP
    unconvertedGWLP -= amount_;
    // Compute the amount of WLP to withdraw, based on the staked amount and the ratio
    uint256 WLPAmount_ = (amount_ * ratio) / PRECISION;
    // Transfer the WLP tokens to the staker
    WLP.safeTransfer(msg.sender, WLPAmount_);
    // Emit a Withdraw event
    emit Withdraw(msg.sender, amount_);
  }

  /**
   *
   * @notice This function allows users to harvest their rewards.
   * @notice This function can only be called by stakers who have deposited gWLP tokens.
   * @notice This function is non-reentrant and calls the internal _harvest function.
   */
  function harvest() public nonReentrant {
    require(stakerInfo[msg.sender].exist, "staker does not exist");
    _harvest();
  }

  /**
   * @notice This internal function collects the accumulated vWINR and WLP rewards for the calling staker.
   * @notice This function calculates the vWINR and WLP rewards for the staker, updates their reward debts, and transfers the rewards to their wallet.
   * @notice This function is called by the harvest function and is non-reentrant.
   * @dev Executes the "check-effects-interactions" pattern to safely handle reward distribution
   *      1. Check:
   *          - Updates the pool rewards
   *          - Gets the StakerInfo storage for the calling address
   *          - Calculates the vWINR and WLP rewards for the staker
   *      2. Effects:
   *          - Adds the vWINR and WLP rewards to the staker's reward debt
   *          - Reduces the allocated rewards and the total WLP profit for the pool
   *      3. Interactions:
   *          - Transfers the vWINR and WLP rewards to the calling address if the rewards are greater than 0
   *      Emits a Harvest event with the staker's address, the amount of vWINR rewards harvested, and the amount of WLP rewards harvested.
   */
  function _harvest() internal {
    // update the rewards in the pool
    _updatePoolRewards();
    // get the staker information
    StakerInfo storage staker = stakerInfo[msg.sender];
    // compute the amount of vWINR and WLP to be rewarded to the staker
    uint256 rewardsToHarvest_ = _computevWINRAmount(staker);
    (uint256 wlpAmount_, uint256 vWINRAmount_) = _computeWLPReward(staker);
    // update the staker's rewardDebt and wlpRewardDebt
    staker.rewardDebt += rewardsToHarvest_;
    staker.wlpRewardDebt += wlpAmount_;
    staker.vWINRRewardDebt += vWINRAmount_;
    // update the allocatedRewards and totalWlpProfit in the pool
    allocatedRewards -= rewardsToHarvest_;
    pool.totalWlpProfit -= wlpAmount_;
    // transfer the rewards to the staker
    if (rewardsToHarvest_ != 0 || vWINRAmount_ != 0) {
      vWINR.safeTransfer(msg.sender, rewardsToHarvest_ + vWINRAmount_);
    }
    if (wlpAmount_ != 0) {
      WLP.safeTransfer(msg.sender, wlpAmount_);
    }
    emit Harvest(msg.sender, rewardsToHarvest_, wlpAmount_);
  }

  /**
   *
   * @param _staker The address of the staker
   * @return vWINRReward_ The pending vWINR reward of the specified staker
   * @return vWINRFromWLP_ The pending vWINR reward from the WLP distribution contract of the specified staker
   * @return WLP_ The pending WLP reward of the specified staker
   * @notice Returns the pending vWINR and WLP rewards for the specified staker.
   * The rewards are calculated based on the staker's staked amount and their share of the accumulated rewards.
   */
  function pendingRewards(
    address _staker
  ) external view returns (uint256 vWINRReward_, uint256 vWINRFromWLP_, uint256 WLP_) {
    StakerInfo memory staker = stakerInfo[_staker];
    // If the staker has staked tokens, calculate the pending rewards
    if (staker.amount != 0) {
      // Compute the pending vWINR rewards for the staker
      vWINRReward_ = _computevWINRAmount(staker);
      // Compute the pending WLP and vWINR rewards from the WLP distribution contract
      (WLP_, vWINRFromWLP_) = _computeWLPReward(staker);
    }
  }

  /**
   * @notice Function to claim WLP and vWINR rewards from the WLP distribution contract
   * @notice Updates the total WLP profit and the WLP per token value for the pool
   * @notice Updates the total vWINR profit and the vWINR per token value for the pool
   * @dev This function is called externally by aynone to claim WLP and vWINR rewards from the WLP distribution contract
   * @dev The WLP distribution contract must be set before calling this function
   * @dev The claimed WLP amount is added to the total WLP profit for the pool
   * @dev The claimed vWINR amount is added to the total vWINR profit for the pool
   * @dev The WLP per token value is updated based on the claimed amount and the total unconverted gWLP tokens
   * @dev The vWINR per token value is updated based on the claimed amount and the total unconverted gWLP tokens
   * @dev This function is non-reentrant to prevent multiple calls from the same user
   */
  function claimWLP() external nonReentrant {
    // Check that the WLP distribution contract is set
    require(WLPSet, "WLP address zero");
    // Get the total WLP balance of the contract before claiming
    uint256 beforeWLP_ = WLP.balanceOf(address(this));
    // Get the total vWINR balance of the contract before claiming
    uint256 beforevWINR_ = vWINR.balanceOf(address(this));
    // Claim WLP and vWINR rewards from the WLP distribution contract
    WLP.withdrawFunds();
    // Get the total WLP balance of the contract after claiming
    uint256 _afterWLP = WLP.balanceOf(address(this));
    // Get the total vWINR balance of the contract after claiming
    uint256 _aftervWINR = vWINR.balanceOf(address(this));
    // Compute the claimed WLP and vWINR amounts
    uint256 amountWLP_ = _afterWLP - beforeWLP_;
    uint256 amountvWINR_ = _aftervWINR - beforevWINR_;
    // Update the pool's WLP and vWINR profit and per token values
    pool.totalWlpProfit += amountWLP_;
    pool.wlpPerToken += (amountWLP_ * PRECISION) / unconvertedGWLP;
    pool.totalvWINRProfit += amountvWINR_;
    pool.vWINRPerToken += (amountvWINR_ * PRECISION) / unconvertedGWLP;
  }

  /**
   * @notice Function to update the pool's accumulated reward data
   * @dev Calculates the number of blocks since the last reward was distributed and the corresponding rewards earned.
   * Calculates the new accumulated rewards per share based on the rewards earned and total tokens staked.
   * Also updates the last rewarded block and emits an event with the updated data.
   */
  function _updatePoolRewards() private {
    PoolInfo storage pool_ = pool;

    if (pool_.tokensStaked == 0) {
      return;
    }

    uint256 nextBlock_ = _getNextBlock();
    if (pool.lastRewardedBlock >= nextBlock_) return;

    uint256 blocksSinceLastReward_ = nextBlock_ - pool_.lastRewardedBlock;
    uint256 rewards_ = blocksSinceLastReward_ * rewardPerBlock;

    pool_.accumulatedRewardsPerShare += (rewards_ * ACC_REWARD_PRECISION) / pool_.tokensStaked;
    pool_.lastRewardedBlock = nextBlock_;

    allocatedRewards += rewards_;

    emit UpdatePool(nextBlock_, pool_.tokensStaked, pool_.accumulatedRewardsPerShare);
  }

  /**
   * @notice Internal function to calculate the next block number to be used for reward calculation
   * @return nextBlock_ Next block number
   */
  function _getNextBlock() internal view returns (uint256 nextBlock_) {
    nextBlock_ = block.number;
    uint256 lastBlock_ = lastBlock;

    if (nextBlock_ > lastBlock_) nextBlock_ = lastBlock_;
  }

  /**
   *
   * @param _amount The amount of vested WINR tokens to be funded for rewards.
   * @param _fromBlock The distbution starting block
   * @param _toBlock The distbution ending block
   * @param _rewardPerBlock The amount will be accumulated every block
   */
  function fundReward(
    uint256 _amount,
    uint256 _fromBlock,
    uint256 _toBlock,
    uint256 _rewardPerBlock
  ) external onlyGovernance {
    require(_amount != 0, "Fund amount can not be zero");
    require(_toBlock != 0, "To block can not be zero");
    require(_fromBlock != 0, "From block can not be zero");
    require(_toBlock > _fromBlock, "From block can not be lower");
    require(_fromBlock >= block.number, "From block can not be lower than current block");

    // Update the maximum block count for the reward distribution.
    lastBlock = _toBlock;
    rewardPerBlock = _rewardPerBlock;
    if (pool.lastRewardedBlock == 0) {
      pool.lastRewardedBlock = _fromBlock;
    }

    // Transfer the vested WINR tokens from the sender to the contract address.
    vWINR.safeTransferFrom(msg.sender, address(this), _amount);

    emit RewardFunded(_amount, _fromBlock, _toBlock, rewardPerBlock);
  }

  /**
   *
   * @param _amount The amount of WLP tokens to be funded.
   * @notice The amount of WLP tokens that have been funded.
   * @notice Sets the WLP/gWLP ratio based on the newly funded WLP tokens and unconverted gWLP tokens.
   */
  function fundWLP(uint256 _amount) external onlyGovernance {
    require(_amount != 0, "Fund amount can not be zero");

    // Transfer the WLP tokens from the sender to the contract address.
    WLP.safeTransferFrom(msg.sender, address(this), _amount);
    // Get the current balance of WLP tokens in the contract.
    uint256 _balance = WLP.balanceOf(address(this));
    // Calculate the amount of WLP tokens that have not yet been converted to gWLP.
    uint256 _balanceToConvert = _balance - pool.totalWlpProfit;
    // Calculate the new WLP/gWLP ratio based on the remaining WLP tokens and unconverted gWLP tokens.
    ratio = (_balanceToConvert * PRECISION) / unconvertedGWLP;

    emit WLPFunded(_amount, ratio);
  }

  /**
   *
   * @param _ratio The new WLP/gWLP ratio to be set.
   * @notice Updates the WLP/gWLP ratio to the given value.
   */
  function updateRatio(uint256 _ratio) external onlyGovernance {
    require(_ratio != 0, "ratio can't be zero");
    ratio = _ratio;
    emit UpdateRatio(_ratio);
  }

  /**
   *
   * @param _staker The address of the staker to retrieve information for.
   * @notice Returns the current staking information for the given staker.
   */
  function getStakerInfo(address _staker) external view returns (StakerInfo memory _stakerInfo) {
    _stakerInfo = stakerInfo[_staker];
  }

  /**
   *
   * @param _token The address of the ERC20 token to recover.
   * @param _amount The amount of the ERC20 token to recover.
   * @notice Recovers any mistakenly sent ERC20 token to the contract.
   * @notice The recovered token cannot be gWLP.
   */
  function recoverToken(IERC20 _token, uint256 _amount) external onlyGovernance {
    // Ensure that the recovered token is not gWLP.
    require(address(_token) != address(gWLP), "can not recover gWLP");
    // Transfer the recovered ERC20 tokens to the governance address.
    _token.safeTransfer(msg.sender, _amount);

    emit RecoverToken(_token, _amount);
  }

  /**
   *
   * @param _staker The staker whose vWINR reward is being calculated.
   * @notice Calculates the vWINR reward amount for the given staker.
   */
  function _computevWINRAmount(
    StakerInfo memory _staker
  ) internal view returns (uint256 vWINRProfit_) {
    // Calculate the accumulated vWINR rewards per share for the staker.
    vWINRProfit_ = (_staker.amount * pool.accumulatedRewardsPerShare) / ACC_REWARD_PRECISION;

    if (pool.lastRewardedBlock > _getNextBlock()) {
      if (vWINRProfit_ < _staker.rewardDebt) {
        return 0;
      } else {
        return vWINRProfit_ - _staker.rewardDebt;
      }
    }
    // Calculate the number of blocks since the last reward distribution.
    uint256 blocksSinceLastReward_ = _getNextBlock() - pool.lastRewardedBlock;

    // If there are blocks since the last reward distribution, calculate additional rewards.
    if (blocksSinceLastReward_ != 0) {
      // Calculate the additional rewards based on the number of blocks and the reward rate.
      uint256 rewards_ = ((blocksSinceLastReward_ * ACC_REWARD_PRECISION) * rewardPerBlock) /
        pool.tokensStaked;
      // Add the additional rewards to the vWINR profit.
      vWINRProfit_ += (_staker.amount * rewards_) / ACC_REWARD_PRECISION;
    }

    // Subtract the staker's reward debt from the vWINR profit.
    if (vWINRProfit_ < _staker.rewardDebt) {
      return 0;
    } else {
      vWINRProfit_ -= _staker.rewardDebt;
    }
  }

  /**
   * @param _staker StakerInfo struct containing staker's state data
   * @return wlpProfit_ The amount of WLP tokens to be rewarded to the staker
   * @notice Calculates the amount of WLP tokens to be rewarded to the staker based on their staked amount and the pool's WLP per token ratio.
   * Deducts the staker's WLP reward debt to compute the actual reward.
   */
  function _computeWLPReward(
    StakerInfo memory _staker
  ) internal view returns (uint256 wlpProfit_, uint256 vWINRProfit_) {
    // Compute the total WLP reward amount by multiplying the staker's staked amount with the current WLP reward rate
    wlpProfit_ = (_staker.amount * pool.wlpPerToken) / PRECISION;
    // Compute the total vWINR reward amount by multiplying the staker's staked amount with the current vWINR reward rate
    vWINRProfit_ = (_staker.amount * pool.vWINRPerToken) / PRECISION;
    // If the staker's WLP reward debt is greater than the computed WLP reward amount, return zero
    if (wlpProfit_ < _staker.wlpRewardDebt) {
      wlpProfit_ = 0;
    }
    // Otherwise, subtract the staker's WLP reward debt from the computed WLP reward amount to get the actual reward
    else {
      wlpProfit_ -= _staker.wlpRewardDebt;
    }
    // If the staker's vWINR reward debt is greater than the computed vWINR reward amount, return zero
    if (vWINRProfit_ < _staker.vWINRRewardDebt) {
      vWINRProfit_ = 0;
    }
    // Otherwise, subtract the staker's vWINR reward debt from the computed vWINR reward amount to get the actual reward
    else {
      vWINRProfit_ -= _staker.vWINRRewardDebt;
    }
  }
}