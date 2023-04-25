// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWINR, IERC20} from "../../interfaces/tokens/IWINR.sol";
import "../../core/Access.sol";
import "./DateTime.sol";

contract VestingTransfer is Access {
	using SafeERC20 for IERC20;

	enum Category {
		WINR_LABS,
		MARKETING,
		ADVISORS,
		PREV_HOLDERS,
		CORE_CONTRIBUTORS
	}
	event Added(address indexed investor, address indexed caller, uint256 allocation);
	event Removed(
		address indexed investor,
		address indexed caller,
		uint256 allocation,
		Category category
	);
	event Withdrawn(address indexed investor, uint256 WINRValue, uint256 vestedWINRValue);
	event RecoverToken(address indexed token, uint256 amount);

	uint256 public totalAllocatedAmount;
	uint256 public initialTimestamp;
	IWINR public WINR;
	IWINR public vWINR;
	address[] public investors;
	/// @dev Boolean variable that indicates whether the contract was initialized.
	bool public isInitialized = false;

	mapping(Category => uint256) public totalAllotments;
	mapping(Category => CategoryDetail) public categoryDetails;
	mapping(address => Investor) public investorsInfo;

	struct Investor {
		bool exists;
		address winrWallet;
		address vWinrWallet;
		uint256 withdrawnTokens;
		uint256 tokensAllotment;
		Category category;
	}

	struct CategoryDetail {
		uint256 cliffDays;
		uint256 recurrence;
	}

	/// @dev Checks that the contract is initialized.
	modifier initialized() {
		require(isInitialized, "not initialized");
		_;
	}

	/// @dev Checks that the contract has not yet been initialized.
	modifier notInitialized() {
		require(!isInitialized, "initialized");
		_;
	}

	modifier onlyInvestor() {
		require(investorsInfo[msg.sender].exists, "Only investors allowed");
		_;
	}

	constructor(IWINR _Winr, IWINR _vWinr, address _admin) Access(_admin) {
		WINR = _Winr;
		vWINR = _vWinr;

		categoryDetails[Category.WINR_LABS] = CategoryDetail(180, 1080);
		categoryDetails[Category.MARKETING] = CategoryDetail(0, 720);
		categoryDetails[Category.ADVISORS] = CategoryDetail(0, 1080);
		categoryDetails[Category.PREV_HOLDERS] = CategoryDetail(0, 720);
		categoryDetails[Category.CORE_CONTRIBUTORS] = CategoryDetail(0, 720);
	}

	/// @dev The starting time of TGE
	/// @param timestamp The initial timestamp, this timestap should be used for vesting
	function setInitialTimestamp(
		uint256 timestamp
	) external onlyRole(DEFAULT_ADMIN_ROLE) notInitialized {
		require(timestamp > block.timestamp, "Initial timestamp must be in the future");
		isInitialized = true;
		initialTimestamp = timestamp;
	}

	function getInitialTimestamp() external view returns (uint256 timestamp) {
		return initialTimestamp;
	}

	function investorsLength() external view returns (uint256 _investorsLenght) {
		return investors.length;
	}

	function addInvestorBatch(
		address[] calldata _winrWallets,
		address[] calldata _vWinrWallets,
		uint256[] calldata _tokensAllotments,
		Category[] calldata _categories
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		require(
			_tokensAllotments.length == _categories.length,
			"addInvestorBatch: array lengths should be the same"
		);
		require(
			_categories.length == _winrWallets.length,
			"addInvestorBatch: array lengths should be the same"
		);
		require(
			_winrWallets.length == _vWinrWallets.length,
			"addInvestorBatch: array lengths should be the same"
		);

		for (uint256 i = 0; i < _tokensAllotments.length; i++) {
			_addInvestor(
				_winrWallets[i],
				_vWinrWallets[i],
				_tokensAllotments[i],
				_categories[i]
			);
		}
	}

	function addInvestor(
		address _winrWallet,
		address _vWinrWallet,
		uint256 _tokensAllotment,
		Category _category
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		_addInvestor(_winrWallet, _vWinrWallet, _tokensAllotment, _category);
	}

	function removeInvestor(address _investor) external onlyRole(DEFAULT_ADMIN_ROLE) {
		Investor memory _info = investorsInfo[_investor];
		uint256 _allocation = _info.tokensAllotment - _info.withdrawnTokens;
		totalAllocatedAmount -= _allocation;
		totalAllotments[_info.category] -= _allocation;
		delete investorsInfo[_investor];
		emit Removed(_investor, msg.sender, _allocation, _info.category);
	}

	/// @param _winrWallet The addresses of new investors.
	/// @param _vWinrWallet The addresses of new investors.
	/// @param _tokensAllotment The amounts of the tokens that belong to each investor.
	/// @param _category The category of the investor
	/// @dev winrWallet or vWinrWallet can be zero.
	function _addInvestor(
		address _winrWallet,
		address _vWinrWallet,
		uint256 _tokensAllotment,
		Category _category
	) internal {
		require(
			_winrWallet != address(0) || _vWinrWallet != address(0),
			"addInvestor: invalid address"
		);
		address _investor = _winrWallet == address(0) ? _vWinrWallet : _winrWallet;
		require(!investorsInfo[_investor].exists, "addInvestor: investor exists");
		require(
			_tokensAllotment > 0,
			"addInvestor: the investor allocation must be more than 0"
		);

		totalAllotments[_category] += _tokensAllotment;
		Investor storage investor = investorsInfo[_investor];

		investor.tokensAllotment = _tokensAllotment;
		investor.exists = true;
		investor.winrWallet = _winrWallet;
		investor.vWinrWallet = _vWinrWallet;
		investor.category = _category;

		investors.push(_investor);

		totalAllocatedAmount += _tokensAllotment;
		emit Added(_investor, msg.sender, _tokensAllotment);
	}

	///@dev If winrWallet = zero, sends withdrawable amount to vWinrWallet as Vested Winr
	///@dev If vWinrWallet = zero, sends withdrawable amount to winrWallet as Winr
	///@dev If both of them are not zero divides withdrawable amount by 2 and sends to both of them
	function withdrawTokens() external onlyInvestor initialized {
		Investor storage investor = investorsInfo[msg.sender];

		uint256 tokensAvailable = withdrawableTokens(msg.sender);

		require(tokensAvailable > 0, "withdrawTokens: no tokens available for withdrawal");

		investor.withdrawnTokens = investor.withdrawnTokens + tokensAvailable;

		if (investor.winrWallet != address(0) && investor.vWinrWallet != address(0)) {
			IERC20(WINR).safeTransfer(investor.winrWallet, tokensAvailable / 2);
			IERC20(vWINR).safeTransfer(investor.vWinrWallet, tokensAvailable / 2);

			emit Withdrawn(msg.sender, tokensAvailable / 2, tokensAvailable / 2);
		} else {
			if (investor.winrWallet != address(0)) {
				IERC20(WINR).safeTransfer(investor.winrWallet, tokensAvailable);
				emit Withdrawn(msg.sender, tokensAvailable, 0);
			} else {
				IERC20(vWINR).safeTransfer(investor.vWinrWallet, tokensAvailable);
				emit Withdrawn(msg.sender, 0, tokensAvailable);
			}
		}
	}

	/// @dev withdrawable tokens for an address
	/// @param _investor whitelisted investor address
	function withdrawableTokens(
		address _investor
	) public view returns (uint256 tokensAvailable) {
		Investor storage investor = investorsInfo[_investor];

		uint256 totalUnlockedTokens = _calculateUnlockedTokens(_investor);
		uint256 tokensWithdrawable = totalUnlockedTokens - investor.withdrawnTokens;
		return tokensWithdrawable;
	}

	/// @dev calculate the amount of unlocked tokens of an investor
	function _calculateUnlockedTokens(
		address _investor
	) internal view returns (uint256 availableTokens) {
		Investor storage investor = investorsInfo[_investor];
		require(
			investor.withdrawnTokens < investor.tokensAllotment,
			"withdrawTokens: investor has already withdrawn all available balance"
		);

		CategoryDetail memory categoryDetail = categoryDetails[investor.category];
		uint256 cliffTimestamp = initialTimestamp + categoryDetail.cliffDays * 1 days;
		uint256 vestingTimestamp = cliffTimestamp + categoryDetail.recurrence * 1 days;

		uint256 currentTimeStamp = block.timestamp;
		if (initialTimestamp == 0) return 0;

		if (currentTimeStamp > initialTimestamp) {
			if (currentTimeStamp <= cliffTimestamp) {
				return 0;
			} else if (
				currentTimeStamp > cliffTimestamp &&
				currentTimeStamp < vestingTimestamp
			) {
				uint256 vestingDistroAmount = investor.tokensAllotment; // - initialDistroAmount;

				uint256 occurence = DateTime.diffDays(
					cliffTimestamp,
					currentTimeStamp
				);

				uint256 vestingUnlockedAmount = (occurence * vestingDistroAmount) /
					categoryDetail.recurrence;

				return vestingUnlockedAmount; // total unlocked amount
			} else {
				return investor.tokensAllotment;
			}
		} else {
			return 0;
		}
	}

	function recoverToken(
		address _token,
		uint256 amount
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		IERC20(_token).safeTransfer(msg.sender, amount);
		emit RecoverToken(_token, amount);
	}
}
