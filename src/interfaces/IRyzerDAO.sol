// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IRyzerDAO
/// @notice Interface for RyzerDAO governance engine
interface IRyzerDAO {
    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct Proposal {
        uint48 startTime;
        uint48 endTime;
        uint48 deadline;
        uint40 forVotes;
        uint40 againstVotes;
        uint8 signatureCount;
        bool executed;
    }

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/
    event DAOInitialized(address indexed ryzerXToken, address indexed project, uint8 quorumThreshold);
    event CoreContractsSet(address indexed ryzerXToken, address indexed project);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, bytes32 descriptionHash, uint48 delay);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalSigned(uint256 indexed proposalId, address indexed signer);
    event ProposalExecuted(uint256 indexed proposalId);
    event FallbackExecution(uint256 indexed proposalId);
    event SignerAdded(address indexed signer);
    event SignerRevoked(address indexed signer);
    event GovernanceParamsSet(uint8 requiredSignatures, uint8 quorumThreshold);

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress();
    error InvalidDelay();
    error InsufficientBalance();
    error ProposalNotFound();
    error VotingPeriodEnded();
    error AlreadyVoted();
    error AlreadySigned();
    error InsufficientQuorum();
    error InsufficientSignatures();
    error ProposalExpired();
    error ProposalNotExpired();
    error InvalidSignatureCount();
    error InvalidParameter();
    error CannotModifyAdmin();

    /*//////////////////////////////////////////////////////////////
                           INITIALIZER
    //////////////////////////////////////////////////////////////*/
    function initialize(address _project, address _ryzerXToken, uint8 _quorumThreshold) external;

    /*//////////////////////////////////////////////////////////////
                        ADMIN-ONLY CONFIGURATION
    //////////////////////////////////////////////////////////////*/
    function setCoreContracts(address _ryzerXToken, address _project) external;
    function setGovernanceParams(uint8 _requiredSignatures, uint8 _quorumThreshold) external;

    /*//////////////////////////////////////////////////////////////
                           PROPOSAL LIFECYCLE
    //////////////////////////////////////////////////////////////*/
    function propose(string calldata description, uint48 delay) external;

    /*//////////////////////////////////////////////////////////////
                              VOTING
    //////////////////////////////////////////////////////////////*/
    function vote(uint256 proposalId, bool support) external;

    /*//////////////////////////////////////////////////////////////
                           SIGNING & EXECUTION
    //////////////////////////////////////////////////////////////*/
    function signProposal(uint256 proposalId) external;
    function executeFallback(uint256 proposalId) external;

    /*//////////////////////////////////////////////////////////////
                         SIGNER MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    function addSigner(address signer) external;
    function revokeSigner(address signer) external;

    /*//////////////////////////////////////////////////////////////
                         PAUSABILITY
    //////////////////////////////////////////////////////////////*/
    function pause() external;
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                         VIEW HELPERS
    //////////////////////////////////////////////////////////////*/
    function getProposalStatus(uint256 proposalId) external view returns (Proposal memory);

    function ryzerXToken() external view returns (IERC20);
    function project() external view returns (address);
    function proposalCount() external view returns (uint16);
    function requiredSignatures() external view returns (uint8);
    function quorumThreshold() external view returns (uint8);
}
