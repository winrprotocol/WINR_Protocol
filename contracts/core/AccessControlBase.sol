// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/utils/Context.sol";
import "../interfaces/core/IVaultAccessControlRegistry.sol";

pragma solidity 0.8.19;

contract AccessControlBase is Context {
	IVaultAccessControlRegistry public immutable registry;
	address public immutable timelockAddressImmutable;

	constructor(address _vaultRegistry, address _timelock) {
		registry = IVaultAccessControlRegistry(_vaultRegistry);
		timelockAddressImmutable = _timelock;
	}

	/*==================== Managed in VaultAccessControlRegistry *====================*/

	modifier onlyGovernance() {
		require(registry.isCallerGovernance(_msgSender()), "Forbidden: Only Governance");
		_;
	}

	modifier onlyManager() {
		require(registry.isCallerManager(_msgSender()), "Forbidden: Only Manager");
		_;
	}

	modifier onlyEmergency() {
		require(registry.isCallerEmergency(_msgSender()), "Forbidden: Only Emergency");
		_;
	}

	modifier protocolNotPaused() {
		require(!registry.isProtocolPaused(), "Forbidden: Protocol Paused");
		_;
	}

	/*==================== Managed in WINRTimelock *====================*/

	modifier onlyTimelockGovernance() {
		address timelockActive_;
		if (!registry.timelockActivated()) {
			// the flip is not switched yet, so this means that the governance address can still pass the onlyTimelockGoverance modifier
			timelockActive_ = registry.governanceAddress();
		} else {
			// the flip is switched, the immutable timelock is now locked in as the only adddress that can pass this modifier (and nothing can undo that)
			timelockActive_ = timelockAddressImmutable;
		}
		require(_msgSender() == timelockActive_, "Forbidden: Only TimelockGovernance");
		_;
	}
}
