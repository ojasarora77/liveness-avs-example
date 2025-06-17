// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import {Script, console} from "forge-std/Script.sol";

// Real AttestationCenter interface (simplified for deployment)
contract AttestationCenter {
    address public avsLogic;
    address public governance;
    mapping(address => uint256) public operatorsIdsByAddress;
    uint256 private nextOperatorId = 1;
    
    // Events
    event OperatorRegistered(address indexed operator, uint256 operatorId);
    event AvsLogicUpdated(address indexed newAvsLogic);
    
    modifier onlyGovernance() {
        require(msg.sender == governance, "Only governance");
        _;
    }
    
    constructor(address _governance) {
        governance = _governance;
    }
    
    function setAvsLogic(address _avsLogic) external onlyGovernance {
        avsLogic = _avsLogic;
        emit AvsLogicUpdated(_avsLogic);
    }
    
    function registerOperator() external {
        require(operatorsIdsByAddress[msg.sender] == 0, "Already registered");
        uint256 operatorId = nextOperatorId++;
        operatorsIdsByAddress[msg.sender] = operatorId;
        emit OperatorRegistered(msg.sender, operatorId);
    }
    
    function getTotalOperators() external view returns (uint256) {
        return nextOperatorId - 1;
    }
}

// Enhanced AgentTrustRegistry with real consensus
contract AgentTrustRegistry {
    struct AgentRegistration {
        uint256 agentIndex;
        uint256 blockRegistered;
        string endpoint;
        uint8 provenanceScore;
        uint8 performanceScore;
        uint8 perceptionScore;
        uint256 lastUpdated;
        uint256 totalBenchmarks;
    }

    struct BadgeInfo {
        uint8 status; // 0=None, 1=Bronze, 2=Silver, 3=Gold, 4=Platinum, 5=Diamond, 6=Blacklisted
        uint256 earnedAt;
        uint256 validUntil;
        bool isPermanent;
    }

    struct ConsensusData {
        mapping(address => bool) hasVoted;
        mapping(uint8 => uint256) provenanceVotes;
        mapping(uint8 => uint256) performanceVotes;
        mapping(uint8 => uint256) perceptionVotes;
        uint256 totalVotes;
        bool finalized;
    }

    AttestationCenter public attestationCenter;
    
    mapping(address => AgentRegistration) public agentRegistrations;
    mapping(address => BadgeInfo) public agentBadges;
    mapping(address => ConsensusData) private consensusData;
    mapping(uint8 => uint256) public badgeHolderCounts;
    
    uint256 public totalRegisteredAgents;
    uint256 public constant CONSENSUS_THRESHOLD = 2; // 2 out of 3 validators
    uint256 public constant SCORE_UPDATE_INTERVAL = 10; // blocks
    
    // Events
    event AgentRegistered(address indexed agent, string endpoint);
    event AgentScoreUpdated(address indexed agent, uint8 provenance, uint8 performance, uint8 perception);
    event BadgeAwarded(address indexed agent, uint8 badge, uint256 timestamp);
    event ConsensusReached(address indexed agent, uint8 provenance, uint8 performance, uint8 perception);

    modifier onlyValidatedOperator() {
        uint256 operatorIndex = attestationCenter.operatorsIdsByAddress(msg.sender);
        require(operatorIndex != 0, "Not a validated AVS operator");
        _;
    }

    constructor(AttestationCenter _attestationCenter) {
        attestationCenter = _attestationCenter;
    }

    function registerAgent(string memory _endpoint) external onlyValidatedOperator {
        require(agentRegistrations[msg.sender].agentIndex == 0, "Agent already registered");
        
        uint256 agentIndex = attestationCenter.operatorsIdsByAddress(msg.sender);
        
        agentRegistrations[msg.sender] = AgentRegistration({
            agentIndex: agentIndex,
            blockRegistered: block.number,
            endpoint: _endpoint,
            provenanceScore: 50, // Initial neutral score
            performanceScore: 50,
            perceptionScore: 50,
            lastUpdated: block.timestamp,
            totalBenchmarks: 0
        });

        totalRegisteredAgents++;
        
        // Initialize with no badge
        agentBadges[msg.sender] = BadgeInfo({
            status: 0,
            earnedAt: 0,
            validUntil: 0,
            isPermanent: false
        });
        
        badgeHolderCounts[0]++; // Increment no-badge count

        emit AgentRegistered(msg.sender, _endpoint);
    } 

    function submitScoreVote(
        address _agent,
        uint8 _provenanceScore,
        uint8 _performanceScore,
        uint8 _perceptionScore
    ) external onlyValidatedOperator {
        require(agentRegistrations[_agent].agentIndex != 0, "Agent not registered");
        require(!consensusData[_agent].hasVoted[msg.sender], "Already voted");
        
        ConsensusData storage consensus = consensusData[_agent];
        
        consensus.hasVoted[msg.sender] = true;
        consensus.provenanceVotes[_provenanceScore]++;
        consensus.performanceVotes[_performanceScore]++;
        consensus.perceptionVotes[_perceptionScore]++;
        consensus.totalVotes++;
        
        // Check if consensus reached
        if (consensus.totalVotes >= CONSENSUS_THRESHOLD && !consensus.finalized) {
            _finalizeScores(_agent);
        }
    }

    function _finalizeScores(address _agent) internal {
        ConsensusData storage consensus = consensusData[_agent];
        
        uint8 finalProvenance = _getMajorityScore(consensus.provenanceVotes);
        uint8 finalPerformance = _getMajorityScore(consensus.performanceVotes);
        uint8 finalPerception = _getMajorityScore(consensus.perceptionVotes);
        
        // Update agent scores
        AgentRegistration storage registration = agentRegistrations[_agent];
        uint8 oldBadge = agentBadges[_agent].status;
        
        registration.provenanceScore = finalProvenance;
        registration.performanceScore = finalPerformance;
        registration.perceptionScore = finalPerception;
        registration.lastUpdated = block.timestamp;
        registration.totalBenchmarks++;
        
        // Calculate and update badge
        uint8 newBadge = _calculateBadge(finalProvenance, finalPerformance, finalPerception);
        _updateBadge(_agent, oldBadge, newBadge);
        
        consensus.finalized = true;
        
        emit AgentScoreUpdated(_agent, finalProvenance, finalPerformance, finalPerception);
        emit ConsensusReached(_agent, finalProvenance, finalPerformance, finalPerception);
    }

    function _getMajorityScore(mapping(uint8 => uint256) storage votes) internal view returns (uint8) {
        uint8 majorityScore = 0;
        uint256 maxVotes = 0;
        
        for (uint8 i = 0; i <= 100; i++) {
            if (votes[i] > maxVotes) {
                maxVotes = votes[i];
                majorityScore = i;
            }
        }
        
        return majorityScore;
    }

    function _calculateBadge(uint8 prov, uint8 perf, uint8 perc) internal pure returns (uint8) {
        uint8 avgScore = (prov + perf + perc) / 3;
        
        if (avgScore >= 95) return 5; // Diamond
        if (avgScore >= 85) return 4; // Platinum
        if (avgScore >= 70) return 3; // Gold
        if (avgScore >= 50) return 2; // Silver
        if (avgScore >= 30) return 1; // Bronze
        return 0; // No badge
    }

    function _updateBadge(address _agent, uint8 oldBadge, uint8 newBadge) internal {
        if (oldBadge != newBadge) {
            // Update counts
            if (badgeHolderCounts[oldBadge] > 0) {
                badgeHolderCounts[oldBadge]--;
            }
            badgeHolderCounts[newBadge]++;
            
            // Update badge info
            agentBadges[_agent] = BadgeInfo({
                status: newBadge,
                earnedAt: block.timestamp,
                validUntil: block.timestamp + 30 days,
                isPermanent: newBadge >= 4 // Platinum and Diamond are permanent
            });
            
            emit BadgeAwarded(_agent, newBadge, block.timestamp);
        }
    }

    // Public view functions for frontend
    function getTrustScore(address _agent) external view returns (uint256) {
        AgentRegistration memory registration = agentRegistrations[_agent];
        require(registration.agentIndex != 0, "Agent not registered");
        
        uint8 compositeScore = (registration.provenanceScore + registration.performanceScore + registration.perceptionScore) / 3;
        return uint256(compositeScore) * 10000; // Scale for precision
    }

    function getScoreComponents(address _agent) external view returns (uint8, uint8, uint8) {
        AgentRegistration memory registration = agentRegistrations[_agent];
        require(registration.agentIndex != 0, "Agent not registered");
        return (registration.provenanceScore, registration.performanceScore, registration.perceptionScore);
    }

    function getAgentBadge(address _agent) external view returns (BadgeInfo memory) {
        return agentBadges[_agent];
    }

    function getBadgeStatistics() external view returns (uint256[7] memory) {
        uint256[7] memory stats;
        for (uint8 i = 0; i < 7; i++) {
            stats[i] = badgeHolderCounts[i];
        }
        return stats;
    }

    function resetConsensus(address _agent) external onlyValidatedOperator {
        // Allow resetting consensus for new voting round
        require(block.number >= agentRegistrations[_agent].lastUpdated + SCORE_UPDATE_INTERVAL, "Too early for new consensus");
        delete consensusData[_agent];
    }
}

contract DeployRealAVS is Script {
    function run() public {
        vm.startBroadcast();
        
        console.log("=== DEPLOYING REAL AVS INFRASTRUCTURE ===");
        console.log("Network: Mantle Sepolia (Chain ID: 5003)");
        console.log("Deployer:", msg.sender);
        console.log("Block:", block.number);
        console.log("");
        
        // Deploy AttestationCenter with deployer as initial governance
        AttestationCenter attestationCenter = new AttestationCenter(msg.sender);
        console.log("AttestationCenter deployed:", address(attestationCenter));
        
        // Deploy AgentTrustRegistry
        AgentTrustRegistry agentTrustRegistry = new AgentTrustRegistry(attestationCenter);
        console.log("AgentTrustRegistry deployed:", address(agentTrustRegistry));
        
        // Set AVS logic in AttestationCenter
        attestationCenter.setAvsLogic(address(agentTrustRegistry));
        console.log("AVS logic configured");
        
        // Register deployer as first operator
        attestationCenter.registerOperator();
        console.log("Deployer registered as operator");
        
        console.log("");
        console.log("=== DEPLOYMENT SUCCESSFUL ===");
        console.log(" Network: Mantle Sepolia");
        console.log("Explorer: https://explorer.sepolia.mantle.xyz");
        console.log("");
        console.log("CONTRACT ADDRESSES (add to .env files):");
        console.log("ATTESTATION_CENTER_ADDRESS=", address(attestationCenter));
        console.log("AGENT_TRUST_REGISTRY_ADDRESS=", address(agentTrustRegistry));
        console.log("");
        console.log("VERIFY ON EXPLORER:");
        console.log("AttestationCenter: https://explorer.sepolia.mantle.xyz/address/", address(attestationCenter));
        console.log("AgentTrustRegistry: https://explorer.sepolia.mantle.xyz/address/", address(agentTrustRegistry));
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Update .env files with these addresses");
        console.log("2. Start AVS services (aggregator, attesters, execution)");
        console.log("3. Register additional operators");
        console.log("4. Connect frontend to real contracts");
        
        vm.stopBroadcast();
    }
}
