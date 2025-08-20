// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IRyzerOrderManager
/// @notice Interface for RyzerOrderManager contract
interface IRyzerOrderManager {
    /*─────────────────────── STRUCTS ───────────────────────*/
    struct Order {
        address buyer;
        address project;
        address paymentToken;
        uint256 amount;
        uint256 deadline;
        bool executed;
        bool cancelled;
    }

    /*─────────────────────── EVENTS ────────────────────────*/
    event OrderPlaced(
        uint256 indexed orderId,
        address indexed buyer,
        address indexed project,
        address paymentToken,
        uint256 amount,
        uint256 deadline
    );

    event OrderExecuted(uint256 indexed orderId, address indexed buyer, address indexed project, uint256 amount);

    event OrderCancelled(uint256 indexed orderId, address indexed buyer);

    event EscrowUpdated(address indexed newEscrow);
    event RegistryUpdated(address indexed newRegistry);

    /*─────────────────────── FUNCTIONS ────────────────────────*/

    /// @notice Place a new token purchase order
    /// @param project The project address
    /// @param paymentToken The token used for payment
    /// @param amount Amount of payment tokens
    /// @param deadline Order expiry timestamp
    /// @return orderId The ID of the created order
    function placeOrder(address project, address paymentToken, uint256 amount, uint256 deadline)
        external
        returns (uint256 orderId);

    function initialize(address _escrow, address _project, address _owner) external;

    /// @notice Execute an existing order
    /// @param orderId The ID of the order to execute
    function executeOrder(uint256 orderId) external;

    /// @notice Cancel an existing order
    /// @param orderId The ID of the order to cancel
    function cancelOrder(uint256 orderId) external;

    /// @notice Update the escrow contract address
    /// @param newEscrow The new escrow contract address
    function updateEscrow(address newEscrow) external;

    /// @notice Update the registry contract address
    /// @param newRegistry The new registry contract address
    function updateRegistry(address newRegistry) external;

    /// @notice Returns order details
    /// @param orderId The ID of the order
    /// @return order Struct with order details
    function getOrder(uint256 orderId) external view returns (Order memory order);

    /// @notice Check if an order is still valid
    /// @param orderId The ID of the order
    /// @return true if valid, false otherwise
    function isOrderValid(uint256 orderId) external view returns (bool);

    /// @notice Get total number of orders
    /// @return count Number of orders
    function totalOrders() external view returns (uint256 count);

    /// @notice UUPS upgrade authorization (required by proxy)
    /// @param newImplementation Address of new implementation
    function upgradeTo(address newImplementation) external;

    /// @notice ERC-165 interface support check
    /// @param interfaceId ID of the interface
    /// @return true if supported
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
