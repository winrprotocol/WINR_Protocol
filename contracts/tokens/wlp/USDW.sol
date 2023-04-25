// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../../interfaces/tokens/wlp/IUSDW.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../core/AccessControlBase.sol";

contract USDW is AccessControlBase, ERC20, IUSDW {
	string constant _name = "WINR USD";
	string constant _symbol = "winrUSD";

	mapping(address => bool) public vaults;

	constructor(
		address _vaultRegistry,
		address _timelock
	) ERC20(_name, _symbol) AccessControlBase(_vaultRegistry, _timelock) {}

	event WithdrawStuckToken(address tokenAddress, address receiver, uint256 amount);

	modifier onlyVault() {
		require(vaults[msg.sender], "USDW: forbidden");
		_;
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

	function addVault(address _vaultAddress) external override onlyTimelockGovernance {
		vaults[_vaultAddress] = true;
		emit VaultAdded(_vaultAddress);
	}

	function removeVault(address _vaultAddress) external override onlyGovernance {
		vaults[_vaultAddress] = false;
		emit VaultRemoved(_vaultAddress);
	}

	function mint(address _account, uint256 _amount) external override onlyVault {
		_mint(_account, _amount);
	}

	function burn(address _account, uint256 _amount) external override onlyVault {
		_burn(_account, _amount);
	}
}
