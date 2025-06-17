// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

/*______     __      __                              __      __ 
 /      \   /  |    /  |                            /  |    /  |
/$$$$$$  | _$$ |_   $$ |____    ______   _______   _$$ |_   $$/   _______ 
$$ |  $$ |/ $$   |  $$      \  /      \ /       \ / $$   |  /  | /       |
$$ |  $$ |$$$$$$/   $$$$$$$  |/$$$$$$  |$$$$$$$  |$$$$$$/   $$ |/$$$$$$$/ 
$$ |  $$ |  $$ | __ $$ |  $$ |$$    $$ |$$ |  $$ |  $$ | __ $$ |$$ |
$$ \__$$ |  $$ |/  |$$ |  $$ |$$$$$$$$/ $$ |  $$ |  $$ |/  |$$ |$$ \_____ 
$$    $$/   $$  $$/ $$ |  $$ |$$       |$$ |  $$ |  $$  $$/ $$ |$$       |
 $$$$$$/     $$$$/  $$/   $$/  $$$$$$$/ $$/   $$/    $$$$/  $$/  $$$$$$$/
*/
/**
 * @author Othentic Labs LTD.
 * @notice Terms of Service: https://www.othentic.xyz/terms-of-service
 * @notice Adapted for AgentTrustRegistry system
 */

import {Script, console} from "forge-std/Script.sol";
import { IAttestationCenter } from "../src/interfaces/IAttestationCenter.sol";
import { IAgentTrustRegistry } from "../src/interfaces/IAgentTrustRegistry.sol";

/**
 * @title RegisterAgentEndpoint
 * @notice Script to register an agent with monitoring endpoint in the AgentTrustRegistry
 * 
 * How to use:
 * 1. Either `source ../../.env` or replace variables in command
 * 2. For new registration:
 *    forge script RegisterAgentEndpoint --rpc-url $L2_RPC --private-key $PRIVATE_KEY 
 *    --broadcast -vvvv --sig="run(address,string)" $ATTESTATION_CENTER_ADDRESS $ENDPOINT
 * 
 * 3. For Mantle Sepolia:
 *    forge script RegisterAgentEndpoint --rpc-url https://rpc.sepolia.mantle.xyz --private-key $PRIVATE_KEY 
 *    --broadcast -vvvv --sig="run(address,string)" $MOCK_ATTESTATION_CENTER_ADDRESS "https://my-agent.com/health"
 */
contract RegisterAgentEndpoint is Script {
    function setUp() public {}

    function run(address attestationCenter, string memory endpoint) public {
        vm.startBroadcast();

        console.log("=== AGENT REGISTRATION ===");
        console.log("Attestation Center:", attestationCenter);
        console.log("Agent Address:", msg.sender);
        console.log("Endpoint:", endpoint);
        console.log("Chain ID:", block.chainid);

        IAttestationCenter attestationCenterContract = IAttestationCenter(attestationCenter);
        
        // Get the AgentTrustRegistry address from attestation center
        address agentTrustRegistryAddress = attestationCenterContract.avsLogic();
        console.log("AgentTrustRegistry:", agentTrustRegistryAddress);
        
        IAgentTrustRegistry agentTrustRegistry = IAgentTrustRegistry(agentTrustRegistryAddress);
        
        // Check if agent is already registered  
        // agentRegistrations returns: (agentIndex, blockRegistered, endpoint, provenanceScore, performanceScore, perceptionScore, lastUpdated, totalBenchmarks)
        (uint256 agentIndex, uint256 blockRegistered, string memory currentEndpoint, , , , , ) = agentTrustRegistry.agentRegistrations(msg.sender);
        
        if (agentIndex == 0) {
            // Agent not registered - register new agent
            console.log("Registering new agent...");
            agentTrustRegistry.registerAgent(endpoint);
            console.log(" Agent registered successfully!");
        } else {
            // Agent already registered - update endpoint
            console.log("Agent already registered (block:", blockRegistered, ")");
            console.log("Current endpoint:", currentEndpoint);
            console.log("Updating endpoint to:", endpoint);
            agentTrustRegistry.changeAgentEndpoint(endpoint);
            console.log(" Agent endpoint updated successfully!");
        }

        // Verify registration
        // agentRegistrations returns: (agentIndex, blockRegistered, endpoint, provenanceScore, performanceScore, perceptionScore, lastUpdated, totalBenchmarks)
        (uint256 newAgentIndex, uint256 newBlockRegistered, string memory newEndpoint, , , , , ) = agentTrustRegistry.agentRegistrations(msg.sender);
        console.log("=== VERIFICATION ===");
        console.log("Agent Index:", newAgentIndex);
        console.log("Block Registered:", newBlockRegistered);
        console.log("Endpoint:", newEndpoint);
        
        // Get total registered agents
        uint256 totalAgents = agentTrustRegistry.totalRegisteredAgents();
        console.log("Total Registered Agents:", totalAgents);

        vm.stopBroadcast();
    }

    /**
     * @notice Alternative function to register multiple test agents at once
     * @param attestationCenter Address of the attestation center
     */
    function runBatch(address attestationCenter) public {
        vm.startBroadcast();

        console.log("=== BATCH AGENT REGISTRATION ===");
        
        IAttestationCenter attestationCenterContract = IAttestationCenter(attestationCenter);
        IAgentTrustRegistry agentTrustRegistry = IAgentTrustRegistry(attestationCenterContract.avsLogic());

        // Register multiple test agents with different endpoints
        string[5] memory testEndpoints = [
            "https://defi-optimizer.agent.com/health",
            "https://social-manager.agent.com/health", 
            "https://gaming-bot.agent.com/health",
            "https://research-assistant.agent.com/health",
            "https://experimental-bot.agent.com/health"
        ];

        for (uint i = 0; i < testEndpoints.length; i++) {
            try agentTrustRegistry.registerAgent(testEndpoints[i]) {
                console.log(" Registered agent with endpoint:", testEndpoints[i]);
            } catch {
                console.log("Failed to register or agent already exists");
                // Try to update endpoint instead
                try agentTrustRegistry.changeAgentEndpoint(testEndpoints[i]) {
                    console.log("Updated endpoint to:", testEndpoints[i]);
                } catch {
                    console.log("Failed to update endpoint");
                }
            }
        }

        uint256 totalAgents = agentTrustRegistry.totalRegisteredAgents();
        console.log("=== BATCH COMPLETE ===");
        console.log("Total Registered Agents:", totalAgents);

        vm.stopBroadcast();
    }
}