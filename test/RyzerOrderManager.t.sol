// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.24;

// import {Test, console} from "forge-std/Test.sol";
// import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// import {RyzerOrderManager} from "../src/RyzerOrderManager.sol";
// import {IRyzerEscrow} from "../src/interfaces/IRyzerEscrow.sol";
// import {IRyzerRealEstateToken} from "../src/interfaces/IRyzerRealEstateToken.sol";

// contract MockEscrow is IRyzerEscrow {
//     struct DepositInfo {
//         address buyer;
//         uint128 amount;
//         Asset token;
//         bytes32 assetId;
//     }

//     struct DisputeInfo {
//         uint256 id;
//         address buyer;
//         Asset token;
//         uint128 amount;
//         uint32 timestamp;
//         uint32 resolvedAt;
//         address resolvedBy;
//         bool isResolved;
//         string reason;
//     }

//     mapping(bytes32 => DepositInfo) private _deposits;
//     mapping(bytes32 => uint256) private _releaseSigCount;
//     mapping(bytes32 => mapping(address => bool)) private _releaseSigned;
//     mapping(bytes32 => uint256) private _disputeSigCount;
//     mapping(bytes32 => mapping(address => bool)) private _disputeSigned;
//     mapping(bytes32 => DisputeInfo) private _disputes;

//     uint8 private _requiredSigs = 1;
//     uint32 private _disputeNonce;
//     uint128 private _dividendPoolUSDT;
//     uint128 private _dividendPoolUSDC;

//     IERC20 private _usdt;
//     IERC20 private _usdc;
//     IRyzerRealEstateToken private _projectToken;
//     bool private _paused;

//     struct DepositInfo {
//         address buyer;
//         uint128 amount;
//         Asset token;
//         bytes32 assetId;
//     }

//     // Initialize function to match the interface
//     function initialize(address __usdt, address __usdc, address _project, address) external {
//         _usdt = IERC20(__usdt);
//         _usdc = IERC20(__usdc);
//         _projectToken = IRyzerRealEstateToken(_project);
//     }

//     // Core functions
//     function deposit(bytes32 orderId, address buyer, uint128 amount, Asset token, bytes32 assetId) external {
//         console.log("MockEscrow: deposit called");
//         _deposits[orderId] = DepositInfo(buyer, amount, token, assetId);
//     }

//     function signRelease(bytes32 orderId, address to, uint128 amount) external {
//         if (!_releaseSigned[orderId][msg.sender]) {
//             _releaseSigCount[orderId]++;
//             _releaseSigned[orderId][msg.sender] = true;
//         }
//     }

//     function depositDividend(Asset token, uint128 amount) external {
//         if (token == Asset.USDT) {
//             _dividendPoolUSDT += amount;
//         } else {
//             _dividendPoolUSDC += amount;
//         }
//     }

//     function distributeDividend(address recipient, Asset token, uint128 amount) external {
//         if (token == Asset.USDT) {
//             _dividendPoolUSDT -= amount;
//         } else {
//             _dividendPoolUSDC -= amount;
//         }
//     }

//     // View functions
//     function deposits(bytes32 orderId) external view returns (Deposit memory) {
//         DepositInfo storage d = _deposits[orderId];
//         return Deposit(d.buyer, d.amount, d.token, d.assetId);
//     }

//     function dividendPoolBalance(Asset token) external view returns (uint128) {
//         return token == Asset.USDT ? _dividendPoolUSDT : _dividendPoolUSDC;
//     }

//     function disputeNonce() external view returns (uint32) {
//         return _disputeNonce;
//     }

//     function disputes(bytes32 disputeId) external view returns (Dispute memory) {
//         DisputeInfo storage d = _disputes[disputeId];
//         return Dispute(d.id, d.buyer, d.token, d.amount, d.timestamp, d.resolvedAt, d.isResolved, d.resolvedBy, d.reason);
//     }

//     function disputeSigCount(bytes32 disputeId) external view returns (uint256) {
//         return _disputeSigCount[disputeId];
//     }

//     function disputeSigned(bytes32 disputeId, address signer) external view returns (bool) {
//         return _disputeSigned[disputeId][signer];
//     }

//     function getDisputeStatus(bytes32 disputeId) external view returns (Dispute memory) {
//         DisputeInfo storage d = _disputes[disputeId];
//         return Dispute(d.id, d.buyer, d.token, d.amount, d.timestamp, d.resolvedAt, d.isResolved, d.resolvedBy, d.reason);
//     }

//     function releaseSigCount(bytes32 orderId) external view returns (uint256) {
//         return _releaseSigCount[orderId];
//     }

//     function releaseSigned(bytes32 orderId, address signer) external view returns (bool) {
//         return _releaseSigned[orderId][signer];
//     }

//     function project() external view returns (IRyzerRealEstateToken) {
//         return _projectToken;
//     }

//     function requiredSigs() external view returns (uint8) {
//         return _requiredSigs;
//     }

//     function usdt() external view returns (IERC20) {
//         return _usdt;
//     }

//     function usdc() external view returns (IERC20) {
//         return _usdc;
//     }

//     // Admin functions
//     function emergencyWithdraw(address recipient, Asset token, uint128 amount) external {
//         // Implementation for emergency withdrawal
//     }

//     function pause() external {
//         _paused = true;
//     }

//     function unpause() external {
//         _paused = false;
//     }

//     function raiseDispute(bytes32 orderId, string calldata reason) external returns (bytes32) {
//         bytes32 disputeId = keccak256(abi.encodePacked(orderId, _disputeNonce));
//         _disputes[disputeId] = DisputeInfo({
//             id: _disputeNonce,
//             buyer: msg.sender,
//             token: _deposits[orderId].token,
//             amount: _deposits[orderId].amount,
//             timestamp: uint32(block.timestamp),
//             resolvedAt: 0,
//             resolvedBy: address(0),
//             isResolved: false,
//             reason: reason
//         });
//         _disputeNonce++;
//         return disputeId;
//     }

//     function setCoreContracts(address __usdt, address __usdc, address _project) external {
//         _usdt = IERC20(__usdt);
//         _usdc = IERC20(__usdc);
//         _projectToken = IRyzerRealEstateToken(_project);
//     }

//     function setRequiredSignatures(uint8 sigs) external {
//         _requiredSigs = sigs;
//     }

//     function signDisputeResolution(bytes32 disputeId, address resolvedTo) external {
//         if (!_disputeSigned[disputeId][msg.sender]) {
//             _disputeSigCount[disputeId]++;
//             _disputeSigned[disputeId][msg.sender] = true;

//             if (_disputeSigCount[disputeId] >= _requiredSigs) {
//                 DisputeInfo storage d = _disputes[disputeId];
//                 d.isResolved = true;
//                 d.resolvedAt = uint32(block.timestamp);
//                 d.resolvedBy = resolvedTo;
//             }
//         }
//     }

//     // Helper function for testing
//     function setReleaseSigned(bytes32 orderId, address signer, bool signed) external {
//         _releaseSigned[orderId][signer] = signed;
//         if (signed) {
//             _releaseSigCount[orderId]++;
//         } else if (_releaseSigned[orderId][signer]) {
//             _releaseSigCount[orderId]--;
//         }
//     }
// }

// contract MockRealEstateToken is IRyzerRealEstateToken {
//     // Token info
//     uint256 public tokenPrice = 1e18; // $1 per token
//     bool public isActive = true;
//     uint256 public minInvestment = 100e18; // 100 tokens
//     uint256 public maxInvestment = 10000e18; // 10,000 tokens
//     address public projectOwner;

//     // Project details
//     string public constant name = "Test Project";
//     string public constant symbol = "TP";
//     string public description = "Test Description";

//     // State
//     bool public paused;

//     constructor(address _owner) {
//         projectOwner = _owner;
//     }

//     // IRyzerRealEstateToken implementation
//     function getProjectDetails() external view returns (
//         address escrow,
//         address orderManager,
//         address dao,
//         address projectOwner_
//     ) {
//         return (address(0), address(0), address(0), projectOwner);
//     }

//     function initialize(bytes calldata) external pure {}

//     function deactivateProject(bytes32) external {
//         isActive = false;
//     }

//     function pause() external {
//         paused = true;
//     }

//     function unpause() external {
//         paused = false;
//     }

//     function setProjectContracts(address, address, address, uint256) external {}

//     function updateMetadataCID(bytes32, bool) external {}

//     // Test helper functions
//     function getProjectOwner() external view returns (address) {
//         return projectOwner;
//     }

//     function getIsActive() external view returns (bool) {
//         return isActive;
//     }

//     function getInvestmentLimits() external view returns (uint256, uint256) {
//         return (minInvestment, maxInvestment);
//     }

//     function setTokenPrice(uint256 _price) external {
//         tokenPrice = _price;
//     }

//     function setActive(bool _active) external {
//         isActive = _active;
//     }

//     function setInvestmentLimits(uint256 _min, uint256 _max) external {
//         minInvestment = _min;
//         maxInvestment = _max;
//     }

//     function setProjectOwner(address _owner) external {
//         projectOwner = _owner;
//     }
// }

// contract RyzerOrderManagerTest is Test {
//     RyzerOrderManager public orderManager;
//     MockEscrow public escrow;
//     MockRealEstateToken public project;
//     ERC20Mock public usdt;
//     ERC20Mock public usdc;
//     ERC20Mock public ryzer;

//     address public owner = makeAddr("owner");
//     address public admin1 = makeAddr("admin1");
//     address public admin2 = makeAddr("admin2");
//     address public operator1 = makeAddr("operator1");
//     address public buyer = makeAddr("buyer");
//     address public projectOwner = makeAddr("projectOwner");
//     address public feeRecipient = makeAddr("feeRecipient");

//     bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
//     bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
//     bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

//     // Test data
//     bytes32 public assetId = keccak256("testAsset");
//     uint128 public constant TOKEN_AMOUNT = 1000e18; // 1000 RWA tokens
//     uint128 public constant FEES = 50e6; // 50 USDT/USDC fees
//     uint256 public constant CURRENCY_PRICE = 1e18; // 1 USD = 1 USDT/USDC

//     // Events
//     event OrderPlaced(bytes32 indexed id, address indexed buyer, uint128 tokens, bytes32 assetId, RyzerOrderManager.Currency currency, uint128 total);
//     event DocumentsSigned(bytes32 indexed id);
//     event OrderFinalized(bytes32 indexed id);
//     event OrderCancelled(bytes32 indexed id, address indexed buyer, uint128 refund);
//     event ReleaseSigned(bytes32 indexed id, address indexed signer);
//     event FundsReleased(bytes32 indexed id, address indexed to, uint128 amount);

//     function setUp() public {
//         console.log("=== SETUP START ===");

//         // Deploy mock tokens
//         usdt = new ERC20Mock();
//         usdc = new ERC20Mock();
//         ryzer = new ERC20Mock();

//         console.log("Deployed tokens:");
//         console.log("  USDT:", address(usdt));
//         console.log("  USDC:", address(usdc));
//         console.log("  RYZER:", address(ryzer));

//         // Deploy mock contracts
//         project = new MockRealEstateToken(projectOwner);
//         escrow = new MockEscrow();

//         console.log("Deployed mocks:");
//         console.log("  Project:", address(project));
//         console.log("  Escrow:", address(escrow));

//         // Deploy and initialize OrderManager
//         address proxy = Upgrades.deployUUPSProxy(
//             "RyzerOrderManager.sol",
//             abi.encodeWithSelector(
//                 RyzerOrderManager.initialize.selector,
//                 address(escrow),
//                 address(project),
//                 owner
//             )
//         );

//         orderManager = RyzerOrderManager(proxy);
//         console.log("OrderManager deployed at:", address(orderManager));

//         // Setup roles
//         vm.startPrank(owner);
//         orderManager.grantRole(ADMIN_ROLE, admin1);
//         orderManager.grantRole(ADMIN_ROLE, admin2);
//         orderManager.grantRole(OPERATOR_ROLE, operator1);

//         // Setup currencies
//         orderManager.setCurrency(RyzerOrderManager.Currency.USDT, address(usdt), true);
//         orderManager.setCurrency(RyzerOrderManager.Currency.USDC, address(usdc), true);
//         orderManager.setCurrency(RyzerOrderManager.Currency.RYZER, address(ryzer), true);

//         // Set required signatures
//         orderManager.setRequiredSignatures(2);
//         vm.stopPrank();

//         // Mint tokens and approve
//         _setupTokens();

//         console.log("=== SETUP COMPLETE ===\n");
//     }

//     function _setupTokens() internal {
//         console.log("Setting up tokens...");

//         // Mint tokens to buyer
//         usdt.mint(buyer, 100000e6); // 100,000 USDT
//         usdc.mint(buyer, 100000e6); // 100,000 USDC
//         ryzer.mint(buyer, 100000e18); // 100,000 RYZER

//         // Approve OrderManager to spend tokens
//         vm.startPrank(buyer);
//         usdt.approve(address(orderManager), type(uint256).max);
//         usdc.approve(address(orderManager), type(uint256).max);
//         ryzer.approve(address(orderManager), type(uint256).max);
//         vm.stopPrank();

//         console.log("Buyer token balances:");
//         console.log("  USDT:", usdt.balanceOf(buyer) / 1e6);
//         console.log("  USDC:", usdc.balanceOf(buyer) / 1e6);
//         console.log("  RYZER:", ryzer.balanceOf(buyer) / 1e18);
//     }

//     /*//////////////////////////////////////////////////////////////
//                          INITIALIZATION TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testInitialization() public {
//         console.log("\n=== TEST: Initialization ===");

//         assertEq(orderManager.escrow(), address(escrow));
//         assertEq(orderManager.project(), address(project));
//         assertEq(orderManager.platformFeeBps(), 250); // 2.5%
//         assertEq(orderManager.requiredSigs(), 2);
//         assertTrue(orderManager.hasRole(DEFAULT_ADMIN_ROLE, owner));
//         assertTrue(orderManager.hasRole(ADMIN_ROLE, owner));

//     }

//     function testSetCurrency() public {
//         console.log("\n=== TEST: Set Currency ===");

//         RyzerOrderManager.CurrencyInfo memory info = orderManager.currencyInfo(RyzerOrderManager.Currency.USDT);
//         assertEq(address(info.token), address(usdt));
//         assertTrue(info.active);
//         assertEq(info.decimals, 18); // ERC20Mock uses 18 decimals

//         console.log("USDT currency info:");
//         console.log("  token:", address(info.token));
//         console.log("  decimals:", info.decimals);
//         console.log("  active:", info.active);
//     }

//     /*//////////////////////////////////////////////////////////////
//                            ORDER PLACEMENT TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testPlaceOrder() public {
//         console.log("\n=== TEST: Place Order ===");

//         RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
//             projectAddress: address(project),
//             escrowAddress: address(escrow),
//             assetId: assetId,
//             amountTokens: TOKEN_AMOUNT,
//             currencyPrice: CURRENCY_PRICE,
//             fees: FEES,
//             currency: RyzerOrderManager.Currency.USDT
//         });

//         console.log("Order parameters:");
//         console.log("  amountTokens:", TOKEN_AMOUNT / 1e18);
//         console.log("  currencyPrice:", CURRENCY_PRICE / 1e18);
//         console.log("  fees:", FEES / 1e6);

//         uint256 buyerBalanceBefore = usdt.balanceOf(buyer);
//         console.log("Buyer USDT balance before:", buyerBalanceBefore / 1e6);

//         vm.expectEmit(false, true, false, false);
//         emit OrderPlaced(bytes32(0), buyer, TOKEN_AMOUNT, assetId, RyzerOrderManager.Currency.USDT, 0);

//         vm.prank(buyer);
//         bytes32 orderId = orderManager.placeOrder(params);

//         console.log("Order placed with ID:", uint256(orderId));

//         RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
//         assertEq(order.buyer, buyer);
//         assertEq(order.amountTokens, TOKEN_AMOUNT);
//         assertEq(order.assetId, assetId);
//         assertTrue(order.status == RyzerOrderManager.OrderStatus.Pending);
//         assertTrue(order.currency == RyzerOrderManager.Currency.USDT);

//         uint256 buyerBalanceAfter = usdt.balanceOf(buyer);
//         console.log("Buyer USDT balance after:", buyerBalanceAfter / 1e6);
//         console.log("Total currency amount:", order.totalCurrency / 1e6);

//         console.log("Order details:");
//         console.log("  buyer:", order.buyer);
//         console.log("  amountTokens:", order.amountTokens / 1e18);
//         console.log("  totalCurrency:", order.totalCurrency / 1e6);
//         console.log("  fees:", order.fees / 1e6);
//         console.log("  status:", uint8(order.status));
//     }

//     function testPlaceOrderUSDC() public {
//         console.log("\n=== TEST: Place Order USDC ===");

//         RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
//             projectAddress: address(project),
//             escrowAddress: address(escrow),
//             assetId: assetId,
//             amountTokens: TOKEN_AMOUNT,
//             currencyPrice: CURRENCY_PRICE,
//             fees: FEES,
//             currency: RyzerOrderManager.Currency.USDC
//         });

//         vm.prank(buyer);
//         bytes32 orderId = orderManager.placeOrder(params);

//         RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
//         assertTrue(order.currency == RyzerOrderManager.Currency.USDC);

//         console.log("  orderId:", uint256(orderId));
//         console.log("  totalCurrency:", order.totalCurrency / 1e6);
//     }

//     function testPlaceOrderInvalidProject() public {
//         console.log("\n=== TEST: Place Order Invalid Project ===");

//         project.setActive(false);

//         RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
//             projectAddress: address(project),
//             escrowAddress: address(escrow),
//             assetId: assetId,
//             amountTokens: TOKEN_AMOUNT,
//             currencyPrice: CURRENCY_PRICE,
//             fees: FEES,
//             currency: RyzerOrderManager.Currency.USDT
//         });

//         vm.expectRevert(RyzerOrderManager.BadParameter.selector);
//         vm.prank(buyer);
//         orderManager.placeOrder(params);

//         console.log("  Correctly rejected inactive project");
//     }

//     function testPlaceOrderInsufficientBalance() public {
//         console.log("\n=== TEST: Place Order Insufficient Balance ===");

//         // Create a buyer with insufficient balance
//         address poorBuyer = makeAddr("poorBuyer");
//         usdt.mint(poorBuyer, 100e6); // Only 100 USDT

//         vm.prank(poorBuyer);
//         usdt.approve(address(orderManager), type(uint256).max);

//         RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
//             projectAddress: address(project),
//             escrowAddress: address(escrow),
//             assetId: assetId,
//             amountTokens: TOKEN_AMOUNT, // This will require much more than 100 USDT
//             currencyPrice: CURRENCY_PRICE,
//             fees: FEES,
//             currency: RyzerOrderManager.Currency.USDT
//         });

//         vm.expectRevert(RyzerOrderManager.InsufficientBalance.selector);
//         vm.prank(poorBuyer);
//         orderManager.placeOrder(params);

//         console.log("  Correctly rejected insufficient balance");
//     }

//     /*//////////////////////////////////////////////////////////////
//                          ORDER WORKFLOW TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testFullOrderWorkflow() public {
//         console.log("\n=== TEST: Full Order Workflow ===");

//         // 1. Place order
//         console.log("Step 1: Placing order...");
//         bytes32 orderId = _placeTestOrder();
//         console.log("  Order placed:", uint256(orderId));

//         // 2. Sign documents
//         console.log("Step 2: Signing documents...");
//         vm.expectEmit(true, false, false, false);
//         emit DocumentsSigned(orderId);

//         vm.prank(buyer);
//         orderManager.signDocuments(orderId);

//         RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
//         assertTrue(order.status == RyzerOrderManager.OrderStatus.DocumentsSigned);
//         console.log("    Documents signed");

//         // 3. Finalize order
//         console.log("Step 3: Finalizing order...");
//         vm.expectEmit(true, false, false, false);
//         emit OrderFinalized(orderId);

//         vm.prank(buyer);
//         orderManager.finalizeOrder(orderId);

//         order = orderManager.getOrder(orderId);
//         assertTrue(order.status == RyzerOrderManager.OrderStatus.Finalized);
//         assertGt(order.releaseAfter, 0);
//         console.log("    Order finalized");
//         console.log("  Release after:", order.releaseAfter);

//         // 4. Wait for timelock and release funds
//         console.log("Step 4: Releasing funds...");
//         vm.warp(block.timestamp + 8 days); // Past the 7-day timelock

//         // First admin signs
//         vm.prank(admin1);
//         orderManager.signRelease(orderId);
//         assertEq(orderManager.releaseSigCount(orderId), 1);
//         console.log("  Admin1 signed release");

//         // Second admin signs (should trigger release)
//         vm.expectEmit(true, true, false, true);
//         emit FundsReleased(orderId, projectOwner, order.totalCurrency);

//         vm.prank(admin2);
//         orderManager.signRelease(orderId);

//         order = orderManager.getOrder(orderId);
//         assertTrue(order.released);
//         console.log("    Funds released to project owner");
//         console.log("  Released amount:", order.totalCurrency / 1e6);

//         console.log("  Full workflow completed successfully");
//     }

//     function testSignDocumentsUnauthorized() public {
//         console.log("\n=== TEST: Sign Documents Unauthorized ===");

//         bytes32 orderId = _placeTestOrder();

//         vm.expectRevert(RyzerOrderManager.Unauthorized.selector);
//         vm.prank(makeAddr("unauthorized"));
//         orderManager.signDocuments(orderId);

//         console.log("  Correctly rejected unauthorized document signing");
//     }

//     function testFinalizeOrderExpired() public {
//         console.log("\n=== TEST: Finalize Order Expired ===");

//         bytes32 orderId = _placeTestOrder();

//         // Warp past order expiry (7 days)
//         vm.warp(block.timestamp + 8 days);

//         vm.expectRevert(RyzerOrderManager.OrderExpired.selector);
//         vm.prank(buyer);
//         orderManager.finalizeOrder(orderId);

//         console.log("  Correctly rejected expired order finalization");
//     }

//     /*//////////////////////////////////////////////////////////////
//                          ORDER CANCELLATION TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testCancelOrderByBuyer() public {
//         console.log("\n=== TEST: Cancel Order By Buyer ===");

//         bytes32 orderId = _placeTestOrder();

//         // Warp past cancellation delay (1 day)
//         vm.warp(block.timestamp + 2 days);

//         RyzerOrderManager.Order memory orderBefore = orderManager.getOrder(orderId);
//         console.log("Order status before cancellation:", uint8(orderBefore.status));

//         vm.expectEmit(true, true, false, true);
//         emit OrderCancelled(orderId, buyer, orderBefore.totalCurrency);

//         vm.prank(buyer);
//         orderManager.cancelOrder(orderId);

//         RyzerOrderManager.Order memory orderAfter = orderManager.getOrder(orderId);
//         assertTrue(orderAfter.status == RyzerOrderManager.OrderStatus.Cancelled);

//         console.log("  Order cancelled successfully");
//         console.log("  Refund amount:", orderAfter.totalCurrency / 1e6);
//     }

//     function testCancelOrderByAdmin() public {
//         console.log("\n=== TEST: Cancel Order By Admin ===");

//         bytes32 orderId = _placeTestOrder();

//         // Admin can cancel immediately (no delay)
//         vm.prank(admin1);
//         orderManager.cancelOrder(orderId);

//         RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
//         assertTrue(order.status == RyzerOrderManager.OrderStatus.Cancelled);

//         console.log("  Admin cancelled order immediately");
//     }

//     function testCancelOrderTooEarly() public {
//         console.log("\n=== TEST: Cancel Order Too Early ===");

//         bytes32 orderId = _placeTestOrder();

//         // Try to cancel immediately (should fail for non-admin)
//         vm.expectRevert(RyzerOrderManager.Delay.selector);
//         vm.prank(buyer);
//         orderManager.cancelOrder(orderId);

//         console.log("  Correctly enforced cancellation delay");
//     }

//     function testCancelFinalizedOrder() public {
//         console.log("\n=== TEST: Cancel Finalized Order ===");

//         bytes32 orderId = _placeTestOrder();

//         // Sign documents and finalize
//         vm.prank(buyer);
//         orderManager.signDocuments(orderId);

//         vm.prank(buyer);
//         orderManager.finalizeOrder(orderId);

//         // Try to cancel finalized order (should fail)
//         vm.expectRevert(RyzerOrderManager.OrderNotFinalized.selector);
//         vm.prank(buyer);
//         orderManager.cancelOrder(orderId);

//         console.log("  Correctly prevented cancellation of finalized order");
//     }

//     /*//////////////////////////////////////////////////////////////
//                          MULTISIG RELEASE TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testSignReleaseBeforeTimelock() public {
//         console.log("\n=== TEST: Sign Release Before Timelock ===");

//         bytes32 orderId = _createFinalizedOrder();

//         // Try to sign release before timelock expires
//         vm.expectRevert(RyzerOrderManager.Timelock.selector);
//         vm.prank(admin1);
//         orderManager.signRelease(orderId);

//         console.log("  Correctly enforced release timelock");
//     }

//     function testSignReleaseAlreadySigned() public {
//         console.log("\n=== TEST: Sign Release Already Signed ===");

//         bytes32 orderId = _createFinalizedOrder();

//         // Warp past timelock
//         vm.warp(block.timestamp + 8 days);

//         // First signature
//         vm.prank(admin1);
//         orderManager.signRelease(orderId);

//         // Try to sign again with same admin
//         vm.expectRevert(RyzerOrderManager.AlreadySigned.selector);
//         vm.prank(admin1);
//         orderManager.signRelease(orderId);

//         console.log("  Correctly prevented double signing");
//     }

//     function testSignReleaseUnauthorized() public {
//         console.log("\n=== TEST: Sign Release Unauthorized ===");

//         bytes32 orderId = _createFinalizedOrder();
//         vm.warp(block.timestamp + 8 days);

//         vm.expectRevert();
//         vm.prank(buyer);
//         orderManager.signRelease(orderId);

//         console.log("  Correctly rejected unauthorized release signing");
//     }

//     /*//////////////////////////////////////////////////////////////
//                          STUCK ORDER RESOLUTION TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testResolveStuckOrder() public {
//         console.log("\n=== TEST: Resolve Stuck Order ===");

//         bytes32 orderId = _placeTestOrder();

//         // Warp past order expiry
//         vm.warp(block.timestamp + 8 days);

//         RyzerOrderManager.Order memory orderBefore = orderManager.getOrder(orderId);
//         console.log("Order status before resolution:", uint8(orderBefore.status));
//         console.log("Order expiry:", orderBefore.orderExpiry);
//         console.log("Current timestamp:", block.timestamp);

//         vm.expectEmit(true, true, false, true);

//         vm.prank(admin1);
//         orderManager.resolveStuckOrder(orderId);

//         RyzerOrderManager.Order memory orderAfter = orderManager.getOrder(orderId);
//         assertTrue(orderAfter.status == RyzerOrderManager.OrderStatus.Cancelled);

//         console.log("  Stuck order resolved successfully");
//     }

//     function testResolveStuckOrderNotExpired() public {
//         console.log("\n=== TEST: Resolve Stuck Order Not Expired ===");

//         bytes32 orderId = _placeTestOrder();

//         // Don't warp time - order should not be stuck yet
//         vm.expectRevert(RyzerOrderManager.Stuck.selector);
//         vm.prank(admin1);
//         orderManager.resolveStuckOrder(orderId);

//         console.log("  Correctly rejected resolution of non-stuck order");
//     }

//     /*//////////////////////////////////////////////////////////////
//                          ADMIN FUNCTION TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testSetRequiredSignatures() public {
//         console.log("\n=== TEST: Set Required Signatures ===");

//         console.log("Current required signatures:", orderManager.requiredSigs());

//         vm.prank(admin1);
//         orderManager.setRequiredSignatures(3);

//         assertEq(orderManager.requiredSigs(), 3);
//         console.log("  Required signatures updated to:", orderManager.requiredSigs());
//     }

//     function testSetRequiredSignaturesInvalid() public {
//         console.log("\n=== TEST: Set Required Signatures Invalid ===");

//         // Test zero signatures
//         vm.expectRevert(RyzerOrderManager.BadParameter.selector);
//         vm.prank(admin1);
//         orderManager.setRequiredSignatures(0);

//         // Test too many signatures
//         vm.expectRevert(RyzerOrderManager.BadParameter.selector);
//         vm.prank(admin1);
//         orderManager.setRequiredSignatures(11);

//         console.log("  Correctly rejected invalid signature counts");
//     }

//     function testSetPlatformFee() public {
//         console.log("\n=== TEST: Set Platform Fee ===");

//         console.log("Current platform fee:", orderManager.platformFeeBps(), "bps");

//         vm.prank(admin1);
//         orderManager.setPlatformFee(500); // 5%

//         assertEq(orderManager.platformFeeBps(), 500);
//         console.log("  Platform fee updated to:", orderManager.platformFeeBps(), "bps");
//     }

//     function testSetPlatformFeeInvalid() public {
//         console.log("\n=== TEST: Set Platform Fee Invalid ===");

//         // Test fee too high (>10%)
//         vm.expectRevert(RyzerOrderManager.BadParameter.selector);
//         vm.prank(admin1);
//         orderManager.setPlatformFee(1001);

//         console.log("  Correctly rejected excessive platform fee");
//     }

//     function testEmergencyWithdraw() public {
//         console.log("\n=== TEST: Emergency Withdraw ===");

//         // First place an order to have some funds in the contract
//         _placeTestOrder();

//         uint256 withdrawAmount = 1000e6;
//         uint256 balanceBefore = usdt.balanceOf(admin1);

//         console.log("Admin balance before withdrawal:", balanceBefore / 1e6);
//         console.log("Withdrawal amount:", withdrawAmount / 1e6);

//         vm.prank(admin1);
//         orderManager.emergencyWithdraw(RyzerOrderManager.Currency.USDT, admin1, uint128(withdrawAmount));

//         uint256 balanceAfter = usdt.balanceOf(admin1);
//         console.log("Admin balance after withdrawal:", balanceAfter / 1e6);

//         console.log("  Emergency withdrawal completed");
//     }

//     /*//////////////////////////////////////////////////////////////
//                          PAUSE/UNPAUSE TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testPauseUnpause() public {
//         console.log("\n=== TEST: Pause/Unpause ===");

//         // Test pause
//         vm.prank(admin1);
//         orderManager.pause();
//         assertTrue(orderManager.paused());
//         console.log("  Contract paused");

//         // Test that functions revert when paused
//         RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
//             projectAddress: address(project),
//             escrowAddress: address(escrow),
//             assetId: assetId,
//             amountTokens: TOKEN_AMOUNT,
//             currencyPrice: CURRENCY_PRICE,
//             fees: FEES,
//             currency: RyzerOrderManager.Currency.USDT
//         });

//         vm.expectRevert();
//         vm.prank(buyer);
//         orderManager.placeOrder(params);
//         console.log("  Order placement correctly blocked when paused");

//         // Test unpause
//         vm.prank(admin1);
//         orderManager.unpause();
//         assertFalse(orderManager.paused());
//         console.log("  Contract unpaused");

//         // Test that functions work after unpause
//         vm.prank(buyer);
//         orderManager.placeOrder(params);
//         console.log("  Order placement works after unpause");
//     }

//     /*//////////////////////////////////////////////////////////////
//                          VIEW FUNCTION TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testViewFunctions() public {
//         console.log("\n=== TEST: View Functions ===");

//         // Test currency support
//         assertTrue(orderManager.isSupported(RyzerOrderManager.Currency.USDT));
//         assertTrue(orderManager.isSupported(RyzerOrderManager.Currency.USDC));
//         console.log("  Currency support correctly detected");

//         // Test currency info
//         RyzerOrderManager.CurrencyInfo memory usdtInfo = orderManager.currencyInfo(RyzerOrderManager.Currency.USDT);
//         assertEq(address(usdtInfo.token), address(usdt));
//         assertTrue(usdtInfo.active);
//         console.log("  Currency info correctly retrieved");

//         // Test order that doesn't exist
//         RyzerOrderManager.Order memory emptyOrder = orderManager.getOrder(bytes32("nonexistent"));
//         assertEq(emptyOrder.buyer, address(0));
//         console.log("  Non-existent order correctly returns empty data");

//         // Test release signature counts
//         bytes32 orderId = _placeTestOrder();
//         assertEq(orderManager.releaseSigCount(orderId), 0);
//         assertFalse(orderManager.hasSignedRelease(orderId, admin1));
//         console.log("  Release signature tracking works correctly");
//     }

//     /*//////////////////////////////////////////////////////////////
//                          EDGE CASES & FUZZING
//     //////////////////////////////////////////////////////////////*/

//     function testFuzzOrderAmount(uint128 amount) public {
//         console.log("\n=== FUZZ TEST: Order Amount ===");
//         console.log("Testing amount:", amount / 1e18);

//         vm.assume(amount >= 100e18 && amount <= 10000e18); // Within project limits

//         RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
//             projectAddress: address(project),
//             escrowAddress: address(escrow),
//             assetId: assetId,
//             amountTokens: amount,
//             currencyPrice: CURRENCY_PRICE,
//             fees: FEES,
//             currency: RyzerOrderManager.Currency.USDT
//         });

//         // Ensure buyer has enough tokens
//         uint256 totalNeeded = (amount * 1e18 / 1e18) + (amount * 250 / 10000) + FEES; // rough calculation
//         usdt.mint(buyer, totalNeeded * 2); // Mint extra to be safe

//         vm.prank(buyer);
//         bytes32 orderId = orderManager.placeOrder(params);

//         RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
//         assertEq(order.amountTokens, amount);

//         console.log("  Fuzz test passed for amount:", amount / 1e18);
//     }

//     function testFuzzCurrencyPrice(uint256 price) public {
//         console.log("\n=== FUZZ TEST: Currency Price ===");

//         vm.assume(price >= 0.1e18 && price <= 10e18); // Between $0.1 and $10
//         console.log("Testing price:", price / 1e18);

//         RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
//             projectAddress: address(project),
//             escrowAddress: address(escrow),
//             assetId: assetId,
//             amountTokens: TOKEN_AMOUNT,
//             currencyPrice: price,
//             fees: FEES,
//             currency: RyzerOrderManager.Currency.USDT
//         });

//         // Ensure buyer has enough tokens
//         usdt.mint(buyer, 1000000e6); // Large amount for fuzz testing

//         vm.prank(buyer);
//         bytes32 orderId = orderManager.placeOrder(params);

//         RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
//         assertGt(order.totalCurrency, 0);

//         console.log("  Fuzz test passed for price:", price / 1e18);
//     }

//     function testMultipleConcurrentOrders() public {
//         console.log("\n=== TEST: Multiple Concurrent Orders ===");

//         address buyer2 = makeAddr("buyer2");
//         address buyer3 = makeAddr("buyer3");

//         // Setup additional buyers
//         usdt.mint(buyer2, 100000e6);
//         usdt.mint(buyer3, 100000e6);

//         vm.prank(buyer2);
//         usdt.approve(address(orderManager), type(uint256).max);
//         vm.prank(buyer3);
//         usdt.approve(address(orderManager), type(uint256).max);

//         RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
//             projectAddress: address(project),
//             escrowAddress: address(escrow),
//             assetId: assetId,
//             amountTokens: TOKEN_AMOUNT,
//             currencyPrice: CURRENCY_PRICE,
//             fees: FEES,
//             currency: RyzerOrderManager.Currency.USDT
//         });

//         // Place multiple orders
//         vm.prank(buyer);
//         bytes32 orderId1 = orderManager.placeOrder(params);
//         console.log("Order 1 placed:", uint256(orderId1));

//         params.assetId = keccak256("asset2");
//         vm.prank(buyer2);
//         bytes32 orderId2 = orderManager.placeOrder(params);
//         console.log("Order 2 placed:", uint256(orderId2));

//         params.assetId = keccak256("asset3");
//         vm.prank(buyer3);
//         bytes32 orderId3 = orderManager.placeOrder(params);
//         console.log("Order 3 placed:", uint256(orderId3));

//         // Verify all orders exist and are unique
//         RyzerOrderManager.Order memory order1 = orderManager.getOrder(orderId1);
//         RyzerOrderManager.Order memory order2 = orderManager.getOrder(orderId2);
//         RyzerOrderManager.Order memory order3 = orderManager.getOrder(orderId3);

//         assertEq(order1.buyer, buyer);
//         assertEq(order2.buyer, buyer2);
//         assertEq(order3.buyer, buyer3);

//         assertTrue(orderId1 != orderId2);
//         assertTrue(orderId2 != orderId3);
//         assertTrue(orderId1 != orderId3);

//         console.log("  Multiple concurrent orders handled correctly");
//     }

//     function testOrderLifecycleWithMultipleSignatures() public {
//         console.log("\n=== TEST: Order Lifecycle With Multiple Signatures ===");

//         // Set higher signature requirement
//         vm.prank(admin1);
//         orderManager.setRequiredSignatures(3);
//         console.log("Required signatures set to: 3");

//         // Add third admin
//         address admin3 = makeAddr("admin3");
//         vm.prank(owner);
//         orderManager.grantRole(ADMIN_ROLE, admin3);
//         console.log("Third admin added:", admin3);

//         bytes32 orderId = _createFinalizedOrder();
//         vm.warp(block.timestamp + 8 days);

//         // First two signatures shouldn't trigger release
//         vm.prank(admin1);
//         orderManager.signRelease(orderId);
//         console.log("Admin1 signed, count:", orderManager.releaseSigCount(orderId));

//         vm.prank(admin2);
//         orderManager.signRelease(orderId);
//         console.log("Admin2 signed, count:", orderManager.releaseSigCount(orderId));

//         RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
//         assertFalse(order.released);
//         console.log("Order not yet released (need 3 signatures)");

//         // Third signature should trigger release
//         vm.expectEmit(true, true, false, true);
//         emit FundsReleased(orderId, projectOwner, order.totalCurrency);

//         vm.prank(admin3);
//         orderManager.signRelease(orderId);
//         console.log("Admin3 signed, count:", orderManager.releaseSigCount(orderId));

//         order = orderManager.getOrder(orderId);
//         assertTrue(order.released);
//         console.log("  Order released after 3 signatures");
//     }

//     /*//////////////////////////////////////////////////////////////
//                          INTEGRATION TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testIntegrationWithRealEstateToken() public {
//         console.log("\n=== TEST: Integration With Real Estate Token ===");

//         // Test with different token price
//         project.setTokenPrice(2e18); // $2 per token
//         console.log("Token price set to: $2");

//         RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
//             projectAddress: address(project),
//             escrowAddress: address(escrow),
//             assetId: assetId,
//             amountTokens: TOKEN_AMOUNT,
//             currencyPrice: CURRENCY_PRICE,
//             fees: FEES,
//             currency: RyzerOrderManager.Currency.USDT
//         });

//         vm.prank(buyer);
//         bytes32 orderId = orderManager.placeOrder(params);

//         RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);

//         // Should cost more due to higher token price
//         console.log("Total currency for $2 tokens:", order.totalCurrency / 1e6);
//         assertGt(order.totalCurrency, 1000e6); // Should be more than $1000

//         console.log("  Integration with token price works correctly");
//     }

//     function testIntegrationWithInvestmentLimits() public {
//         console.log("\n=== TEST: Integration With Investment Limits ===");

//         // Set tight investment limits
//         project.setInvestmentLimits(500e18, 1500e18); // 500-1500 tokens
//         console.log("Investment limits set to: 500-1500 tokens");

//         RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
//             projectAddress: address(project),
//             escrowAddress: address(escrow),
//             assetId: assetId,
//             amountTokens: 2000e18, // Above limit
//             currencyPrice: CURRENCY_PRICE,
//             fees: FEES,
//             currency: RyzerOrderManager.Currency.USDT
//         });

//         vm.expectRevert(RyzerOrderManager.BadAmount.selector);
//         vm.prank(buyer);
//         orderManager.placeOrder(params);
//         console.log("  Correctly rejected order above investment limit");

//         // Test with amount within limits
//         params.amountTokens = 1000e18;
//         vm.prank(buyer);
//         bytes32 orderId = orderManager.placeOrder(params);

//         RyzerOrderManager.Order memory order = orderManager.getOrder(orderId);
//         assertEq(order.amountTokens, 1000e18);
//         console.log("  Order within limits accepted");
//     }

//     /*//////////////////////////////////////////////////////////////
//                          ERROR HANDLING TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testErrorHandling() public {
//         console.log("\n=== TEST: Error Handling ===");

//         bytes32 nonExistentOrder = keccak256("nonexistent");

//         // Test operations on non-existent orders
//         vm.expectRevert(RyzerOrderManager.OrderNotFound.selector);
//         vm.prank(buyer);
//         orderManager.signDocuments(nonExistentOrder);
//         console.log("  Sign documents on non-existent order correctly fails");

//         vm.expectRevert(RyzerOrderManager.OrderNotFound.selector);
//         vm.prank(buyer);
//         orderManager.finalizeOrder(nonExistentOrder);
//         console.log("  Finalize non-existent order correctly fails");

//         vm.expectRevert(RyzerOrderManager.OrderNotFound.selector);
//         vm.prank(buyer);
//         orderManager.cancelOrder(nonExistentOrder);
//         console.log("  Cancel non-existent order correctly fails");

//         vm.expectRevert(RyzerOrderManager.OrderNotFinalized.selector);
//         vm.prank(admin1);
//         orderManager.signRelease(nonExistentOrder);
//         console.log("  Sign release on non-existent order correctly fails");
//     }

//     /*//////////////////////////////////////////////////////////////
//                          HELPER FUNCTIONS
//     //////////////////////////////////////////////////////////////*/

//     function _placeTestOrder() internal returns (bytes32) {
//         RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
//             projectAddress: address(project),
//             escrowAddress: address(escrow),
//             assetId: assetId,
//             amountTokens: TOKEN_AMOUNT,
//             currencyPrice: CURRENCY_PRICE,
//             fees: FEES,
//             currency: RyzerOrderManager.Currency.USDT
//         });

//         vm.prank(buyer);
//         return orderManager.placeOrder(params);
//     }

//     function _createFinalizedOrder() internal returns (bytes32) {
//         bytes32 orderId = _placeTestOrder();

//         vm.prank(buyer);
//         orderManager.signDocuments(orderId);

//         vm.prank(buyer);
//         orderManager.finalizeOrder(orderId);

//         return orderId;
//     }

//     /*//////////////////////////////////////////////////////////////
//                          UPGRADE TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testUpgradeAuthorization() public {
//         console.log("\n=== TEST: Upgrade Authorization ===");

//         // Deploy new implementation
//         RyzerOrderManager newImpl = new RyzerOrderManager();
//         console.log("New implementation deployed at:", address(newImpl));

//         // Non-admin should not be able to upgrade
//         vm.expectRevert();
//         vm.prank(buyer);
//         orderManager.upgradeToAndCall(address(newImpl), "");
//         console.log("  Non-admin correctly rejected from upgrading");

//         // Admin should be able to upgrade
//         vm.prank(owner);
//         orderManager.upgradeToAndCall(address(newImpl), "");
//         console.log("  Admin successfully upgraded contract");

//         // Verify contract still works after upgrade
//         assertTrue(orderManager.hasRole(DEFAULT_ADMIN_ROLE, owner));
//         console.log("  Contract state preserved after upgrade");
//     }

//     /*//////////////////////////////////////////////////////////////
//                          COMPREHENSIVE SCENARIO TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testComplexOrderScenarios() public {
//         console.log("\n=== TEST: Complex Order Scenarios ===");

//         console.log("Scenario 1: Order -> Sign -> Finalize -> Release");
//         bytes32 orderId1 = _placeTestOrder();
//         vm.prank(buyer);
//         orderManager.signDocuments(orderId1);
//         vm.prank(buyer);
//         orderManager.finalizeOrder(orderId1);
//         vm.warp(block.timestamp + 8 days);
//         vm.prank(admin1);
//         orderManager.signRelease(orderId1);
//         vm.prank(admin2);
//         orderManager.signRelease(orderId1);
//         console.log("  Scenario 1 completed");

//         console.log("Scenario 2: Order -> Cancel after delay");
//         bytes32 orderId2 = _placeTestOrder();
//         vm.warp(block.timestamp + 2 days);
//         vm.prank(buyer);
//         orderManager.cancelOrder(orderId2);
//         console.log("  Scenario 2 completed");

//         console.log("Scenario 3: Order -> Expire -> Admin resolves");
//         bytes32 orderId3 = _placeTestOrder();
//         vm.warp(block.timestamp + 8 days);
//         vm.prank(admin1);
//         orderManager.resolveStuckOrder(orderId3);
//         console.log("  Scenario 3 completed");

//         console.log("  All complex scenarios handled correctly");
//     }

//     function testStressTestOrders() public {
//         console.log("\n=== TEST: Stress Test Orders ===");

//         // Create many orders to test gas and storage
//         bytes32[] memory orderIds = new bytes32[](5);

//         for (uint i = 0; i < 5; i++) {
//             RyzerOrderManager.PlaceOrderParams memory params = RyzerOrderManager.PlaceOrderParams({
//                 projectAddress: address(project),
//                 escrowAddress: address(escrow),
//                 assetId: keccak256(abi.encode("asset", i)),
//                 amountTokens: TOKEN_AMOUNT,
//                 currencyPrice: CURRENCY_PRICE,
//                 fees: FEES,
//                 currency: RyzerOrderManager.Currency.USDT
//             });

//             usdt.mint(buyer, 10000e6); // Mint more tokens for each order

//             vm.prank(buyer);
//             orderIds[i] = orderManager.placeOrder(params);

//             console.log("Order", i + 1, "placed:", uint256(orderIds[i]));
//         }

//         // Verify all orders exist and are unique
//         for (uint i = 0; i < 5; i++) {
//             RyzerOrderManager.Order memory order = orderManager.getOrder(orderIds[i]);
//             assertEq(order.buyer, buyer);
//             assertEq(order.amountTokens, TOKEN_AMOUNT);

//             // Check uniqueness
//             for (uint j = i + 1; j < 5; j++) {
//                 assertTrue(orderIds[i] != orderIds[j]);
//             }
//         }

//         console.log("  Stress test completed - all orders unique and valid");
//     }
// }
