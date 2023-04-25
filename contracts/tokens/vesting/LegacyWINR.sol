// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "solmate/src/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract LegacyWINR is ERC20, ReentrancyGuard, AccessControlEnumerable {
	event Added(address[] participants, uint256[] amounts);
	event Claimed(address indexed participant, uint256 amount);
	mapping(address => uint256) public allocations;

	constructor(address _admin) ERC20("Legacy WINR", "lWINR") {
		_grantRole(DEFAULT_ADMIN_ROLE, _admin);
	}

	function addParticipants(
		address[] memory _participants,
		uint256[] memory _amounts
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		require(_participants.length == _amounts.length, "Lengths are not equal");
		for (uint256 i = 0; i < _participants.length; i++) {
			_addParticipant(_participants[i], _amounts[i]);
		}

		emit Added(_participants, _amounts);
	}

	function _addParticipant(address _participant, uint256 _amount) internal {
		allocations[_participant] = _amount;
	}

	function claim() external nonReentrant {
		uint256 _amount = allocations[msg.sender];
		require(_amount > 0, "No allocated tokens");
		allocations[msg.sender] = 0;
		_mint(msg.sender, _amount);
		emit Claimed(msg.sender, _amount);
	}
}
