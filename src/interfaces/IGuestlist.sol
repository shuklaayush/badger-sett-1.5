// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

interface IGuestlist {
    function authorized(
        address guest,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external view returns (bool);

    function setGuests(address[] calldata _guests, bool[] calldata _invited)
        external;
}
