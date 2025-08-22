// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/RyzerOrderManager.sol";
import "../src/interfaces/IRyzerEscrow.sol";
import "../src/interfaces/IRyzerRealEstateToken.sol";
import {RyzerEscrow} from "../src/RyzerEscrow.sol";
import {RyzerRealEstateToken} from "../src/RyzerRealEstateToken.sol";
import {UsdcMock} from "../src/USDCMock.sol";
import {UsdtMock} from "../src/UsdtMock.sol";
import {RyzerToken} from "../src/RyzerToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RyzerDAO} from "../src/RyzerDAO.sol";

contract RyzerOrderManagerTest is Test {
    RyzerOrderManager public orderManager;
    RyzerOrderManager public implementation;
    RyzerEscrow public escrow;
    RyzerRealEstateToken public project;
    UsdcMock public usdc;
    UsdtMock public usdt;
    RyzerToken public ryzer;
    RyzerDAO public ryzerDAO;
    
    address public owner = makeAddr("owner");
    address public admin = makeAddr("admin");
    address public operator = makeAddr("operator");
    address public buyer = makeAddr("buyer");
    address public projectOwner = makeAddr("projectOwner");
    address public feeRecipient = makeAddr("feeRecipient");
    address public factory = makeAddr("factory");
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    bytes32 public testAssetId = keccak256("TEST_ASSET");
    
    event OrderPlaced(
        bytes32 indexed id, 
        address indexed buyer, 
        uint128 tokens, 
        bytes32 assetId, 
        RyzerOrderManager.Currency currency, 
        uint128 total
    );
    event DocumentsSigned(bytes32 indexed id);
    event OrderFinalized(bytes32 indexed id);
    event OrderCancelled(bytes32 indexed id, address indexed buyer, uint128 refund);
    event FundsReleased(bytes32 indexed id, address indexed to, uint128 amount);
    
    function setUp() public {
        // Deploy mock tokens
        usdt = new UsdtMock();
        usdc = new UsdcMock();
        ryzer = new RyzerToken();
        ryzerDAO = new RyzerDAO();
        
        // Deploy escrow first
        escrow = new RyzerEscrow();
        
        // Deploy implementation and proxy for OrderManager
        implementation = new RyzerOrderManager();
        
        // Deploy project token
        project = new RyzerRealEstateToken();
        
        // Initialize escrow
        escrow.initialize(address(usdt), address(usdc), address(project), owner);
        
        // Initialize OrderManager with proxy
        bytes memory orderManagerInitData = abi.encodeCall(
            RyzerOrderManager.initialize,
            (address(escrow), address(project), owner)
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), orderManagerInitData);
        orderManager = RyzerOrderManager(address(proxy));
        
        // Configure project token
        RyzerRealEstateToken.TokenConfig memory config = RyzerRealEstateToken.TokenConfig({
            info: RyzerRealEstateToken.TokenInfo({
                name: "Test Real Estate Token",
                symbol: "TRET",
                decimals: 18,
                maxSupply: 1000000 * 10 ** 18,
                tokenPrice: 100 * 10 ** 6, // $100 in 6 decimals (USDT/USDC format)
                cancelDelay: 7 days,
                assetType: RyzerRealEstateToken.AssetType.Commercial
            }),
            gov: RyzerRealEstateToken.GovernanceConfig({
                identityRegistry: makeAddr("identityRegistry"),
                compliance: makeAddr("compliance"),
                onchainID: makeAddr("onchainID"),
                projectOwner: projectOwner,
                factory: factory,
                escrow: address(escrow),
                orderManager: address(orderManager),
                dao: address(ryzerDAO),
                companyId: keccak256("testCompany"),
                assetId: testAssetId,
                metadataCID: keccak256("testMetadata"),
                legalMetadataCID: keccak256("testLegalMetadata"),
                dividendPct: 25 // 25%
            }),
            policy: RyzerRealEstateToken.InvestmentPolicy({
                preMintAmount: 1000000 * 10 ** 18, // Pre-mint tokens to escrow
                minInvestment: 1000 * 10 ** 18,
                maxInvestment: 100000 * 10 ** 18,
                isActive: true
            })
        });

        // Initialize the project token
        bytes memory projectInitData = abi.encode(config);
        vm.prank(factory);
        project.initialize(projectInitData);

        // Set project contracts (this will mint pre-mint amount to escrow)
        vm.prank(projectOwner);
        project.setProjectContracts(address(escrow), address(orderManager), address(ryzerDAO), 0);
        
        // Setup OrderManager roles and configurations
        vm.startPrank(owner);
        orderManager.grantRole(ADMIN_ROLE, admin);
        orderManager.grantRole(OPERATOR_ROLE, operator);
        
        // Configure currencies
        orderManager.setCurrency(RyzerOrderManager.Currency.USDT, address(usdt), true);
        orderManager.setCurrency(RyzerOrderManager.Currency.USDC, address(usdc), true);
        orderManager.setCurrency(RyzerOrderManager.Currency.RYZER, address(ryzer), true);
        
        // Set required signatures for multisig
        orderManager.setRequiredSignatures(1);
        orderManager.setFeeRecipient(feeRecipient);
        vm.stopPrank();
        
        // Setup escrow admin role for orderManager to handle releases
        vm.prank(owner);
        escrow.grantRole(ADMIN_ROLE, address(orderManager));
        
        // Setup tokens for buyer
        usdt.mint(buyer, 1000000e6); // 1M USDT
        usdc.mint(buyer, 1000000e6); // 1M USDC
        ryzer.mint(buyer, 1000000e18); // 1M RYZER
        
        // Approve tokens from buyer
        vm.startPrank(buyer);
        usdt.approve(address(orderManager), type(uint256).max);
        usdc.approve(address(orderManager), type(uint256).max);
        ryzer.approve(address(orderManager), type(uint256).max);
        vm.stopPrank();
        
        // Grant project owner ADMIN_ROLE in escrow for deposit functionality
        vm.prank(owner);
        escrow.grantRole(ADMIN_ROLE, projectOwner);
    }
    
    function testPlaceOrderSuccess() public {
        uint128 amountTokens = 10000 * 10 ** 18; // 10,000 tokens
        uint256 currencyPrice = 1 * 10 ** 18; // 1 USDT = 1 USD
        uint128 fees = 50 * 10 ** 6; // 50 USDT additional fees
        
        RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
            projectAddress: address(project),
            escrowAddress: address(escrow),
            assetId: testAssetId,
            amountTokens: amountTokens,
            currencyPrice: currencyPrice,
            fees: fees,
            currency: RyzerOrderManager.Currency.USDT
        });
        
        // Calculate expected values
        uint256 tokenPrice = project.tokenPrice(); // 100 * 10^6 (in USDT decimals)
        uint256 value = (amountTokens * tokenPrice) / currencyPrice; // Should be 1,000,000 USDT (6 decimals)
        uint256 platformFeeBps = 250; // 2.5%
        uint128 platformFee = uint128(value * platformFeeBps / 10000);
        uint128 expectedTotal = uint128(value) + platformFee + fees;
        
        uint256 buyerBalanceBefore = usdt.balanceOf(buyer);
        
        vm.expectEmit(true, true, true, true);
        emit OrderPlaced(bytes32(0), buyer, amountTokens, testAssetId, RyzerOrderManager.Currency.USDT, expectedTotal);
        
        vm.prank(buyer);
        bytes32 orderId = orderManager.placeOrder(params);
        
        // Verify order was created
        RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(order.buyer, buyer);
        assertEq(order.amountTokens, amountTokens);
        assertEq(order.totalCurrency, expectedTotal);
        assertEq(order.fees, fees);
        assertEq(order.assetId, testAssetId);
        assertEq(uint(order.status), uint(RyzerOrderManager.OrderStatus.Pending));
        assertEq(uint(order.currency), uint(RyzerOrderManager.Currency.USDT));
        assertEq(order.projectAddress, address(project));
        assertEq(order.escrowAddress, address(escrow));
        assertEq(order.released, false);
        
        // Verify tokens were transferred from buyer
        uint256 buyerBalanceAfter = usdt.balanceOf(buyer);
        assertEq(buyerBalanceBefore - buyerBalanceAfter, expectedTotal);
    

    }
    
    function testPlaceOrderInsufficientBalance() public {
        uint128 amountTokens = 10000 * 10 ** 18;
        uint256 currencyPrice = 1 * 10 ** 18;
        uint128 fees = 50 * 10 ** 6;
        
        // Create a buyer with insufficient balance
        address poorBuyer = makeAddr("poorBuyer");
        usdt.mint(poorBuyer, 1000e6); // Only 1000 USDT
        
        vm.startPrank(poorBuyer);
        usdt.approve(address(orderManager), type(uint256).max);
        vm.stopPrank();
        
        RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
            projectAddress: address(project),
            escrowAddress: address(escrow),
            assetId: testAssetId,
            amountTokens: amountTokens,
            currencyPrice: currencyPrice,
            fees: fees,
            currency: RyzerOrderManager.Currency.USDT
        });
        
        vm.prank(poorBuyer);
        vm.expectRevert(RyzerOrderManager.InsufficientBalance.selector);
        orderManager.placeOrder(params);
    }
    
    function testPlaceOrderInvalidAmount() public {
        uint128 amountTokens = 500 * 10 ** 18; // Below minimum investment
        uint256 currencyPrice = 1 * 10 ** 18;
        uint128 fees = 50 * 10 ** 6;
        
        RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
            projectAddress: address(project),
            escrowAddress: address(escrow),
            assetId: testAssetId,
            amountTokens: amountTokens,
            currencyPrice: currencyPrice,
            fees: fees,
            currency: RyzerOrderManager.Currency.USDT
        });
        
        vm.prank(buyer);
        vm.expectRevert(RyzerOrderManager.BadAmount.selector);
        orderManager.placeOrder(params);
    }
    
    function testSignDocuments() public {
        // First place an order
        bytes32 orderId = _placeTestOrder();
        
        vm.expectEmit(true, false, false, false);
        emit DocumentsSigned(orderId);
        
        vm.prank(buyer);
        orderManager.signDocuments(orderId);
        
        RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(uint(order.status), uint(RyzerOrderManager.OrderStatus.DocumentsSigned));
    }
    
    function testSignDocumentsUnauthorized() public {
        bytes32 orderId = _placeTestOrder();
        
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(RyzerOrderManager.Unauthorized.selector);
        orderManager.signDocuments(orderId);
    }
    
    function testFinalizeOrderSuccess() public {
        // Place order and sign documents
        bytes32 orderId = _placeTestOrder();
        
        vm.prank(buyer);
        orderManager.signDocuments(orderId);
        
        uint256 buyerTokenBalanceBefore = project.balanceOf(buyer);
        uint256 escrowTokenBalanceBefore = project.balanceOf(address(escrow));
        
        vm.expectEmit(true, false, false, false);
        emit OrderFinalized(orderId);
        
        vm.prank(buyer);
        orderManager.finalizeOrder(orderId);
        
        // Verify order status
        RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(uint(order.status), uint(RyzerOrderManager.OrderStatus.Finalized));
        
        // Verify tokens were transferred from escrow to buyer
        uint256 buyerTokenBalanceAfter = project.balanceOf(buyer);
        uint256 escrowTokenBalanceAfter = project.balanceOf(address(escrow));
        
        assertEq(buyerTokenBalanceAfter - buyerTokenBalanceBefore, order.amountTokens);
        assertEq(escrowTokenBalanceBefore - escrowTokenBalanceAfter, order.amountTokens);
    }
    
    function testFinalizeOrderNotDocumentsSigned() public {
        bytes32 orderId = _placeTestOrder();
        
        vm.prank(buyer);
        vm.expectRevert(); // Should revert because documents not signed
        orderManager.finalizeOrder(orderId);
    }
    
    function testFinalizeOrderByAdmin() public {
        bytes32 orderId = _placeTestOrder();
        
        vm.prank(buyer);
        orderManager.signDocuments(orderId);
        
        // Admin should be able to finalize
        vm.prank(admin);
        orderManager.finalizeOrder(orderId);
        
        RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(uint(order.status), uint(RyzerOrderManager.OrderStatus.Finalized));
    }
    
    function testFinalizeOrderUnauthorized() public {
        bytes32 orderId = _placeTestOrder();
        
        vm.prank(buyer);
        orderManager.signDocuments(orderId);
        
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(RyzerOrderManager.Unauthorized.selector);
        orderManager.finalizeOrder(orderId);
    }
    
    function testCancelOrderSuccess() public {
        bytes32 orderId = _placeTestOrder();
        
        // Wait for cancellation delay
        vm.warp(block.timestamp + 1 days + 1);
        
        vm.expectEmit(true, true, false, true);
        emit OrderCancelled(orderId, buyer, 0); // Amount will be calculated
        
        vm.prank(buyer);
        orderManager.cancelOrder(orderId);
        
        RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(uint(order.status), uint(RyzerOrderManager.OrderStatus.Cancelled));
    }
    
    function testCancelOrderBeforeDelay() public {
        bytes32 orderId = _placeTestOrder();
        
        vm.prank(buyer);
        vm.expectRevert(RyzerOrderManager.Delay.selector);
        orderManager.cancelOrder(orderId);
    }
    
    function testCancelOrderByAdminNoDelay() public {
        bytes32 orderId = _placeTestOrder();
        
        // Admin should be able to cancel immediately
        vm.prank(admin);
        orderManager.cancelOrder(orderId);
        
        RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
        assertEq(uint(order.status), uint(RyzerOrderManager.OrderStatus.Cancelled));
    }
    
    function testOrderExpiry() public {
        bytes32 orderId = _placeTestOrder();
        
        // Fast forward past order expiry
        vm.warp(block.timestamp + 8 days);
        
        vm.prank(buyer);
        vm.expectRevert(RyzerOrderManager.OrderExpired.selector);
        orderManager.signDocuments(orderId);
    }
    
    function testMultipleOrdersFromSameBuyer() public {
        bytes32 orderId1 = _placeTestOrder();
        
        // Place another order with different parameters
        uint128 amountTokens2 = 5000 * 10 ** 18;
        RyzerOrderManager.PlaceOrderParams memory params2 = RyzerOrderManager.PlaceOrderParams({
            projectAddress: address(project),
            escrowAddress: address(escrow),
            assetId: keccak256("DIFFERENT_ASSET"),
            amountTokens: amountTokens2,
            currencyPrice: 1 * 10 ** 18,
            fees: 25 * 10 ** 6,
            currency: RyzerOrderManager.Currency.USDC
        });
        
        vm.prank(buyer);
        bytes32 orderId2 = orderManager.placeOrder(params2);
        
        // Verify both orders exist and are different
        assertNotEq(orderId1, orderId2);
        
        RyzerOrderManager.Order memory order1 = orderManager.getOrder(orderId1);
        RyzerOrderManager.Order memory order2 = orderManager.getOrder(orderId2);
        
        assertEq(order1.amountTokens, 10000 * 10 ** 18);
        assertEq(order2.amountTokens, 5000 * 10 ** 18);
        assertEq(uint(order1.currency), uint(RyzerOrderManager.Currency.USDT));
        assertEq(uint(order2.currency), uint(RyzerOrderManager.Currency.USDC));
    }
    
    // Helper function to place a standard test order
    function _placeTestOrder() internal returns (bytes32) {
        uint128 amountTokens = 10000 * 10 ** 18;
        uint256 currencyPrice = 1 * 10 ** 18;
        uint128 fees = 50 * 10 ** 6;
        
        RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
            projectAddress: address(project),
            escrowAddress: address(escrow),
            assetId: testAssetId,
            amountTokens: amountTokens,
            currencyPrice: currencyPrice,
            fees: fees,
            currency: RyzerOrderManager.Currency.USDT
        });
        
        vm.prank(buyer);
        return orderManager.placeOrder(params);
    }
    
    // Test edge cases and error conditions
    function testPlaceOrderWithZeroAssetId() public {
        RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
            projectAddress: address(project),
            escrowAddress: address(escrow),
            assetId: bytes32(0), // Zero asset ID
            amountTokens: 10000 * 10 ** 18,
            currencyPrice: 1 * 10 ** 18,
            fees: 50 * 10 ** 6,
            currency: RyzerOrderManager.Currency.USDT
        });
        
        vm.prank(buyer);
        vm.expectRevert(RyzerOrderManager.BadParameter.selector);
        orderManager.placeOrder(params);
    }
    
    function testPlaceOrderWithInactiveProject() public {
        // Deactivate the project
        vm.prank(projectOwner);
        project.deactivateProject("Test deactivation");
        
        RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
            projectAddress: address(project),
            escrowAddress: address(escrow),
            assetId: testAssetId,
            amountTokens: 10000 * 10 ** 18,
            currencyPrice: 1 * 10 ** 18,
            fees: 50 * 10 ** 6,
            currency: RyzerOrderManager.Currency.USDT
        });
        
        vm.prank(buyer);
        vm.expectRevert(RyzerOrderManager.BadParameter.selector);
        orderManager.placeOrder(params);
    }
    
    function testGetOrderDetails() public {
        bytes32 orderId = _placeTestOrder();
        
        RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
        
        assertEq(order.buyer, buyer);
        assertEq(order.assetId, testAssetId);
        assertEq(order.projectAddress, address(project));
        assertEq(order.escrowAddress, address(escrow));
        assertEq(uint(order.status), uint(RyzerOrderManager.OrderStatus.Pending));
        assertFalse(order.released);
        assertTrue(order.createdAt > 0);
        assertTrue(order.orderExpiry > order.createdAt);
    }
}