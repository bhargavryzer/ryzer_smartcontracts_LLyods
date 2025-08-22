// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Core contracts
import {RyzerRegistry} from "../src/RyzerRegistry.sol";
import {RyzerCompanyFactory} from "../src/RyzerCompanyFactory.sol";
import {RyzerRealEstateTokenFactory} from "../src/RyzerRealEstateFactory.sol";
import {RyzerEscrow} from "../src/RyzerEscrow.sol";
import {RyzerOrderManager} from "../src/RyzerOrderManager.sol";
import {RyzerDAO} from "../src/RyzerDAO.sol";
import {RyzerRealEstateToken} from "../src/RyzerRealEstateToken.sol";

// Mocks (for testnet deployment)
import {UsdtMock} from "../src/UsdtMock.sol";

contract DeployApothemScript is Script {
    // Contract instances
    RyzerRegistry public registry;
    RyzerCompanyFactory public companyFactory;
    RyzerRealEstateTokenFactory public realEstateFactory;
    RyzerEscrow public escrowImpl;
    RyzerOrderManager public orderManagerImpl;
    RyzerDAO public daoImpl;
    RyzerRealEstateToken public projectTokenImpl;

    // Mock tokens
    UsdtMock public usdt;

    // Deployment parameters
    address public deployer;
    address public admin = 0x2e118e720e4142E75fC79a0f57745Af650d39F94; // Replace with your admin address

    // XDC Apothem testnet parameters
    uint256 public constant APOTHEM_CHAIN_ID = 51;
    string public constant RPC_URL = "https://erpc.apothem.network";

    function run() external {
        // Get deployer from private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.rememberKey(deployerPrivateKey);

        // Set the chain ID for XDC Apothem
        vm.chainId(APOTHEM_CHAIN_ID);

        console.log("Deployer:", deployer);
        console.log("Deploying to XDC Apothem testnet...");

        // Start broadcasting transactions
        vm.startBroadcast(deployer);

        // 1. Deploy mock tokens (for testnet only)
        console.log("Deploying mock tokens...");
        usdt = new UsdtMock();

        // 2. Deploy implementation contracts
        console.log("Deploying implementation contracts...");
        registry = new RyzerRegistry();
        companyFactory = new RyzerCompanyFactory();
        escrowImpl = new RyzerEscrow();
        orderManagerImpl = new RyzerOrderManager();
        daoImpl = new RyzerDAO();
        projectTokenImpl = new RyzerRealEstateToken();

        // 3. Deploy RealEstateTokenFactory (needs implementations)
        console.log("Deploying RyzerRealEstateTokenFactory...");
        realEstateFactory = new RyzerRealEstateTokenFactory();

        // 4. Initialize the registry
        console.log("Initializing registry...");
        registry.initialize(admin);

        // 5. Initialize the company factory
        console.log("Initializing company factory...");
        companyFactory.initialize(admin, address(registry));

        // 6. Transfer ownership of the registry to the company factory
        console.log("Transferring registry ownership to company factory...");
        registry.transferOwnership(address(companyFactory));

        // 7. Set up the real estate factory in the registry
        console.log("Setting up real estate factory in registry...");
        registry.setRealEstateFactory(address(realEstateFactory));

        vm.stopBroadcast();

        // Log all deployed contract addresses
        console.log("\n=== Deployment Summary ===");
        console.log("RyzerRegistry:", address(registry));
        console.log("RyzerCompanyFactory:", address(companyFactory));
        console.log("RyzerRealEstateTokenFactory:", address(realEstateFactory));
        console.log("RyzerEscrow (impl):", address(escrowImpl));
        console.log("RyzerOrderManager (impl):", address(orderManagerImpl));
        console.log("RyzerDAO (impl):", address(daoImpl));
        console.log("RyzerRealEstateToken (impl):", address(projectTokenImpl));
        console.log("USDT Mock:", address(usdt));
    }
}
