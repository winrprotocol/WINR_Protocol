// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.6.0 <0.9.0;

interface IBaseFDT {
	/**
        @dev    Returns the total amount of funds a given address is able to withdraw currently.
        @param  owner Address of FDT holder.
        @return A uint256 representing the available funds for a given account.
    */
	function withdrawableFundsOf_WLP(address owner) external view returns (uint256);

	function withdrawableFundsOf_VWINR(address owner) external view returns (uint256);

	/**
        @dev Withdraws all available funds for a FDT holder.
    */
	function withdrawFunds_WLP() external;

	function withdrawFunds_VWINR() external;

	function withdrawFunds() external;

	/**
        @dev   This event emits when new funds are distributed.
        @param by               The address of the sender that distributed funds.
        @param fundsDistributed_WLP The amount of funds received for distribution.
    */
	event FundsDistributed_WLP(address indexed by, uint256 fundsDistributed_WLP);

	event FundsDistributed_VWINR(address indexed by, uint256 fundsDistributed_VWINR);

	/**
        @dev   This event emits when distributed funds are withdrawn by a token holder.
        @param by             The address of the receiver of funds.
        @param fundsWithdrawn_WLP The amount of funds that were withdrawn.
        @param totalWithdrawn_WLP The total amount of funds that were withdrawn.
    */
	event FundsWithdrawn_WLP(
		address indexed by,
		uint256 fundsWithdrawn_WLP,
		uint256 totalWithdrawn_WLP
	);

	event FundsWithdrawn_VWINR(
		address indexed by,
		uint256 fundsWithdrawn_VWINR,
		uint256 totalWithdrawn_VWINR
	);
}
