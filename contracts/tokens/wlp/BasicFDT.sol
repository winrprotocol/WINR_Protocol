// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IBaseFDT.sol";
import "./math/SafeMath.sol";
import "./math/SignedSafeMath.sol";
import "./math/SafeMathUint.sol";
import "./math/SafeMathInt.sol";

/// @title BasicFDT implements base level FDT functionality for accounting for revenues.
abstract contract BasicFDT is IBaseFDT, ERC20 {
	using SafeMath for uint256;
	using SafeMathUint for uint256;
	using SignedSafeMath for int256;
	using SafeMathInt for int256;

	uint256 internal constant pointsMultiplier = 2 ** 128;

	// storage for WLP token rewards
	uint256 internal pointsPerShare_WLP;
	mapping(address => int256) internal pointsCorrection_WLP;
	mapping(address => uint256) internal withdrawnFunds_WLP;

	// storage for VWINR token rewards
	uint256 internal pointsPerShare_VWINR;
	mapping(address => int256) internal pointsCorrection_VWINR;
	mapping(address => uint256) internal withdrawnFunds_VWINR;

	// events WLP token rewards
	event PointsPerShareUpdated_WLP(uint256 pointsPerShare_WLP);
	event PointsCorrectionUpdated_WLP(address indexed account, int256 pointsCorrection_WLP);

	// events VWINR token rewards
	event PointsPerShareUpdated_VWINR(uint256 pointsPerShare_VWINR);
	event PointsCorrectionUpdated_VWINR(address indexed account, int256 pointsCorrection_VWINR);

	constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

	// ADDED FUNCTION BY GHOST

	/**
	 * The WLP on this contract (so that is WLP that has to be disbtributed as rewards, doesn't belong the the WLP that can claim this same WLp). To prevent the dust accumulation of WLP on this contract, we should deduct the balance of WLP on this contract from totalSupply, otherwise the pointsPerShare_WLP will make pointsPerShare_WLP lower as it should be
	 */
	function correctedTotalSupply() public view returns (uint256) {
		return (totalSupply() - balanceOf(address(this)));
	}

	/**
        @dev Distributes funds to token holders.
        @dev It reverts if the total supply of tokens is 0.
        @dev It emits a `FundsDistributed` event if the amount of received funds is greater than 0.
        @dev It emits a `PointsPerShareUpdated` event if the amount of received funds is greater than 0.
             About undistributed funds:
                In each distribution, there is a small amount of funds which do not get distributed,
                   which is `(value  pointsMultiplier) % totalSupply()`.
                With a well-chosen `pointsMultiplier`, the amount funds that are not getting distributed
                   in a distribution can be less than 1 (base unit).
                We can actually keep track of the undistributed funds in a distribution
                   and try to distribute it in the next distribution.
    */
	function _distributeFunds_WLP(uint256 value) internal {
		require(totalSupply() > 0, "FDT:ZERO_SUPPLY");

		if (value == 0) return;

		uint256 correctedTotalSupply_ = correctedTotalSupply();

		pointsPerShare_WLP = pointsPerShare_WLP.add(
			value.mul(pointsMultiplier) / correctedTotalSupply_
		);
		emit FundsDistributed_WLP(msg.sender, value);
		emit PointsPerShareUpdated_WLP(pointsPerShare_WLP);
	}

	function _distributeFunds_VWINR(uint256 value) internal {
		require(totalSupply() > 0, "FDT:ZERO_SUPPLY");

		if (value == 0) return;

		uint256 correctedTotalSupply_ = correctedTotalSupply();

		pointsPerShare_VWINR = pointsPerShare_VWINR.add(
			value.mul(pointsMultiplier) / correctedTotalSupply_
		);
		emit FundsDistributed_VWINR(msg.sender, value);
		emit PointsPerShareUpdated_VWINR(pointsPerShare_VWINR);
	}

	/**
        @dev    Prepares the withdrawal of funds.
        @dev    It emits a `FundsWithdrawn_WLP` event if the amount of withdrawn funds is greater than 0.
        @return withdrawableDividend_WLP The amount of dividend funds that can be withdrawn.
    */
	function _prepareWithdraw_WLP() internal returns (uint256 withdrawableDividend_WLP) {
		withdrawableDividend_WLP = withdrawableFundsOf_WLP(msg.sender);
		uint256 _withdrawnFunds_WLP = withdrawnFunds_WLP[msg.sender].add(
			withdrawableDividend_WLP
		);
		withdrawnFunds_WLP[msg.sender] = _withdrawnFunds_WLP;
		emit FundsWithdrawn_WLP(msg.sender, withdrawableDividend_WLP, _withdrawnFunds_WLP);
	}

	function _prepareWithdraw_VWINR() internal returns (uint256 withdrawableDividend_VWINR) {
		withdrawableDividend_VWINR = withdrawableFundsOf_VWINR(msg.sender);
		uint256 _withdrawnFunds_VWINR = withdrawnFunds_VWINR[msg.sender].add(
			withdrawableDividend_VWINR
		);
		withdrawnFunds_VWINR[msg.sender] = _withdrawnFunds_VWINR;
		emit FundsWithdrawn_VWINR(
			msg.sender,
			withdrawableDividend_VWINR,
			_withdrawnFunds_VWINR
		);
	}

	/**
        @dev    Returns the amount of funds that an account can withdraw.
        @param  _owner The address of a token holder.
        @return The amount funds that `_owner` can withdraw.
    */
	function withdrawableFundsOf_WLP(address _owner) public view returns (uint256) {
		return accumulativeFundsOf_WLP(_owner).sub(withdrawnFunds_WLP[_owner]);
	}

	function withdrawableFundsOf_VWINR(address _owner) public view returns (uint256) {
		return accumulativeFundsOf_VWINR(_owner).sub(withdrawnFunds_VWINR[_owner]);
	}

	/**
        @dev    Returns the amount of funds that an account has withdrawn.
        @param  _owner The address of a token holder.
        @return The amount of funds that `_owner` has withdrawn.
    */
	function withdrawnFundsOf_WLP(address _owner) external view returns (uint256) {
		return withdrawnFunds_WLP[_owner];
	}

	function withdrawnFundsOf_VWINR(address _owner) external view returns (uint256) {
		return withdrawnFunds_VWINR[_owner];
	}

	/**
        @dev    Returns the amount of funds that an account has earned in total.
        @dev    accumulativeFundsOf_WLP(_owner) = withdrawableFundsOf_WLP(_owner) + withdrawnFundsOf_WLP(_owner)
                                         = (pointsPerShare_WLP * balanceOf(_owner) + pointsCorrection_WLP[_owner]) / pointsMultiplier
        @param  _owner The address of a token holder.
        @return The amount of funds that `_owner` has earned in total.
    */
	function accumulativeFundsOf_WLP(address _owner) public view returns (uint256) {
		return
			pointsPerShare_WLP
				.mul(balanceOf(_owner))
				.toInt256Safe()
				.add(pointsCorrection_WLP[_owner])
				.toUint256Safe() / pointsMultiplier;
	}

	function accumulativeFundsOf_VWINR(address _owner) public view returns (uint256) {
		return
			pointsPerShare_VWINR
				.mul(balanceOf(_owner))
				.toInt256Safe()
				.add(pointsCorrection_VWINR[_owner])
				.toUint256Safe() / pointsMultiplier;
	}

	/**
        @dev   Transfers tokens from one account to another. Updates pointsCorrection_WLP to keep funds unchanged.
        @dev   It emits two `PointsCorrectionUpdated` events, one for the sender and one for the receiver.
        @param from  The address to transfer from.
        @param to    The address to transfer to.
        @param value The amount to be transferred.
    */
	function _transfer(address from, address to, uint256 value) internal virtual override {
		super._transfer(from, to, value);

		// storage for WLP token rewards
		int256 _magCorrection_WLP = pointsPerShare_WLP.mul(value).toInt256Safe();
		int256 pointsCorrectionFrom_WLP = pointsCorrection_WLP[from].add(
			_magCorrection_WLP
		);
		pointsCorrection_WLP[from] = pointsCorrectionFrom_WLP;
		int256 pointsCorrectionTo_WLP = pointsCorrection_WLP[to].sub(_magCorrection_WLP);
		pointsCorrection_WLP[to] = pointsCorrectionTo_WLP;

		// storage for VWINR token rewards
		int256 _magCorrection_VWINR = pointsPerShare_VWINR.mul(value).toInt256Safe();
		int256 pointsCorrectionFrom_VWINR = pointsCorrection_VWINR[from].add(
			_magCorrection_VWINR
		);
		pointsCorrection_VWINR[from] = pointsCorrectionFrom_VWINR;
		int256 pointsCorrectionTo_VWINR = pointsCorrection_VWINR[to].sub(
			_magCorrection_VWINR
		);
		pointsCorrection_VWINR[to] = pointsCorrectionTo_VWINR;

		emit PointsCorrectionUpdated_WLP(from, pointsCorrectionFrom_WLP);
		emit PointsCorrectionUpdated_WLP(to, pointsCorrectionTo_WLP);

		emit PointsCorrectionUpdated_VWINR(from, pointsCorrectionFrom_VWINR);
		emit PointsCorrectionUpdated_VWINR(to, pointsCorrectionTo_VWINR);
	}

	/**
        @dev   Mints tokens to an account. Updates pointsCorrection_WLP to keep funds unchanged.
        @param account The account that will receive the created tokens.
        @param value   The amount that will be created.
    */
	function _mint(address account, uint256 value) internal virtual override {
		super._mint(account, value);

		int256 _pointsCorrection_WLP = pointsCorrection_WLP[account].sub(
			(pointsPerShare_WLP.mul(value)).toInt256Safe()
		);

		pointsCorrection_WLP[account] = _pointsCorrection_WLP;

		int256 _pointsCorrection_VWINR = pointsCorrection_VWINR[account].sub(
			(pointsPerShare_VWINR.mul(value)).toInt256Safe()
		);

		pointsCorrection_VWINR[account] = _pointsCorrection_VWINR;

		emit PointsCorrectionUpdated_WLP(account, _pointsCorrection_WLP);
		emit PointsCorrectionUpdated_VWINR(account, _pointsCorrection_VWINR);
	}

	/**
        @dev   Burns an amount of the token of a given account. Updates pointsCorrection_WLP to keep funds unchanged.
        @dev   It emits a `PointsCorrectionUpdated` event.
        @param account The account whose tokens will be burnt.
        @param value   The amount that will be burnt.
    */
	function _burn(address account, uint256 value) internal virtual override {
		super._burn(account, value);

		int256 _pointsCorrection_WLP = pointsCorrection_WLP[account].add(
			(pointsPerShare_WLP.mul(value)).toInt256Safe()
		);

		pointsCorrection_WLP[account] = _pointsCorrection_WLP;

		int256 _pointsCorrection_VWINR = pointsCorrection_VWINR[account].add(
			(pointsPerShare_VWINR.mul(value)).toInt256Safe()
		);

		pointsCorrection_VWINR[account] = _pointsCorrection_VWINR;

		emit PointsCorrectionUpdated_WLP(account, _pointsCorrection_WLP);
		emit PointsCorrectionUpdated_VWINR(account, _pointsCorrection_VWINR);
	}

	/**
        @dev Withdraws all available funds for a token holder.
    */
	function withdrawFunds_WLP() public virtual override {}

	function withdrawFunds_VWINR() public virtual override {}

	function withdrawFunds() public virtual override {}

	/**
        @dev    Updates the current `fundsToken` balance and returns the difference of the new and previous `fundsToken` balance.
        @return A int256 representing the difference of the new and previous `fundsToken` balance.
    */
	function _updateFundsTokenBalance_WLP() internal virtual returns (int256) {}

	function _updateFundsTokenBalance_VWINR() internal virtual returns (int256) {}

	/**
        @dev Registers a payment of funds in tokens. May be called directly after a deposit is made.
        @dev Calls _updateFundsTokenBalance(), whereby the contract computes the delta of the new and previous
             `fundsToken` balance and increments the total received funds (cumulative), by delta, by calling _distributeFunds_WLP().
    */
	function updateFundsReceived() public virtual {
		int256 newFunds_WLP = _updateFundsTokenBalance_WLP();
		int256 newFunds_VWINR = _updateFundsTokenBalance_VWINR();

		if (newFunds_WLP > 0) {
			_distributeFunds_WLP(newFunds_WLP.toUint256Safe());
		}

		if (newFunds_VWINR > 0) {
			_distributeFunds_VWINR(newFunds_VWINR.toUint256Safe());
		}
	}

	function updateFundsReceived_WLP() public virtual {
		int256 newFunds_WLP = _updateFundsTokenBalance_WLP();

		if (newFunds_WLP > 0) {
			_distributeFunds_WLP(newFunds_WLP.toUint256Safe());
		}
	}

	function updateFundsReceived_VWINR() public virtual {
		int256 newFunds_VWINR = _updateFundsTokenBalance_VWINR();

		if (newFunds_VWINR > 0) {
			_distributeFunds_VWINR(newFunds_VWINR.toUint256Safe());
		}
	}

	function returnPointsCorrection_WLP(address _account) public view returns (int256) {
		return pointsCorrection_WLP[_account];
	}

	function returnPointsCorrection_VWINR(address _account) public view returns (int256) {
		return pointsCorrection_VWINR[_account];
	}

	function returnWithdrawnFunds_WLP(address _account) public view returns (uint256) {
		return withdrawnFunds_WLP[_account];
	}

	function returnWithdrawnFunds_VWINR(address _account) public view returns (uint256) {
		return withdrawnFunds_VWINR[_account];
	}
}
