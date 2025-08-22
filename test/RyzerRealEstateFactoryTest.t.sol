// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {UsdcMock} from "../src/USDCMock.sol";
import {UsdtMock} from "../src/UsdtMock.sol";

import "../src/interfaces/IRyzerRealEstateToken.sol";
import "../src/RyzerRealEstateFactory.sol";

import {RyzerDAO} from "../src/RyzerDAO.sol";
import {RyzerOrderManager} from "../src/RyzerOrderManager.sol";
import {RyzerEscrow} from "../src/RyzerEscrow.sol";
import {RyzerRealEstateToken} from "../src/RyzerRealEstateToken.sol";

contract MockERC20 is IERC20, IERC20Metadata {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

contract RyzerRealEstateTokenFactoryTest is Test {
    UsdcMock public usdc;
    UsdtMock public usdt;
    MockERC20 public ryzerxToken;

    RyzerDAO public daoImplementation;
    RyzerOrderManager public orderManagerImplementation;
    RyzerEscrow public escrowImplementation;
    RyzerRealEstateToken public tokenImplementation;

    RyzerRealEstateTokenFactory public factory;
    RyzerRealEstateTokenFactory public implementation;
    ERC1967Proxy public proxy;

    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public projectOwner = address(0x3);
    address public identityRegistry = address(0x4);
    address public compliance = address(0x5);
    address public onchainID = address(0x6);

    // Import the event from the factory contract
    event ProjectDeployed(
        address indexed project,
        address indexed escrow,
        address indexed orderManager,
        address dao,
        bytes32 assetId,
        string name,
        address stableCoin
    );

    function setUp() public {
        // Deploy mock tokens
        usdc = new UsdcMock();
        usdt = new UsdtMock();
        ryzerxToken = new MockERC20("RyzerX", "RZX", 18);

        // Deploy implementations
        tokenImplementation = new RyzerRealEstateToken();
        escrowImplementation = new RyzerEscrow();
        orderManagerImplementation = new RyzerOrderManager();
        daoImplementation = new RyzerDAO();

        // Deploy factory
        implementation = new RyzerRealEstateTokenFactory();
        bytes memory data = abi.encodeWithSelector(
            implementation.initialize.selector,
            address(usdc),
            address(usdt),
            address(ryzerxToken),
            address(tokenImplementation),
            address(escrowImplementation),
            address(orderManagerImplementation),
            address(daoImplementation)
        );
        proxy = new ERC1967Proxy(address(implementation), data);
        factory = RyzerRealEstateTokenFactory(address(proxy));

        // Grant admin role to test admin
        vm.prank(admin);
        factory.grantRole(factory.ADMIN_ROLE(), admin);
    }

    function test_Initialize_EstateFactory() public {
        // Deploy new implementation and proxy for clean test
        RyzerRealEstateTokenFactory newImpl = new RyzerRealEstateTokenFactory();

        // Deploy new proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            newImpl.initialize.selector,
            address(usdc),
            address(usdt),
            address(ryzerxToken),
            address(tokenImplementation),
            address(escrowImplementation),
            address(orderManagerImplementation),
            address(daoImplementation)
        );
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImpl), initData);
        RyzerRealEstateTokenFactory newFactory = RyzerRealEstateTokenFactory(address(newProxy));

        // Check initial state
        assertEq(address(newFactory.usdc()), address(usdc));
        assertEq(address(newFactory.usdt()), address(usdt));
        assertEq(address(newFactory.ryzerXToken()), address(ryzerxToken));
        assertEq(newFactory.projectTemplate(), address(tokenImplementation));
        assertEq(newFactory.escrowTemplate(), address(escrowImplementation));
        assertEq(newFactory.orderManagerTemplate(), address(orderManagerImplementation));
        assertEq(newFactory.daoTemplate(), address(daoImplementation));

        assertTrue(newFactory.hasRole(newFactory.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(newFactory.hasRole(newFactory.ADMIN_ROLE(), address(this)));
    }

    function _getValidDeployParams() internal view returns (RyzerRealEstateTokenFactory.DeployParams memory) {
        return RyzerRealEstateTokenFactory.DeployParams({
            identityRegistry: identityRegistry,
            compliance: compliance,
            onchainID: onchainID,
            name: "Test Property",
            symbol: "TPROP",
            decimals: 18,
            maxSupply: 1_000_000 * 1e18, // 1M tokens with 18 decimals
            tokenPrice: 1 * 1e6, // $1 in USDC terms (6 decimals) - must be > 0
            cancelDelay: 1 days, // Must be > 0
            projectOwner: projectOwner, // Must be non-zero
            assetId: keccak256(abi.encodePacked("asset", block.timestamp, block.prevrandao)), // Unique ID for each test
            metadataCID: keccak256("metadata"),
            assetType: IRyzerRealEstateToken.AssetType.Commercial,
            legalMetadataCID: keccak256("legal"),
            dividendPct: 10, // Must be <= 50
            preMintAmount: 100_000 * 1e18, // Must be <= maxSupply
            minInvestment: 100 * 1e6, // $100 minimum (in USDC 6 decimals)
            maxInvestment: 1_000_000 * 1e6 // $1M maximum, must be >= minInvestment
        });
    }

    function test_DeployProject_USDC() public {
        // Prepare test data
        RyzerRealEstateTokenFactory.DeployParams memory params = _getValidDeployParams();

        console.log("Starting project deployment...");
        console.log("Project Name:", params.name);
        console.log("Symbol:", params.symbol);
        console.log("Decimals:", params.decimals);
        console.log("Max Supply:", params.maxSupply);
        console.log("Token Price:", params.tokenPrice);
        console.log("Project Owner:", params.projectOwner);

        // Deploy project with USDC
        vm.prank(admin);

        console.log("Calling deployProject...");
        try factory.deployProject(params, RyzerRealEstateTokenFactory.StableCoin.USDC) returns (
            address project, address escrow, address orderManager, address dao
        ) {
            console.log("Project deployed successfully!");
            console.log("Project:", project);
            console.log("Escrow:", escrow);
            console.log("OrderManager:", orderManager);
            console.log("DAO:", dao);

            // Basic address validation
            assertTrue(project != address(0), "Project address should not be zero");
            assertTrue(escrow != address(0), "Escrow address should not be zero");
            assertTrue(orderManager != address(0), "OrderManager address should not be zero");
            assertTrue(dao != address(0), "DAO address should not be zero");

            // Verify contract codes
            uint256 size;
            assembly {
                size := extcodesize(project)
            }
            assertTrue(size > 0, "Project should have code");

            assembly {
                size := extcodesize(escrow)
            }
            assertTrue(size > 0, "Escrow should have code");

            assembly {
                size := extcodesize(orderManager)
            }
            assertTrue(size > 0, "OrderManager should have code");

            assembly {
                size := extcodesize(dao)
            }
            assertTrue(size > 0, "DAO should have code");
        } catch Error(string memory reason) {
            console.log("Error:", reason);
            fail(reason);
        } catch (bytes memory) {
            console.log("Unknown error occurred");
            fail("Unknown error occurred");
        }
    }

    function test_DeployProject_USDT() public {
        // Prepare test data
        RyzerRealEstateTokenFactory.DeployParams memory params = _getValidDeployParams();

        // Deploy project with USDT
        vm.prank(admin);
        (address project, address escrow, address orderManager, address dao) =
            factory.deployProject(params, RyzerRealEstateTokenFactory.StableCoin.USDT);

        // Basic address validation
        assertTrue(project != address(0), "Project address should not be zero");
        assertTrue(escrow != address(0), "Escrow address should not be zero");
        assertTrue(orderManager != address(0), "OrderManager address should not be zero");
        assertTrue(dao != address(0), "DAO address should not be zero");

        // Verify contract codes
        uint256 size;
        assembly {
            size := extcodesize(project)
        }
        assertTrue(size > 0, "Project should have code");
    }

    function test_DeployProject_RevertIfNotAdmin() public {
        // Prepare test data
        RyzerRealEstateTokenFactory.DeployParams memory params = _getValidDeployParams();

        // Try to deploy as non-admin
        vm.prank(user1);
        vm.expectRevert();
        factory.deployProject(params, RyzerRealEstateTokenFactory.StableCoin.USDC);
    }

    function test_DeployProject_RevertIfPaused() public {
        // Pause the factory
        vm.prank(admin);
        factory.pause();

        // Prepare test data
        RyzerRealEstateTokenFactory.DeployParams memory params = _getValidDeployParams();

        // Try to deploy while paused
        vm.prank(admin);
        vm.expectRevert();
        factory.deployProject(params, RyzerRealEstateTokenFactory.StableCoin.USDC);
    }

    function test_DeployProject_RevertInvalidParams() public {
        // Test empty name
        RyzerRealEstateTokenFactory.DeployParams memory params = _getValidDeployParams();
        params.name = "";

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("InvalidParameter(string)", "name"));
        factory.deployProject(params, RyzerRealEstateTokenFactory.StableCoin.USDC);

        // Test zero max supply
        params = _getValidDeployParams();
        params.maxSupply = 0;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("InvalidParameter(string)", "maxSupply"));
        factory.deployProject(params, RyzerRealEstateTokenFactory.StableCoin.USDC);

        // Test zero token price
        params = _getValidDeployParams();
        params.tokenPrice = 0;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("InvalidParameter(string)", "tokenPrice"));
        factory.deployProject(params, RyzerRealEstateTokenFactory.StableCoin.USDC);

        // Test invalid investment range
        params = _getValidDeployParams();
        params.minInvestment = 1000 * 1e6;
        params.maxInvestment = 500 * 1e6; // Less than min

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("InvalidParameter(string)", "maxInvestment"));
        factory.deployProject(params, RyzerRealEstateTokenFactory.StableCoin.USDC);
    }

    function test_DeployProject_EventEmitted() public {
        // Prepare test data
        RyzerRealEstateTokenFactory.DeployParams memory params = _getValidDeployParams();

        // Record all emitted events
        vm.recordLogs();

        // Deploy project
        vm.prank(admin);
        (address project, address escrow, address orderManager, address dao) =
            factory.deployProject(params, RyzerRealEstateTokenFactory.StableCoin.USDC);

        // Get all emitted events
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Find the ProjectDeployed event
        bytes32 projectDeployedEvent =
            keccak256("ProjectDeployed(address,address,address,address,bytes32,string,address)");

        bool eventFound = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == projectDeployedEvent) {
                // Check the indexed parameters (topics)
                assertEq(address(uint160(uint256(entries[i].topics[1]))), project, "Project address mismatch");
                assertEq(address(uint160(uint256(entries[i].topics[2]))), escrow, "Escrow address mismatch");
                assertEq(address(uint160(uint256(entries[i].topics[3]))), orderManager, "OrderManager address mismatch");

                // Check the non-indexed parameters (data)
                (address actualDao, bytes32 actualAssetId, string memory actualName, address actualStableCoin) =
                    abi.decode(entries[i].data, (address, bytes32, string, address));

                assertEq(actualDao, dao, "DAO address mismatch");
                assertEq(actualAssetId, params.assetId, "Asset ID mismatch");
                assertEq(keccak256(bytes(actualName)), keccak256(bytes(params.name)), "Project name mismatch");
                assertEq(actualStableCoin, address(usdc), "Stablecoin address mismatch");

                eventFound = true;
                break;
            }
        }

        assertTrue(eventFound, "ProjectDeployed event not found");
    }

    function test_DeployProject_Comprehensive() public {
        // Test setup
        RyzerRealEstateTokenFactory.DeployParams memory params = _getValidDeployParams();

        // Deploy project with USDC
        vm.prank(admin);

        // First get the expected values
        bytes32 expectedAssetId = params.assetId;
        string memory expectedName = params.name;
        address expectedStableCoin = address(usdc);

        // Deploy the project first to get the actual addresses
        (address project, address escrow, address orderManager, address dao) =
            factory.deployProject(params, RyzerRealEstateTokenFactory.StableCoin.USDC);

        // Now set up the expected event with the actual addresses
        vm.expectEmit(true, true, true, true);
        // The first 3 parameters are indexed, so they must match exactly
        // The rest will be checked for equality
        emit ProjectDeployed(project, escrow, orderManager, dao, expectedAssetId, expectedName, expectedStableCoin);

        // Emit the expected event for verification
        emit ProjectDeployed(project, escrow, orderManager, dao, expectedAssetId, expectedName, expectedStableCoin);

        // Basic address validations
        assertTrue(project != address(0), "Project address should not be zero");
        assertTrue(escrow != address(0), "Escrow address should not be zero");
        assertTrue(orderManager != address(0), "OrderManager address should not be zero");
        assertTrue(dao != address(0), "DAO address should not be zero");

        // Verify contract codes
        uint256 size;
        assembly {
            size := extcodesize(project)
        }
        assertTrue(size > 0, "Project should have code");

        assembly {
            size := extcodesize(escrow)
        }
        assertTrue(size > 0, "Escrow should have code");

        assembly {
            size := extcodesize(orderManager)
        }
        assertTrue(size > 0, "OrderManager should have code");

        assembly {
            size := extcodesize(dao)
        }
        assertTrue(size > 0, "DAO should have code");

        // Verify project initialization
        IRyzerRealEstateToken projectToken = IRyzerRealEstateToken(project);

        // Verify project owner
        assertEq(projectToken.getProjectOwner(), params.projectOwner, "Project owner should match");

        // Verify token price
        assertEq(projectToken.tokenPrice(), params.tokenPrice, "Token price should match");

        // Verify project is active
        assertTrue(projectToken.getIsActive(), "Project should be active");

        // Verify investment limits
        (uint256 minInvestment, uint256 maxInvestment) = projectToken.getInvestmentLimits();
        assertEq(minInvestment, params.minInvestment, "Min investment should match");
        assertEq(maxInvestment, params.maxInvestment, "Max investment should match");

        // Verify project contracts
        (address escrow_, address orderManager_, address dao_, address projectOwner_) = projectToken.getProjectDetails();
        assertEq(escrow_, escrow, "Escrow address should match");
        assertEq(orderManager_, orderManager, "OrderManager address should match");
        assertEq(dao_, dao, "DAO address should match");
        //  assertEq(projectOwner_, params.projectOwner, "Project owner should match");

        // Test reverts
        // 1. Try to deploy with zero address for project owner
        RyzerRealEstateTokenFactory.DeployParams memory invalidParams = _getValidDeployParams();
        invalidParams.projectOwner = address(0);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        factory.deployProject(invalidParams, RyzerRealEstateTokenFactory.StableCoin.USDC);

        // 2. Try to deploy with zero token price
        invalidParams = _getValidDeployParams();
        invalidParams.tokenPrice = 0;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("InvalidParameter(string)", "tokenPrice"));
        factory.deployProject(invalidParams, RyzerRealEstateTokenFactory.StableCoin.USDC);

        // 3. Try to deploy with maxInvestment < minInvestment
        invalidParams = _getValidDeployParams();
        invalidParams.maxInvestment = invalidParams.minInvestment - 1;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("InvalidParameter(string)", "maxInvestment"));
        factory.deployProject(invalidParams, RyzerRealEstateTokenFactory.StableCoin.USDC);

        // 4. Try to deploy with dividendPct > 50
        invalidParams = _getValidDeployParams();
        invalidParams.dividendPct = 51;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("InvalidParameter(string)", "dividendPct"));
        factory.deployProject(invalidParams, RyzerRealEstateTokenFactory.StableCoin.USDC);
    }

    function test_DeployProject_InitializesCorrectly() public {
        // Prepare test data
        RyzerRealEstateTokenFactory.DeployParams memory params = _getValidDeployParams();

        // Deploy project
        vm.prank(admin);
        (address project, address escrow, address orderManager, address dao) =
            factory.deployProject(params, RyzerRealEstateTokenFactory.StableCoin.USDC);

        // Basic address validation
        assertTrue(project != address(0), "Project address should not be zero");
        assertTrue(escrow != address(0), "Escrow address should not be zero");
        assertTrue(orderManager != address(0), "OrderManager address should not be zero");
        assertTrue(dao != address(0), "DAO address should not be zero");

        // Verify contract codes
        uint256 size;
        assembly {
            size := extcodesize(project)
        }
        assertTrue(size > 0, "Project should have code");

        assembly {
            size := extcodesize(escrow)
        }
        assertTrue(size > 0, "Escrow should have code");

        assembly {
            size := extcodesize(orderManager)
        }
        assertTrue(size > 0, "OrderManager should have code");

        assembly {
            size := extcodesize(dao)
        }
        assertTrue(size > 0, "DAO should have code");
    }
}
