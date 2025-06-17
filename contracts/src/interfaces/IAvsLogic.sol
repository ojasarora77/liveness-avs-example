// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

/**
 * @title IAvsLogic
 * @notice Interface for AVS logic handling
 */
interface IAvsLogic {
    /**
     * @notice Handle AVS-specific logic
     * @param data Encoded data for processing
     * @return Processed result
     */
    function handleAvsLogic(bytes calldata data) external returns (bytes memory);
}