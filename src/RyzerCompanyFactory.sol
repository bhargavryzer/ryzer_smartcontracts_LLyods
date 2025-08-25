// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {RyzerCompany} from "./RyzerCompany.sol";
import {IRyzerRegistry} from "../src/interfaces/IRyzerRegistry.sol";

contract RyzerCompanyFactory is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IRyzerRegistry public ryzerRegistry;
    /*────────────────────────────── ROLES ───────────────────────────────*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /*────────────────────────────── CONSTANTS ───────────────────────────*/
    uint256 private constant _MAX_NAME = 32;
    uint256 private constant _MAX_JURISDICTION = 32;
    string public constant VERSION = "1.0.0";

    /*────────────────────────────── STORAGE ──────────────────────────────*/
    address public companyImpl; // RyzerCompany implementation
    uint256 public companyCounter; // global company id
    mapping(uint256 => address) public companyAt; // id => proxy address
    mapping(address => uint256[]) public ownerIds; // owner => ids

    /*────────────────────────────── EVENTS ───────────────────────────────*/
    event CompanyDeployed(
        uint256 indexed id,
        address indexed proxy,
        address indexed owner,
        RyzerCompany.CompanyType companyType,
        bytes32 name,
        bytes32 jurisdiction
    );
    event ImplChanged(address indexed oldImpl, address indexed newImpl);

    /*────────────────────────────── ERRORS ───────────────────────────────*/
    error BadAddress();
    error BadInput();
    error BadLength();

    /*────────────────────────────── INITIALIZER ──────────────────────────*/
    function initialize(address _impl) external initializer {
        if (_impl.code.length == 0) revert BadAddress();

        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        companyImpl = _impl;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /*────────────────────────────── ADMIN ────────────────────────────────*/
    function setImpl(address _new) external onlyRole(ADMIN_ROLE) {
        if (_new.code.length == 0) revert BadAddress();
        emit ImplChanged(companyImpl, _new);
        companyImpl = _new;
    }

    /*────────────────────────────── DEPLOY ───────────────────────────────*/
    /// @notice Deploy a new RyzerCompany proxy
    function deployCompany(RyzerCompany.CompanyType companyType, bytes32 name, bytes32 jurisdiction)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 id, address proxy)
    {
        if (name == 0 || jurisdiction == 0) revert BadInput();

        id = ++companyCounter;
        proxy = Clones.clone(companyImpl);

        RyzerCompany(proxy).initialize(_msgSender(), companyType, name, jurisdiction);

        companyAt[id] = proxy;
        ownerIds[_msgSender()].push(id);

        emit CompanyDeployed(id, proxy, _msgSender(), companyType, name, jurisdiction);
    }

    /*────────────────────────────── VIEW HELPERS ─────────────────────────*/
    /// @notice All companies owned by an address
    function companiesOf(address owner) external view returns (uint256[] memory) {
        return ownerIds[owner];
    }

    /*────────────────────────────── PAUSE / UPGRADE ─────────────────────*/
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address impl) internal view override onlyRole(ADMIN_ROLE) {
        if (impl.code.length == 0) revert BadAddress();
    }
}
