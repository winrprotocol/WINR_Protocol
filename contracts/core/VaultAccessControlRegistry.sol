// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/core/IVaultAccessControlRegistry.sol";

contract VaultAccessControlRegistry is IVaultAccessControlRegistry, AccessControl, Pausable {
	/*==================== Constants *====================*/
	bytes32 public constant GOVERANCE_ROLE = keccak256("GOVERANCE_ROLE");
	bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
	bytes32 public constant PROTOCOL_ROLE = keccak256("PROTOCOL_ROLE");
	bytes32 public constant TEAM_ROLE = keccak256("TEAM_ROLE");
	bytes32 public constant SUPPORT_ROLE = keccak256("SUPPORT_ROLE");

	/*==================== State Variabes *====================*/
	address public immutable timelockAddressImmutable;
	address public governanceAddress;
	bool public timelockActivated = false;

	constructor(address _governance, address _timelock) Pausable() {
		governanceAddress = _governance;
		timelockAddressImmutable = _timelock;
		
		_setupRole(GOVERANCE_ROLE, _governance);
		_setupRole(EMERGENCY_ROLE, _governance);
		_setupRole(SUPPORT_ROLE, _governance);
		_setupRole(TEAM_ROLE, _governance);
		_setupRole(PROTOCOL_ROLE, _governance);

		_setRoleAdmin(GOVERANCE_ROLE, GOVERANCE_ROLE);
		_setRoleAdmin(PROTOCOL_ROLE, GOVERANCE_ROLE);
		_setRoleAdmin(SUPPORT_ROLE, GOVERANCE_ROLE);
		_setRoleAdmin(TEAM_ROLE, GOVERANCE_ROLE);
		_setRoleAdmin(EMERGENCY_ROLE, GOVERANCE_ROLE);
	}

	/*==================== One-time functions *====================*/

	/**
	 * To ensure that right after deployment the governance enitity is able to make configuration changes we use a switch mechanism. After the switch is flipped, the governance entity can no longer flip it back. After this point all function protected by the onlyTimelockGovernance modifier can be called after the timelock period has passed.
	 */
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

	/**
	 * 
	 */
	function isCallerGovernance(
		address _account
	) external view whenNotPaused returns (bool isGovernance_) {
		isGovernance_ = hasRole(GOVERANCE_ROLE, _account);
	}

	/**
	 * @dev the emergency role can only pause functions/the protocol - it is meant to be held by trusted entities that are distributed geographically
	 */
	function isCallerEmergency(
		address _account
	) external view whenNotPaused returns (bool isEmergency_) {
		isEmergency_ = hasRole(EMERGENCY_ROLE, _account);
	}

	/**
	 * @dev any address that is assigned the protocol should be a smart contract (no EAO allowed)
	 */
	function isCallerProtocol(
		address _account
	) external view whenNotPaused returns (bool isProtocol_) {
		isProtocol_ = hasRole(PROTOCOL_ROLE, _account);
	}

	/**
	 * @dev the team role is only assigned to entities that are highly trusted, a key holder cannot use hotkeys (only cold wallets)
	 */
	function isCallerTeam(
		address _account
	) external view whenNotPaused returns (bool isTeam_) {
		isTeam_ = hasRole(TEAM_ROLE, _account);
	}

	/**
	 * @dev the support role is the lowest level of access, it can only configure non-valueble configurations like referral tiers 
	 */
	function isCallerSupport(
		address _account
	) external view whenNotPaused returns (bool isSupport_) {
		isSupport_ = hasRole(SUPPORT_ROLE, _account);
	}

	function isProtocolPaused() external view returns (bool isPaused_) {
		isPaused_ = paused();
	}
}
