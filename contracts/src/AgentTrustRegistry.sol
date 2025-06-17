// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import "./interfaces/IAgentTrustRegistry.sol";
import "./interfaces/IAvsLogic.sol";
import "./interfaces/IAttestationCenter.sol";

/**
 * @title AgentTrustRegistry
 * @notice Decentralized registry for AI agent trust scores with consensus-based validation
 */
contract AgentTrustRegistry is IAgentTrustRegistry, IAvsLogic {

    // Consensus tracking for each agent
    struct ConsensusData {
        mapping(address => bool) hasVoted;
        mapping(uint8 => uint256) provenanceVotes;
        mapping(uint8 => uint256) performanceVotes;
        mapping(uint8 => uint256) perceptionVotes;
        uint256 totalVotes;
        bool finalized;
    }

    // State variables
    IAttestationCenter public immutable attestationCenter;
    
    mapping(address => AgentRegistration) private _agentRegistrations;
    mapping(address => BadgeInfo) private _agentBadges;
    mapping(address => ConsensusData) private _consensusData;
    mapping(BadgeStatus => uint256) private _badgeHolderCounts;
    mapping(address => uint256) internal penalties; // Track penalties for operators
    
    uint256 private _totalRegisteredAgents;
    uint256 public constant CONSENSUS_THRESHOLD = 2; // 2 out of 3 validators
    uint256 public constant SCORE_UPDATE_INTERVAL = 10; // blocks
    uint256 public constant MIN_SCORE = 0;
    uint256 public constant MAX_SCORE = 100;

    modifier onlyAvsOperator() {
        uint256 operatorIndex = attestationCenter.operatorsIdsByAddress(msg.sender);
        if (operatorIndex == 0) {
            revert NotAnAvsOperator(msg.sender);
        }
        _;
    }

    modifier validScore(uint8 score) {
        if (score > MAX_SCORE) {
            revert InvalidScoreRange(score);
        }
        _;
    }

    modifier agentExists(address agent) {
        if (_agentRegistrations[agent].agentIndex == 0) {
            revert AgentNotRegistered(agent);
        }
        _;
    }

    modifier notBlacklisted(address agent) {
        if (_agentBadges[agent].status == BadgeStatus.Blacklisted) {
            revert AgentBlacklisted(agent, _agentBadges[agent].earnedAt);
        }
        _;
    }

    constructor(IAttestationCenter _attestationCenter) {
        attestationCenter = _attestationCenter;
    }

    /**
     * @notice Register a new agent in the trust registry
     * @param endpoint The agent's endpoint URL for health checks
     */
    function registerAgent(string memory endpoint) 
        external 
        onlyAvsOperator 
        notBlacklisted(msg.sender) 
    {
        if (_agentRegistrations[msg.sender].agentIndex != 0) {
            revert AgentAlreadyRegistered(msg.sender);
        }
        
        uint256 agentIndex = attestationCenter.operatorsIdsByAddress(msg.sender);
        
        _agentRegistrations[msg.sender] = AgentRegistration({
            agentIndex: agentIndex,
            blockRegistered: block.number,
            endpoint: endpoint,
            provenanceScore: 50, // Initial neutral score
            performanceScore: 50,
            perceptionScore: 50,
            lastUpdated: block.timestamp,
            totalBenchmarks: 0
        });

        _totalRegisteredAgents++;
        
        // Initialize with no badge
        _agentBadges[msg.sender] = BadgeInfo({
            status: BadgeStatus.None,
            earnedAt: 0,
            validUntil: 0,
            isPermanent: false
        });
        
        _badgeHolderCounts[BadgeStatus.None]++;

        emit AgentRegistered(msg.sender, endpoint);
    }

    /**
     * @notice Change the endpoint of an already registered agent
     * @param endpoint The new endpoint URL for health checks
     */
    function changeAgentEndpoint(string memory endpoint) 
        external 
        onlyAvsOperator 
    {
        require(_agentRegistrations[msg.sender].blockRegistered != 0, "Agent not registered");
        
        _agentRegistrations[msg.sender].endpoint = endpoint;
        
        emit AgentEndpointChanged(msg.sender, endpoint);
    }

    /**
     * @notice Unregister an agent from the registry
     */
    function unregister() 
        external 
    {
        require(_agentRegistrations[msg.sender].blockRegistered != 0, "Agent not registered");
        
        // Reset registration data
        delete _agentRegistrations[msg.sender];
        
        // Update total count
        _totalRegisteredAgents--;
        
        emit AgentUnregistered(msg.sender);
    }

    /**
     * @notice Submit score votes for an agent (consensus mechanism)
     * @param agent The agent address to score
     * @param provenanceScore Score for provenance (0-100)
     * @param performanceScore Score for performance (0-100)  
     * @param perceptionScore Score for perception (0-100)
     */
    function submitScoreVote(
        address agent,
        uint8 provenanceScore,
        uint8 performanceScore,
        uint8 perceptionScore
    ) 
        external 
        onlyAvsOperator
        agentExists(agent)
        validScore(provenanceScore)
        validScore(performanceScore)
        validScore(perceptionScore)
    {
        ConsensusData storage consensus = _consensusData[agent];
        
        if (consensus.hasVoted[msg.sender]) {
            revert AlreadyVoted(msg.sender, agent);
        }

        if (consensus.finalized) {
            revert ConsensusAlreadyFinalized(agent);
        }
        
        consensus.hasVoted[msg.sender] = true;
        consensus.provenanceVotes[provenanceScore]++;
        consensus.performanceVotes[performanceScore]++;
        consensus.perceptionVotes[perceptionScore]++;
        consensus.totalVotes++;
        
        // Check if consensus reached
        if (consensus.totalVotes >= CONSENSUS_THRESHOLD) {
            _finalizeScores(agent);
        }
    }

    /**
     * @notice Reset consensus for a new voting round
     * @param agent The agent address to reset consensus for
     */
    function resetConsensus(address agent) 
        external 
        onlyAvsOperator 
        agentExists(agent) 
    {
        AgentRegistration memory registration = _agentRegistrations[agent];
        if (block.number < registration.lastUpdated + SCORE_UPDATE_INTERVAL) {
            revert InsufficientConsensus(block.number - registration.lastUpdated, SCORE_UPDATE_INTERVAL);
        }
        
        delete _consensusData[agent];
    }

    /**
     * @notice Finalize agent scores based on consensus
     * @param agent The agent address to finalize scores for
     */
    function _finalizeScores(address agent) internal {
        ConsensusData storage consensus = _consensusData[agent];
        
        uint8 finalProvenance = _getMajorityScore(consensus.provenanceVotes);
        uint8 finalPerformance = _getMajorityScore(consensus.performanceVotes);
        uint8 finalPerception = _getMajorityScore(consensus.perceptionVotes);
        
        // Update agent scores
        AgentRegistration storage registration = _agentRegistrations[agent];
        BadgeStatus oldBadge = _agentBadges[agent].status;
        
        registration.provenanceScore = finalProvenance;
        registration.performanceScore = finalPerformance;
        registration.perceptionScore = finalPerception;
        registration.lastUpdated = block.timestamp;
        registration.totalBenchmarks++;
        
        // Calculate and update badge
        BadgeStatus newBadge = _calculateBadge(finalProvenance, finalPerformance, finalPerception);
        _updateBadge(agent, oldBadge, newBadge);
        
        consensus.finalized = true;
        
        emit AgentScoreUpdated(agent, finalProvenance, finalPerformance, finalPerception);
        emit ConsensusReached(agent, finalProvenance, finalPerformance, finalPerception);
    }

    /**
     * @notice Get majority score from vote mapping
     * @param votes Mapping of scores to vote counts
     * @return The score with the most votes
     */
    function _getMajorityScore(mapping(uint8 => uint256) storage votes) 
        internal 
        view 
        returns (uint8) 
    {
        uint8 majorityScore = 0;
        uint256 maxVotes = 0;
        
        for (uint8 i = 0; i <= MAX_SCORE; i++) {
            if (votes[i] > maxVotes) {
                maxVotes = votes[i];
                majorityScore = i;
            }
        }
        
        return majorityScore;
    }

    /**
     * @notice Calculate badge based on average score
     * @param prov Provenance score
     * @param perf Performance score  
     * @param perc Perception score
     * @return The appropriate badge status
     */
    function _calculateBadge(uint8 prov, uint8 perf, uint8 perc) 
        internal 
        pure 
        returns (BadgeStatus) 
    {
        uint8 avgScore = (prov + perf + perc) / 3;
        
        if (avgScore >= 95) return BadgeStatus.Diamond;
        if (avgScore >= 85) return BadgeStatus.Platinum;
        if (avgScore >= 70) return BadgeStatus.Gold;
        if (avgScore >= 50) return BadgeStatus.Silver;
        if (avgScore >= 30) return BadgeStatus.Bronze;
        return BadgeStatus.None;
    }

    /**
     * @notice Update agent badge and counts
     * @param agent Agent address
     * @param oldBadge Previous badge status
     * @param newBadge New badge status
     */
    function _updateBadge(address agent, BadgeStatus oldBadge, BadgeStatus newBadge) internal {
        if (oldBadge != newBadge) {
            // Update counts
            if (_badgeHolderCounts[oldBadge] > 0) {
                _badgeHolderCounts[oldBadge]--;
            }
            _badgeHolderCounts[newBadge]++;
            
            // Update badge info
            _agentBadges[agent] = BadgeInfo({
                status: newBadge,
                earnedAt: block.timestamp,
                validUntil: block.timestamp + 30 days,
                isPermanent: newBadge >= BadgeStatus.Platinum // Platinum and Diamond are permanent
            });
            
            emit BadgeAwarded(agent, newBadge, block.timestamp);
        }
    }

    // VIEW FUNCTIONS

    /**
     * @notice Get agent's composite trust score
     * @param agent Agent address
     * @return Trust score scaled by 10000 for precision
     */
    function getTrustScore(address agent) 
        external 
        view 
        agentExists(agent)
        returns (uint256) 
    {
        AgentRegistration memory registration = _agentRegistrations[agent];
        uint8 compositeScore = (registration.provenanceScore + registration.performanceScore + registration.perceptionScore) / 3;
        return uint256(compositeScore) * 10000; // Scale for precision
    }

    /**
     * @notice Get individual score components for an agent
     * @param agent Agent address
     * @return provenance Provenance score
     * @return performance Performance score  
     * @return perception Perception score
     */
    function getScoreComponents(address agent) 
        external 
        view 
        agentExists(agent)
        returns (uint8 provenance, uint8 performance, uint8 perception) 
    {
        AgentRegistration memory registration = _agentRegistrations[agent];
        return (registration.provenanceScore, registration.performanceScore, registration.perceptionScore);
    }

    /**
     * @notice Get complete agent registration data
     * @param agent Agent address
     * @return Agent registration struct
     */
    function getAgentRegistration(address agent) 
        external 
        view 
        returns (AgentRegistration memory) 
    {
        return _agentRegistrations[agent];
    }

    /**
     * @notice Get agent's badge information
     * @param agent Agent address
     * @return Badge information struct
     */
    function getAgentBadge(address agent) 
        external 
        view 
        returns (BadgeInfo memory) 
    {
        return _agentBadges[agent];
    }

    /**
     * @notice Get badge distribution statistics
     * @return Array of badge holder counts [None, Bronze, Silver, Gold, Platinum, Diamond, Blacklisted]
     */
    function getBadgeStatistics() 
        external 
        view 
        returns (uint256[7] memory) 
    {
        uint256[7] memory stats;
        for (uint8 i = 0; i < 7; i++) {
            stats[i] = _badgeHolderCounts[BadgeStatus(i)];
        }
        return stats;
    }

    /**
     * @notice Check if agent is eligible for a specific badge level
     * @param agent Agent address
     * @param badgeLevel Badge level to check eligibility for
     * @return eligible True if agent meets the requirements
     */
    function isEligibleForBadge(address agent, BadgeStatus badgeLevel) 
        external 
        view 
        returns (bool eligible) 
    {
        if (_agentRegistrations[agent].agentIndex == 0) {
            return false;
        }
        
        AgentRegistration memory registration = _agentRegistrations[agent];
        uint8 avgScore = (registration.provenanceScore + registration.performanceScore + registration.perceptionScore) / 3;
        
        if (badgeLevel == BadgeStatus.Diamond) return avgScore >= 95;
        if (badgeLevel == BadgeStatus.Platinum) return avgScore >= 85;
        if (badgeLevel == BadgeStatus.Gold) return avgScore >= 70;
        if (badgeLevel == BadgeStatus.Silver) return avgScore >= 50;
        if (badgeLevel == BadgeStatus.Bronze) return avgScore >= 30;
        
        return true; // Everyone is eligible for None badge
    }

    /**
     * @notice Get liveness score for an agent (based on uptime and penalties)
     * @param agent Agent address
     * @return Liveness score based on penalties
     */
    function getLivelinessScore(address agent) 
        external 
        view 
        returns (uint256) 
    {
        uint256 penalty = penalties[agent];
        // Base score of 100, reduced by penalty count
        if (penalty >= 100) {
            return 0;
        }
        return 100 - penalty;
    }

    // PUBLIC MAPPING ACCESSORS

    /**
     * @notice Access agent registration mapping
     * @param agent Agent address
     * @return agentIndex Index of the agent
     * @return blockRegistered Block number when registered
     * @return endpoint Agent endpoint
     * @return provenanceScore Provenance score
     * @return performanceScore Performance score
     * @return perceptionScore Perception score
     * @return lastUpdated Last update timestamp
     * @return totalBenchmarks Total benchmarks count
     */
    function agentRegistrations(address agent) 
        external 
        view 
        returns (
            uint256 agentIndex,
            uint256 blockRegistered,
            string memory endpoint,
            uint8 provenanceScore,
            uint8 performanceScore,
            uint8 perceptionScore,
            uint256 lastUpdated,
            uint256 totalBenchmarks
        ) 
    {
        AgentRegistration memory reg = _agentRegistrations[agent];
        return (
            reg.agentIndex,
            reg.blockRegistered,
            reg.endpoint,
            reg.provenanceScore,
            reg.performanceScore,
            reg.perceptionScore,
            reg.lastUpdated,
            reg.totalBenchmarks
        );
    }

    /**
     * @notice Get count of holders for a specific badge
     * @param badge Badge status to query
     * @return Number of holders
     */
    function badgeHolderCounts(BadgeStatus badge) 
        external 
        view 
        returns (uint256) 
    {
        return _badgeHolderCounts[badge];
    }

    /**
     * @notice Get total number of registered agents
     * @return Total count
     */
    function totalRegisteredAgents() 
        external 
        view 
        returns (uint256) 
    {
        return _totalRegisteredAgents;
    }

    // IAvsLogic implementation
    /**
     * @notice Handle AVS-specific logic
     * @param data Encoded data for processing
     * @return Processed result
     */
    function handleAvsLogic(bytes calldata data) external pure override returns (bytes memory) {
        // Handle AVS logic here
        return data;
    }

    /**
     * @notice Called after task submission to handle penalties
     * @param taskInfo Information about the task
     * @param approved Whether the task was approved
     * @param validatorSignature Signature from validator
     * @param chainInfos Array of chain information
     * @param operatorIds Array of operator IDs
     */
    function afterTaskSubmission(
        IAttestationCenter.TaskInfo memory taskInfo,
        bool approved,
        string memory validatorSignature,
        uint256[2] memory chainInfos,
        uint256[] memory operatorIds
    ) external {
        require(msg.sender == address(attestationCenter), "Only attestation center can call");
        
        // Decode operator address and isHealthy status from task data
        (address operator, bool isHealthy) = abi.decode(taskInfo.data, (address, bool));
        
        // If operator is not healthy, penalize them
        if (!isHealthy) {
            penalties[operator]++;
            emit AgentPenalized(operator);
        }
    }
}