// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../core/Access.sol";

contract VestedWINR is ERC20, Access {
	/*==================================================== Events =============================================================*/
	event Mint(address indexed to, uint256 amount, uint256 remainingSupply);
	event Burn(address indexed from, uint256 amount);
	event Whitelisted(address indexed whitelisted);
	event RemoveWhitelisted(address indexed whitelisted);
	/*==================================================== State Variables ====================================================*/
	uint256 public immutable MAX_SUPPLY;
	mapping(address => bool) public wlAddresses;

	// this role is in the Access.sol on deployed version
	bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

	/*======================================================= Constructor =====================================================*/
	constructor(
		string memory _name,
		string memory _symbol,
		address _admin,
		uint256 _maxSupply
	) ERC20(_name, _symbol) Access(_admin) {
		MAX_SUPPLY = _maxSupply;
	}

	/*======================================================= Functions ======================================================*/

	/**
	 *
	 * @param _account the address of the whitelisted wallet
	 * @dev Admin can set the _account as whitelisted
	 * @dev only whitelisted users can transfer tokens
	 */
	function setWlAccount(address _account) external onlyGovernance {
		wlAddresses[_account] = true;
		emit Whitelisted(_account);
	}

	/**
	 *
	 * @param _account the address of the account will be removed from whitelisted
	 */
	function removeWlAccount(address _account) external onlyGovernance {
		wlAddresses[_account] = false;
		emit RemoveWhitelisted(_account);
	}

	/**
	 *
	 * @param to  address of the token receiver
	 * @param amount amount of the token
	 * @dev transfers can only be made by whitelisted accounts
	 */
	function transfer(address to, uint256 amount) public virtual override returns (bool) {
		require(wlAddresses[msg.sender], "Only Wl Accounts");
		return super.transfer(to, amount);
	}

	/**
	 * @param from address of the token sender
	 * @param to  address of the to
	 * @param amount amount of the token
	 * @dev ransfers can only be made by whitelisted accounts
	 */
	function transferFrom(
		address from,
		address to,
		uint256 amount
	) public virtual override returns (bool) {
		require(wlAddresses[msg.sender], "Only Wl Accounts");
		return super.transferFrom(from, to, amount);
	}

	/**
	 *
	 * @param account  mint to address
	 * @param amount  mint amount
	 * @dev mint function will not mint if it causes the total supply to exceed MAX_SUPPLY
	 * @dev returns minted amount and remaining from MAX_SUPPLY
	 */
	function mint(
		address account,
		uint256 amount
	) external onlyRole(MINTER_ROLE) returns (uint256, uint256) {
		bool canMint = (totalSupply() + amount <= MAX_SUPPLY);
		uint256 minted = canMint ? amount : 0;
		if (canMint) {
			_mint(account, amount);
		}

		uint256 remainingSupply = MAX_SUPPLY - totalSupply();
		emit Mint(account, minted, remainingSupply);

		return (minted, remainingSupply);
	}

	/**
	 *
	 * @param amount amount to burn
	 * @dev this function burns the given amount of tokens from the caller
	 */
	function burn(uint256 amount) external {
		_burn(msg.sender, amount);

		emit Burn(msg.sender, amount);
	}
}
