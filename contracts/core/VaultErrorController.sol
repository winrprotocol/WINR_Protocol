// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;
pragma experimental ABIEncoderV2;

import "../interfaces/core/IVault.sol";
import "./AccessControlBase.sol";

contract VaultErrorController is AccessControlBase {
	constructor(
		address _vaultRegistry,
		address _timelock
	) AccessControlBase(_vaultRegistry, _timelock) {}

	function setErrors(IVault _vault, string[] calldata _errors) external onlyGovernance {
		for (uint256 i = 0; i < _errors.length; ++i) {
			_vault.setError(i, _errors[i]);
		}
	}
}
