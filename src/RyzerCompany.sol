// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";

/// @title RyzerCompany
/// @notice Immutable on-chain record for a single RWA company.
/// @dev    Deployed once per company; never upgraded.
contract RyzerCompany is Initializable, ContextUpgradeable, ERC165Upgradeable {
    /*────────────────────────────── ENUMS ───────────────────────────────*/
    enum CompanyType {
        LLC,
        PRIVATELIMITED,
        DAOLLC,
        CORPORATION,
        PUBLICENTITY,
        PARTNERSHIP
    }

    /*────────────────────────────── IMMUTABLE STORAGE ───────────────────*/
    address public OWNER; // 20 B
    CompanyType public TYPE; // 1  B
    bytes31 private ___GAP; // 31 B padding
    bytes32 public NAME; // 32 B
    bytes32 public JURISDICTION; // 32 B
    bytes32 public CID; // 32 B (IPFS hash)

    /*────────────────────────────── EVENTS ───────────────────────────────*/
    event Deployed(address indexed owner, CompanyType indexed companyType, bytes32 name, bytes32 jurisdiction);

    /*────────────────────────────── CONSTRUCTOR / INITIALIZER ───────────*/
    /// @dev initializer called by factory or registry
    function initialize(address owner_, CompanyType type_, bytes32 name_, bytes32 jurisdiction_) external initializer {
        OWNER = owner_;
        TYPE = type_;
        NAME = name_;
        JURISDICTION = jurisdiction_;

        emit Deployed(owner_, type_, name_, jurisdiction_);
    }

    /*────────────────────────────── ERC-165 ──────────────────────────────*/
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /*────────────────────────────── VIEW HELPERS ─────────────────────────*/
    function details()
        external
        view
        returns (address owner, CompanyType companyType, bytes32 name, bytes32 jurisdiction)
    {
        return (OWNER, TYPE, NAME, JURISDICTION);
    }
}
