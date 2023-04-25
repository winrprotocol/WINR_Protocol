// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract WhitelistPool is ERC20, AccessControlEnumerable {
	/*====================================== Events ============================================= */
	event Deposit(address indexed account, uint256 amount);
	event Withdraw(address indexed multisig, uint256 amount);
	event DueDate(uint256 newDueDate);
	/*====================================== State Variables ============================================= */
	IERC20 public immutable USDC;
	uint256 public dueDate;

	/*====================================== Constructor ============================================= */
	constructor(IERC20 _USDC) ERC20("Genesis WLP", "gWLP") {
		require(address(_USDC) != address(0), "WP: Address zero");
		USDC = _USDC;
		dueDate = block.timestamp + 4 days; // default
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
	}

	/*====================================== Functions ============================================= */
	/**
	 *
	 * @param amount deposit amount of USDC
	 * @notice it takes USDC and mints gWLP equivalent amount of USDC
	 */
	function deposit(uint256 amount) external {
		require(block.timestamp < dueDate, "WP: Due Date has passed");
		require(USDC.transferFrom(msg.sender, address(this), amount), "WP: Deposit failed");

		_mint(msg.sender, amount * 10 ** 12);
		emit Deposit(msg.sender, amount);
	}

	/**
	 *
	 * @param amount withdraw amount of the USDC
	 * @notice only DEFAULT_ADMIN_ROLE can withdraw
	 * @notice withdraw is not allowed before than due date
	 */
	function withdraw(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
		require(block.timestamp >= dueDate, "WP: Due Date has not come");
		require(USDC.transfer(msg.sender, amount), "WP: Withdraw failed");
		emit Withdraw(msg.sender, amount);
	}

	/**
	 *
	 * @param newDueDate new due date, it must be in timestamp
	 * @notice new due date can not be before than the current one
	 */
	function updateDueDate(uint256 newDueDate) external onlyRole(DEFAULT_ADMIN_ROLE) {
		require(newDueDate > dueDate, "WP: Due Date must be greater the old one");
		dueDate = newDueDate;
		emit DueDate(newDueDate);
	}
}
