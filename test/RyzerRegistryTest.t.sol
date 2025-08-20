// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {RyzerRegistry} from "../src/RyzerRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RyzerRegistryTest is RyzerRegistry, Test {
    RyzerRegistry public registry;
    RyzerRegistry public implementation;
    ERC1967Proxy public proxy;

    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public projectAddr = address(0x4);
    address public escrowAddr = address(0x5);
    address public orderManagerAddr = address(0x6);
    address public daoAddr = address(0x7);
    address public newImpl = address(0x8);

    // Test data
    bytes32 public constant TEST_NAME = keccak256("Test Company");
    bytes32 public constant TEST_JURISDICTION = keccak256("Delaware");
    bytes32 public constant TEST_PROJECT_NAME = keccak256("Test Project");
    bytes32 public constant TEST_PROJECT_SYMBOL = keccak256("TST");
    bytes32 public constant TEST_METADATA_CID = keccak256("QmTestMetadata");
    bytes32 public constant TEST_LEGAL_CID = keccak256("QmTestLegal");

    function setUp() public {
        // Deploy implementation
        implementation = new RyzerRegistry();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSignature("initialize()");
        proxy = new ERC1967Proxy(address(implementation), initData);

        // Cast proxy to registry interface
        registry = RyzerRegistry(address(proxy));

        // Grant admin role to test admin
        vm.prank(address(this));
        registry.grantRole(registry.ADMIN_ROLE(), admin);
    }

    function test_Initialize() public {
        // Deploy new implementation and proxy for clean test
        RyzerRegistry newImpl = new RyzerRegistry();

        bytes memory initData = abi.encodeWithSignature("initialize()");
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImpl), initData);
        RyzerRegistry newRegistry = RyzerRegistry(address(newProxy));

        // Check initial state
        assertEq(newRegistry.companyCount(), 0);
        assertEq(newRegistry.projectCount(), 0);
        assertTrue(newRegistry.hasRole(newRegistry.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(newRegistry.hasRole(newRegistry.ADMIN_ROLE(), address(this)));
        assertEq(newRegistry.VERSION(), "2.0.0");
    }

    function test_RegisterCompany() public {
        vm.expectEmit(true, true, false, true);
        emit CompanyRegistered(1, user1, TEST_NAME);

        vm.prank(admin);
        uint256 companyId = registry.registerCompany(user1, TEST_NAME, TEST_JURISDICTION, RyzerRegistry.CompanyType.LLC);

        assertEq(companyId, 1);
        assertEq(registry.companyCount(), 1);
        assertEq(registry.companyOf(user1), 1);

        RyzerRegistry.Company memory company = registry.getCompany(1);
        assertEq(company.owner, user1);
        assertEq(uint256(company.companyType), uint256(RyzerRegistry.CompanyType.LLC));
        assertTrue(company.isActive);
        assertEq(company.name, TEST_NAME);
        assertEq(company.jurisdiction, TEST_JURISDICTION);
    }
}
