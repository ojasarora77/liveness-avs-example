// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import {Script, console} from "forge-std/Script.sol";
import "../src/AgentTrustRegistry.sol";

// Mock AttestationCenter for testing
contract MockAttestationCenter {
    address public avsLogic;
    mapping(address => uint256) public operatorsIdsByAddress;
    uint256 private nextOperatorId = 1;
    
    function setAvsLogic(address _avsLogic) external {
        avsLogic = _avsLogic;
    }
    
    function registerOperator() external {
        operatorsIdsByAddress[msg.sender] = nextOperatorId++;
    }
}

contract TestCompilation is Script {
    function run() public {
        vm.startBroadcast();
        
        console.log("=== TESTING FIXED COMPILATION ===");
        
        // Deploy mock attestation center
        MockAttestationCenter mockCenter = new MockAttestationCenter();
        console.log("MockAttestationCenter deployed:", address(mockCenter));
        
        // Deploy AgentTrustRegistry with fixed code
        AgentTrustRegistry registry = new AgentTrustRegistry(IAttestationCenter(address(mockCenter)));
        console.log("AgentTrustRegistry deployed:", address(registry));
        
        // Set AVS logic
        mockCenter.setAvsLogic(address(registry));
        
        // Register as operator
        mockCenter.registerOperator();
        
        // Test basic functionality
        registry.registerAgent("https://test-agent.example.com");
        console.log("Test agent registered successfully");
        
        uint256 totalAgents = registry.totalRegisteredAgents();
        console.log("Total agents:", totalAgents);
        
        console.log(" All compilation errors fixed!");
        
        vm.stopBroadcast();
    }
}