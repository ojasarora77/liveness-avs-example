// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

interface IAgentTrustRegistry {
    
    // Enums and Structs - Define once in interface
    enum BadgeStatus {
        None,        // 0
        Bronze,      // 1
        Silver,      // 2
        Gold,        // 3
        Platinum,    // 4
        Diamond,     // 5
        Blacklisted  // 6
    }

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
        BadgeStatus status;
        uint256 earnedAt;
        uint256 validUntil;
        bool isPermanent;
    }

    // Events
    event AgentRegistered(address indexed agent, string endpoint);
    event AgentEndpointChanged(address indexed agent, string endpoint);
    event AgentUnregistered(address indexed agent);
    event AgentPenalized(address indexed agent);
    event AgentScoreUpdated(address indexed agent, uint8 provenance, uint8 performance, uint8 perception);
    event BadgeAwarded(address indexed agent, BadgeStatus badge, uint256 timestamp);
    event ConsensusReached(address indexed agent, uint8 provenance, uint8 performance, uint8 perception);

    // Errors
    error AgentAlreadyRegistered(address agent);
    error AgentNotRegistered(address agent);
    error NotAnAvsOperator(address caller);
    error AgentBlacklisted(address agent, uint256 blacklistedAt);
    error AlreadyVoted(address validator, address agent);
    error ConsensusAlreadyFinalized(address agent);
    error InvalidScoreRange(uint8 score);
    error InsufficientConsensus(uint256 votes, uint256 required);

    // Core Functions
    function registerAgent(string memory endpoint) external;
    function changeAgentEndpoint(string memory endpoint) external;
    function unregister() external;
    function submitScoreVote(address agent, uint8 provenanceScore, uint8 performanceScore, uint8 perceptionScore) external;
    function resetConsensus(address agent) external;

    // View Functions
    function getTrustScore(address agent) external view returns (uint256);
    function getLivelinessScore(address agent) external view returns (uint256);
    function getScoreComponents(address agent) external view returns (uint8 provenance, uint8 performance, uint8 perception);
    function getAgentRegistration(address agent) external view returns (AgentRegistration memory);
    function getAgentBadge(address agent) external view returns (BadgeInfo memory);
    function getBadgeStatistics() external view returns (uint256[7] memory);
    function isEligibleForBadge(address agent, BadgeStatus badgeLevel) external view returns (bool);
    
    // Public mappings (as view functions)
    function agentRegistrations(address agent) external view returns (
        uint256 agentIndex,
        uint256 blockRegistered,
        string memory endpoint,
        uint8 provenanceScore,
        uint8 performanceScore,
        uint8 perceptionScore,
        uint256 lastUpdated,
        uint256 totalBenchmarks
    );
    
    function badgeHolderCounts(BadgeStatus badge) external view returns (uint256);
    function totalRegisteredAgents() external view returns (uint256);
}