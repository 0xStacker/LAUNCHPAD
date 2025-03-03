//SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

library BasisPointsCalculator {
    uint256 constant BASIS_POINTS = 10_000; // 10000 basis points = 100%

    /**
     * @dev Calculate the percentage of a given value using basis points.
     * @param value The value to calculate the percentage of.
     * @return 10% of the value.
     */
    function calculatePercentage(uint256 value, uint256 bps) public pure returns (uint256) {
        // Calculate the percentage using basis points
        uint256 result = (value * bps) / BASIS_POINTS;

        return result;
    }
}
