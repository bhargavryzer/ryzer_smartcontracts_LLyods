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
import {RyzerCompany} from "../src/RyzerCompany.sol";
import {UsdtMock} from "../src/UsdtMock.sol";
import {UsdcMock} from "../src/UsdcMock.sol";
import {RyzerToken} from "../src/RyzerToken.sol";
import {ModularCompliance} from "../src/TREX/compliance/modular/ModularCompliance.sol";
import {IdentityRegistry} from "../src/TREX/registry/implementation/IdentityRegistry.sol";

contract DeployApothemScript is Script {
    // Contract instances
    RyzerRegistry public registry;
    RyzerCompanyFactory public companyFactory;
    RyzerRealEstateTokenFactory public realEstateFactory;
    RyzerEscrow public escrowImpl;
    RyzerOrderManager public orderManagerImpl;
    RyzerDAO public daoImpl;
    RyzerRealEstateToken public projectTokenImpl;
    RyzerCompany public ryzerCompanyImpl;
    ModularCompliance public modularCompliance;
    IdentityRegistry public identityRegistry;

    // Mock tokens
    UsdtMock public usdt;
    UsdcMock public usdc;
    RyzerToken public ryzerToken;

    // Deployment parameters
    address public deployer;
    address public admin = 0xFDa522b8c863ed7Abf681d0c86Cc0c5DCb95d4E6; // Replace with your admin address

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
        usdc = new UsdcMock();
        ryzerToken = new RyzerToken();

        // 2. Deploy implementation contracts
        console.log("Deploying implementation contracts...");
        ryzerCompanyImpl = new RyzerCompany();
        companyFactory = new RyzerCompanyFactory();
        projectTokenImpl = new RyzerRealEstateToken();
        daoImpl = new RyzerDAO();
        escrowImpl = new RyzerEscrow();
        orderManagerImpl = new RyzerOrderManager();
      
        realEstateFactory = new RyzerRealEstateTokenFactory();
        registry = new RyzerRegistry(); //proxy
        modularCompliance = new ModularCompliance();
        identityRegistry = new IdentityRegistry();

        // 4. Initialize the registry
        console.log("Initializing registry...");
        //deploying proxy
        bytes memory ryzerRegistyInitData = abi.encodeWithSignature("initialize()");
        ERC1967Proxy ryzerRegistryProxy = new ERC1967Proxy(address(registry), ryzerRegistyInitData);

        // 5. Initialize the company factory
        console.log("Initializing company factory...");
        bytes memory ryzerCompanyFactoryInitData = abi.encodeWithSignature("initialize(address)", ryzerCompanyImpl);
        ERC1967Proxy ryzerCompanyFactoryProxy = new ERC1967Proxy(address(companyFactory), ryzerCompanyFactoryInitData);

        // 6. Initialize the realEstate factory
        console.log("Initializing realEstateFactory ...");
        address ryzerXToken = 0xeF4A07fA23A4BFe6aBf3b5B8791E90ea2E83081E;
        bytes memory realEstateFactoryInitData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address)",
            usdc,
            usdt,
            ryzerToken,
            projectTokenImpl,
            escrowImpl,
            orderManagerImpl,
            daoImpl
        );
        ERC1967Proxy ryzeRealEstateFactoryProxy =
            new ERC1967Proxy(address(realEstateFactory), realEstateFactoryInitData);

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
