// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IUSDW {
	event VaultAdded(address vaultAddress);

	event VaultRemoved(address vaultAddress);

	function addVault(address _vault) external;

	function removeVault(address _vault) external;

	function mint(address _account, uint256 _amount) external;

	function burn(address _account, uint256 _amount) external;
}
