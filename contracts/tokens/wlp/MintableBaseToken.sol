// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./BasicFDT.sol";
import "../../interfaces/tokens/wlp/IMintable.sol";
import "../../core/AccessControlBase.sol";
import "solmate/src/utils/ReentrancyGuard.sol";

contract MintableBaseToken is BasicFDT, AccessControlBase, ReentrancyGuard, IMintable {
	using SafeMath for uint256;
	using SafeMathUint for uint256;
	using SignedSafeMath for int256;
	using SafeMathInt for int256;

	mapping(address => bool) public override isMinter;
	bool public inPrivateTransferMode;
	mapping(address => bool) public isHandler;

	IERC20 public immutable rewardToken_WLP; // 1 The `rewardToken_WLP` (dividends).
	IERC20 public immutable rewardToken_VWINR; // 2 The `rewardToken_VWINR` (dividends).

	uint256 public rewardTokenBalance_WLP; // The amount of `rewardToken_WLP` (Liquidity Asset 1) currently present and accounted for in this contract.
	uint256 public rewardTokenBalance_VWINR; // The amount of `rewardToken_VWINR` (Liquidity Asset2 ) currently present and accounted for in this contract.

	event SetInfo(string name, string symbol);

	event SetPrivateTransferMode(bool inPrivateTransferMode);

	event SetHandler(address handlerAddress, bool isActive);

	event WithdrawStuckToken(address tokenAddress, address receiver, uint256 amount);

	constructor(
		string memory _name,
		string memory _symbol,
		address _vwinrAddress,
		address _vaultRegistry,
		address _timelock
	) BasicFDT(_name, _symbol) AccessControlBase(_vaultRegistry, _timelock) {
		rewardToken_WLP = IERC20(address(this));
		rewardToken_VWINR = IERC20(_vwinrAddress);
	}

	modifier onlyMinter() {
		require(isMinter[_msgSender()], "MintableBaseToken: forbidden");
		_;
	}

	/**
        @dev Withdraws all available funds for a token holder.
    */
	function withdrawFunds_WLP() public virtual override nonReentrant {
		uint256 withdrawableFunds_WLP = _prepareWithdraw_WLP();

		if (withdrawableFunds_WLP > uint256(0)) {
			rewardToken_WLP.transfer(_msgSender(), withdrawableFunds_WLP);

			_updateFundsTokenBalance_WLP();
		}
	}

	function withdrawFunds_VWINR() public virtual override nonReentrant {
		uint256 withdrawableFunds_VWINR = _prepareWithdraw_VWINR();

		if (withdrawableFunds_VWINR > uint256(0)) {
			rewardToken_VWINR.transfer(_msgSender(), withdrawableFunds_VWINR);

			_updateFundsTokenBalance_VWINR();
		}
	}

	function withdrawFunds() public virtual override nonReentrant {
		withdrawFunds_WLP();
		withdrawFunds_VWINR();
	}

	/**
        @dev    Updates the current `rewardToken_WLP` balance and returns the difference of the new and previous `rewardToken_WLP` balance.
        @return A int256 representing the difference of the new and previous `rewardToken_WLP` balance.
    */
	function _updateFundsTokenBalance_WLP() internal virtual override returns (int256) {
		uint256 _prevFundsTokenBalance_WLP = rewardTokenBalance_WLP;

		rewardTokenBalance_WLP = rewardToken_WLP.balanceOf(address(this));

		return int256(rewardTokenBalance_WLP).sub(int256(_prevFundsTokenBalance_WLP));
	}

	function _updateFundsTokenBalance_VWINR() internal virtual override returns (int256) {
		uint256 _prevFundsTokenBalance_VWINR = rewardTokenBalance_VWINR;

		rewardTokenBalance_VWINR = rewardToken_VWINR.balanceOf(address(this));

		return int256(rewardTokenBalance_VWINR).sub(int256(_prevFundsTokenBalance_VWINR));
	}

	function transfer(address _recipient, uint256 _amount) public override returns (bool) {
		if (inPrivateTransferMode) {
			require(isHandler[_msgSender()], "BaseToken: _msgSender() not whitelisted");
		}
		super._transfer(_msgSender(), _recipient, _amount);
		return true;
	}

	function transferFrom(
		address _from,
		address _recipient,
		uint256 _amount
	) public override returns (bool) {
		if (inPrivateTransferMode) {
			require(isHandler[_msgSender()], "BaseToken: _msgSender() not whitelisted");
		}
		if (isHandler[_msgSender()]) {
			super._transfer(_from, _recipient, _amount);
			return true;
		}
		address spender = _msgSender();
		super._spendAllowance(_from, spender, _amount);
		super._transfer(_from, _recipient, _amount);
		return true;
	}

	function setInPrivateTransferMode(
		bool _inPrivateTransferMode
	) external onlyTimelockGovernance {
		inPrivateTransferMode = _inPrivateTransferMode;
		emit SetPrivateTransferMode(_inPrivateTransferMode);
	}

	function setHandler(address _handler, bool _isActive) external onlyTimelockGovernance {
		isHandler[_handler] = _isActive;
		emit SetHandler(_handler, _isActive);
	}

	function setInfo(string memory _name, string memory _symbol) external onlyGovernance {
		_name = _name;
		_symbol = _symbol;
		emit SetInfo(_name, _symbol);
	}

	/**
	 * @notice function to service users who accidentally send their tokens to this contract
	 * @dev since this function could technically steal users assets we added a timelock modifier
	 * @param _token address of the token to be recoved
	 * @param _account address the recovered tokens will be sent to
	 * @param _amount amount of token to be recoverd
	 */
	function withdrawToken(
		address _token,
		address _account,
		uint256 _amount
	) external onlyGovernance {
		IERC20(_token).transfer(_account, _amount);
		emit WithdrawStuckToken(_token, _account, _amount);
	}

	function setMinter(
		address _minter,
		bool _isActive
	) external override onlyTimelockGovernance {
		isMinter[_minter] = _isActive;
		emit MinterSet(_minter, _isActive);
	}

	function mint(address _account, uint256 _amount) external override nonReentrant onlyMinter {
		super._mint(_account, _amount);
	}

	function burn(address _account, uint256 _amount) external override nonReentrant onlyMinter {
		super._burn(_account, _amount);
	}
}
