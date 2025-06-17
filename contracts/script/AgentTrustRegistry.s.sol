// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {Script, console} from "forge-std/Script.sol";

import { AgentTrustRegistry } from '../src/AgentTrustRegistry.sol';
import { IAttestationCenter } from '../src/interfaces/IAttestationCenter.sol';

contract AgentTrustRegistryDeploy is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        
        console.log("Deploying to Mantle Sepolia...");
        console.log("Deployer: ", msg.sender);
        console.log("Chain ID: ", block.chainid);
        
        // Deploy mock AttestationCenter first
        MockAttestationCenter mockAttestationCenter = new MockAttestationCenter();
        console.log("MockAttestationCenter deployed at: ", address(mockAttestationCenter));
        
        // Deploy AgentTrustRegistry
        AgentTrustRegistry agentTrustRegistry = new AgentTrustRegistry(
            IAttestationCenter(address(mockAttestationCenter))
        );
        console.log("AgentTrustRegistry deployed at: ", address(agentTrustRegistry));
        
        // Set the AVS logic
        mockAttestationCenter.setAvsLogic(address(agentTrustRegistry));
        console.log("AVS logic set in mock attestation center");
        
        // Register some test operators
        mockAttestationCenter.mockRegisterOperator(msg.sender);
        console.log("Registered deployer as test operator");
        
        console.log("=== MANTLE SEPOLIA DEPLOYMENT COMPLETE ===");
        console.log("Network: Mantle Sepolia (Chain ID: 5003)");
        console.log("Explorer: https://explorer.sepolia.mantle.xyz");
        console.log("");
        console.log(" Add these to your .env files:");
        console.log("MOCK_ATTESTATION_CENTER_ADDRESS=", address(mockAttestationCenter));
        console.log("AGENT_TRUST_REGISTRY_ADDRESS=", address(agentTrustRegistry));
        console.log("");
        console.log(" Verify contracts at:");
        console.log("MockAttestationCenter: https://explorer.sepolia.mantle.xyz/address/", address(mockAttestationCenter));
        console.log("AgentTrustRegistry: https://explorer.sepolia.mantle.xyz/address/", address(agentTrustRegistry));
        
        vm.stopBroadcast();
    }
}

// Mock AttestationCenter for testing
contract MockAttestationCenter is IAttestationCenter {
    address public avsLogic;
    mapping(address => uint256) public operatorsIdsByAddress;
    uint256 private nextOperatorId = 1;
    
    function setAvsLogic(address _avsLogic) external {
        avsLogic = _avsLogic;
    }
    
    function mockRegisterOperator(address operator) external {
        operatorsIdsByAddress[operator] = nextOperatorId++;
    }
}