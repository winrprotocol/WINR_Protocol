// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/tokens/wlp/IWETH.sol";
import "../interfaces/core/IVault.sol";
import "../interfaces/core/IRouter.sol";
import "./AccessControlBase.sol";

contract Router is IRouter, AccessControlBase {
	using Address for address payable;

	address public immutable weth;
	address public immutable usdw;
	address public immutable vaultAddress;
	mapping(address => bool) public plugins;
	mapping(address => mapping(address => bool)) public approvedPlugins;
	bool public pluginsEnabled = true;

	constructor(
		address _vaultAddress,
		address _usdw,
		address _weth,
		address _vaultRegistry,
		address _timelock
	) AccessControlBase(_vaultRegistry, _timelock) {
		vaultAddress = _vaultAddress;
		usdw = _usdw;
		weth = _weth;
	}

	receive() external payable {
		require(_msgSender() == weth, "Router: invalid sender");
	}

	/*==================== Configuration functions plugins *====================*/

	function setPluginsEnabled(bool _setting) external onlyTimelockGovernance {
		pluginsEnabled = _setting;
	}

	function addPlugin(address _plugin) external override onlyGovernance {
		plugins[_plugin] = true;
	}

	function removePlugin(address _plugin) external onlyGovernance {
		plugins[_plugin] = false;
	}

	function approvePlugin(address _plugin) external onlyManager {
		approvedPlugins[_msgSender()][_plugin] = true;
	}

	function denyPlugin(address _plugin) external onlyManager {
		approvedPlugins[_msgSender()][_plugin] = false;
	}

	/*==================== Operational functions *====================*/

	/**
	 * @notice configure a transfer plugin
	 * @param _token token to be transferred by the plugin
	 * @param _account account that will source the token
	 * @param _receiver the address the tokens are sent to
	 * @param _amount the amount of the token being transferred
	 */
	function pluginTransfer(
		address _token,
		address _account,
		address _receiver,
		uint256 _amount
	) external override {
		_validatePlugin(_account);
		SafeERC20.safeTransferFrom(IERC20(_token), _account, _receiver, _amount);
	}

	function directPoolDeposit(address _token, uint256 _amount) external {
		SafeERC20.safeTransferFrom(IERC20(_token), _sender(), vaultAddress, _amount);
		IVault(vaultAddress).directPoolDeposit(_token);
	}

	/**
	 * @notice public swap function with the vaultAddress
	 * @dev if you pass [dai, eth, btc] in path you are selling dai for eth in the vaultAddress, then you sell the eth for btc
	 * @param _path swap path array
	 * @param _amountIn amount of the asset being purchased going in
	 * @param _minOut minimum amount of the purchased asset the swapper wants to receive
	 * @param _receiver address the swapper wants to receive the purchased asset on
	 */
	function swap(
		address[] memory _path,
		uint256 _amountIn,
		uint256 _minOut,
		address _receiver
	) public override {
		SafeERC20.safeTransferFrom(IERC20(_path[0]), _sender(), vaultAddress, _amountIn);
		uint256 amountOut = _swap(_path, _minOut, _receiver);
		emit Swap(_msgSender(), _path[0], _path[_path.length - 1], _amountIn, amountOut);
	}

	// function swapAndBet(

	// )

	/**
	 * @dev if you pass [dai, eth, btc] in path you are selling dai for eth in the vaultAddress, then you sell the eth for btc
	 * @param _path swap path array
	 * @param _minOut minimum amount of ETH the swapper wants to recieve
	 * @param _receiver address the swapper wants to receive the ETH on
	 */
	function swapETHToTokens(
		address[] memory _path,
		uint256 _minOut,
		address _receiver
	) external payable {
		require(_path[0] == weth, "Router: invalid _path");
		_transferETHToVault();
		uint256 amountOut = _swap(_path, _minOut, _receiver);
		emit Swap(_msgSender(), _path[0], _path[_path.length - 1], msg.value, amountOut);
	}

	/**
	 * @param _path address array with the swap route
	 * @param _amountIn amount of tokens entering the router (of _path[0])
	 * @param _minOut minimum amount of tokenOut (so _path[-1] -> ETH in this case) that the swapper wants to  receive
	 * @param _receiver the address the swapper wants to receive the assets on
	 */
	function swapTokensToETH(
		address[] memory _path,
		uint256 _amountIn,
		uint256 _minOut,
		address payable _receiver
	) external {
		require(_path[_path.length - 1] == weth, "Router: invalid _path");
		SafeERC20.safeTransferFrom(IERC20(_path[0]), _sender(), vaultAddress, _amountIn);
		uint256 amountOut = _swap(_path, _minOut, address(this));
		_transferOutETH(amountOut, _receiver);
		emit Swap(_msgSender(), _path[0], _path[_path.length - 1], _amountIn, amountOut);
	}

	/*==================== Internal functions *====================*/

	function _transferETHToVault() private {
		IWETH(weth).deposit{value: msg.value}();
		SafeERC20.safeTransfer(IERC20(weth), vaultAddress, msg.value);
	}

	function _transferOutETH(uint256 _amountOut, address payable _receiver) private {
		IWETH(weth).withdraw(_amountOut);
		_receiver.sendValue(_amountOut);
	}

	/**
	 * @dev if you pass [dai, eth, btc] in path you are selling dai for eth in the vaultAddress, then you sell the eth for btc
	 * @param _path array with the swap route of assets
	 * @param _minOut minimum amount of the final asset the swapper wants to receive
	 * @param _receiver the address the swapper wants to receive the assets on
	 */
	function _swap(
		address[] memory _path,
		uint256 _minOut,
		address _receiver
	) private returns (uint256) {
		if (_path.length == 2) {
			return _vaultSwap(_path[0], _path[1], _minOut, _receiver);
		}
		if (_path.length == 3) {
			uint256 midOut = _vaultSwap(_path[0], _path[1], 0, address(this));
			SafeERC20.safeTransfer(IERC20(_path[1]), vaultAddress, midOut);
			return _vaultSwap(_path[1], _path[2], _minOut, _receiver);
		}
		revert("Router: invalid _path.length");
	}

	/**
	 * @notice internal vaultAddress swap function
	 * @param _tokenIn address of tokens being sold
	 * @param _tokenOut address of token being bought
	 * @param _minOut minimum amount of _tokenOut the swapper wants to receive
	 * @param _receiver address the swapper wants to receive the purchased assets on
	 * @return amountOut of _tokenOut the swapper wants to receive
	 */
	function _vaultSwap(
		address _tokenIn,
		address _tokenOut,
		uint256 _minOut,
		address _receiver
	) private returns (uint256) {
		uint256 amountOut;
		if (_tokenOut == usdw) {
			// buyUSDW
			amountOut = IVault(vaultAddress).deposit(_tokenIn, _receiver);
		} else if (_tokenIn == usdw) {
			// sellUSDW
			amountOut = IVault(vaultAddress).withdraw(_tokenOut, _receiver);
		} else {
			// swap
			amountOut = IVault(vaultAddress).swap(_tokenIn, _tokenOut, _receiver);
		}
		require(amountOut >= _minOut, "Router: insufficient amountOut");
		return amountOut;
	}

	function _sender() private view returns (address) {
		return _msgSender();
	}

	function _validatePlugin(address _account) private view {
		require(pluginsEnabled, "Router: plugins not enabled");
		require(plugins[_msgSender()], "Router: invalid plugin");
		require(approvedPlugins[_account][_msgSender()], "Router: plugin not approved");
	}
}
