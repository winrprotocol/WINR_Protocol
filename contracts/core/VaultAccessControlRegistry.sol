// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/core/IVaultAccessControlRegistry.sol";

contract VaultAccessControlRegistry is IVaultAccessControlRegistry, AccessControl, Pausable {
	/*==================== Constants *====================*/
	bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
	bytes32 public constant GOVERANCE_ROLE = keccak256("GOVERANCE_ROLE");
	bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

	/*==================== State Variabes *====================*/
	address public immutable timelockAddressImmutable;
	address public governanceAddress;
	bool public timelockActivated = false;

	constructor(address _governance, address _timelock) Pausable() {
		governanceAddress = _governance;
		timelockAddressImmutable = _timelock;
		_setupRole(GOVERANCE_ROLE, _governance);
		_setupRole(MANAGER_ROLE, _governance);
		_setupRole(EMERGENCY_ROLE, _governance);
		_setRoleAdmin(GOVERANCE_ROLE, GOVERANCE_ROLE);
		_setRoleAdmin(MANAGER_ROLE, GOVERANCE_ROLE);
		_setRoleAdmin(EMERGENCY_ROLE, GOVERANCE_ROLE);
	}

	/*==================== One-time functions *====================*/

	function flipTimelockDeadmanSwitch() external onlyRole(GOVERANCE_ROLE) {
		require(
			!timelockActivated,
			"VaultAccessControlRegistry: Deadmanswitch already flipped"
		);
		timelockActivated = true;
		emit DeadmanSwitchFlipped();
	}

	/*==================== Configuration functions (onlyGovernance, onlyEmergency) *====================*/

	function pauseProtocol() external onlyRole(EMERGENCY_ROLE) {
		_pause();
	}

	function unpauseProtocol() external onlyRole(EMERGENCY_ROLE) {
		_unpause();
	}

	/**
	 * @notice  function that sets a new governanceAddress, revokes the old governance address
	 * @dev even though parent AccessControl provides revoke and grant functions as well, the intent is for only want one governanceAddress to be set at the same time!
	 * @param _governanceAddress the new to be configured governance address
	 */
	function changeGovernanceAddress(address _governanceAddress) external {
		require(
			_governanceAddress != address(0x0),
			"VaultAccessControlRegistry: Governance cannot be null address"
		);
		require(
			msg.sender == governanceAddress,
			"VaultAccessControlRegistry: Only official goverance address can change goverance address"
		);
		// revoke the contract/address currenly marked as goverance
		_revokeRole(GOVERANCE_ROLE, governanceAddress);
		// grant the governanceRole to the new _governanceAddress
		_grantRole(GOVERANCE_ROLE, _governanceAddress);
		governanceAddress = _governanceAddress;
		// note: at deployment the goverance address was also assigned the emergency and manager roles - with this function these roles are not revoked!
		emit GovernanceChange(_governanceAddress);
	}

	/*==================== View functions *====================*/

	function isCallerGovernance(
		address _account
	) external view whenNotPaused returns (bool isGovernance_) {
		isGovernance_ = hasRole(GOVERANCE_ROLE, _account);
	}

	function isCallerManager(
		address _account
	) external view whenNotPaused returns (bool isManager_) {
		isManager_ = hasRole(MANAGER_ROLE, _account);
	}

	function isCallerEmergency(
		address _account
	) external view whenNotPaused returns (bool isEmergency_) {
		isEmergency_ = hasRole(EMERGENCY_ROLE, _account);
	}

	function isProtocolPaused() external view returns (bool isPaused_) {
		isPaused_ = paused();
	}
}
