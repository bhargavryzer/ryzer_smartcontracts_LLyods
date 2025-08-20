// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IRyzerCompany
/// @notice Interface for RyzerCompany immutable company record
interface IRyzerCompany {
    /*────────────────────────────── ENUMS ───────────────────────────────*/
    enum CompanyType {
        LLC,
        PRIVATELIMITED,
        DAOLLC,
        CORPORATION,
        PUBLICENTITY,
        PARTNERSHIP
    }

    /*────────────────────────────── EVENTS ──────────────────────────────*/
    event Deployed(
        address indexed owner, CompanyType indexed companyType, bytes32 name, bytes32 jurisdiction, bytes32 cid
    );

    /*────────────────────────────── FUNCTIONS ───────────────────────────*/

    /// @notice Initializes immutable company details
    /// @dev Callable once by factory/registry
    function initialize(address owner_, CompanyType type_, bytes32 name_, bytes32 jurisdiction_, bytes32 cid_)
        external;

    /// @notice ERC-165 interface support check
    /// @param interfaceId ID of the interface
    /// @return true if supported
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    /// @notice Returns full company details
    /// @return owner Company owner
    /// @return companyType Type of company
    /// @return name Company name
    /// @return jurisdiction Jurisdiction string
    /// @return cid IPFS CID of metadata
    function details()
        external
        view
        returns (address owner, CompanyType companyType, bytes32 name, bytes32 jurisdiction, bytes32 cid);
}
