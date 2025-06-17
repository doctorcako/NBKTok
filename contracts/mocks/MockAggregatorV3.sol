// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract MockAggregatorV3 is AggregatorV3Interface {
    uint8 immutable _decimals;
    int256 private _price;
    uint80 private _roundId;
    uint256 private _timestamp;
    uint80 private _answeredInRound;

    constructor(uint8 decimals_, int256 price_) {
        _decimals = decimals_;
        _price = price_;
        _roundId = 1;
        _timestamp = block.timestamp;
        _answeredInRound = 1;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock MATIC/USD Price Feed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 id) external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (id, _price, _timestamp, _timestamp, _answeredInRound);
    }

    function latestRoundData() external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_roundId, _price, _timestamp, _timestamp, _answeredInRound);
    }

    // Función para actualizar el precio en pruebas
    function updatePrice(int256 newPrice) external {
        _price = newPrice;
        _roundId++;
        _timestamp = block.timestamp;
        _answeredInRound = _roundId;
    }
} 