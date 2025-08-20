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

import {RyzerDAO} from"../src/RyzerDAO.sol";
import {RyzerOrderManager} from"../src/RyzerOrderManager.sol";

import {RyzerEscrow} from"../src/RyzerEscrow.sol";
import {RyzerRealEstateToken} from"../src/RyzerRealEstateToken.sol";

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

RyzerDAO public ryzerDAO;
RyzerOrderManager public ryzerOrderManager;
RyzerEscrow public ryzerEscrow;
RyzerRealEstateToken public ryzerRealEstateToken;



    RyzerRealEstateTokenFactory public factory;
    RyzerRealEstateTokenFactory public implementation;
    ERC1967Proxy public proxy;

    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public projectOwner = address(0x3);
    address public identityRegistry = address(0x4);
    address public compliance = address(0x5);
    address public onchainID = address(0x6);

    address public projectTemplate = address(0x7);
    address public escrowTemplate = address(0x8);
    address public orderManagerTemplate = address(0x8);
    address public daoTemplate = address(0x8);

    function setUp() public {
        // Deploy mock tokens
        usdc = new UsdcMock();
        usdt = new UsdtMock();
        ryzerxToken = new MockERC20("Ryzer Token", "RYZER", 18);

        // Deploy implementation
        implementation = new RyzerRealEstateTokenFactory();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address)",
            address(usdc),
            address(usdt),
            address(ryzerxToken),
            address(projectTemplate),
            address(escrowTemplate),
            address(orderManagerTemplate),
            address(daoTemplate)
        );
        proxy = new ERC1967Proxy(address(implementation), initData);

        // Cast proxy to factory interface
        factory = RyzerRealEstateTokenFactory(address(proxy));

        // Grant admin role to test admin
        vm.prank(address(this));
        factory.grantRole(factory.ADMIN_ROLE(), admin);
    }

    function test_Initialize() public {
        // Deploy new implementation and proxy for clean test
        RyzerRealEstateTokenFactory newImpl = new RyzerRealEstateTokenFactory();

        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address)",
            address(usdc),
            address(usdt),
            address(ryzerxToken),
            address(projectTemplate),
            address(escrowTemplate),
            address(orderManagerTemplate),
            address(daoTemplate)
        );
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImpl), initData);
        RyzerRealEstateTokenFactory newFactory = RyzerRealEstateTokenFactory(address(newProxy));

        // Check initial state
        assertEq(address(newFactory.usdc()), address(usdc));
        assertEq(address(newFactory.usdt()), address(usdt));
        assertEq(address(newFactory.ryzerXToken()), address(ryzerxToken));
        assertEq(newFactory.projectTemplate(), address(projectTemplate));
        assertEq(newFactory.escrowTemplate(), address(escrowTemplate));
        assertEq(newFactory.orderManagerTemplate(), address(orderManagerTemplate));
        assertEq(newFactory.daoTemplate(), address(daoTemplate));

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
            maxSupply: 1000000 * 1e18,
            tokenPrice: 100 * 1e6, // $100 in USDC terms
            cancelDelay: 7 days,
            projectOwner: projectOwner,
            assetId: keccak256("asset123"),
            metadataCID: keccak256("metadata"),
            assetType: IRyzerRealEstateToken.AssetType.Commercial,
            legalMetadataCID: keccak256("legal"),
            dividendPct: 10,
            preMintAmount: 100000 * 1e18,
            minInvestment: 1000 * 1e6, // $1000
            maxInvestment: 100000 * 1e6 // $100,000
        });
    }

    function test_DeployProject_USDC() public {

    }
}
